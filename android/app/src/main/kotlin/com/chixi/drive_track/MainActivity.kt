package com.chixi.drive_track

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.view.WindowManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.View
import android.widget.VideoView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class TrackService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("drivetrack", "驰迹记录", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(ch)
        }
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n: Notification = NotificationCompat.Builder(this, "drivetrack")
            .setContentTitle("驰迹记录中")
            .setContentText("正在记录轨迹、G 值与传感器数据")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
        startForeground(1, n)
        return START_STICKY
    }
}

class MainActivity : FlutterActivity(), SensorEventListener, LocationListener {
    private var locSink: EventChannel.EventSink? = null
    private var senSink: EventChannel.EventSink? = null
    private var bleDevSink: EventChannel.EventSink? = null
    private var bleDataSink: EventChannel.EventSink? = null
    // 分步授权：每个 step 一个 requestCode，结果按 code 存 map 分发，杜绝单一
    // pendingPermResult 被后一次请求覆盖丢结果。旧 1001 保留给 foreground 一步。
    private val pendingPermResults = mutableMapOf<Int, MethodChannel.Result>()
    private val permStepByCode = mapOf(1001 to "foreground", 1002 to "extras", 1003 to "background", 1004 to "camera", 1005 to "microphone")
    // v0.1.3 通用 BLE：带服务过滤的扫描 + 通用读写订阅（单 GATT，一次一台）。
    private var scanServiceFilter: List<String>? = null
    private var pendingReadResult: MethodChannel.Result? = null
    private var pendingReadUuid: String? = null

    private lateinit var sensorManager: SensorManager
    private lateinit var locationManager: LocationManager
    private var latestRv: FloatArray? = null
    private var latestPressure: Float = 0f

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var gatt: BluetoothGatt? = null
    private var lastBleAddress: String? = null
    private var autoReconnect = true
    private var reconnectAttempts = 0
    private val handler = Handler(Looper.getMainLooper())
    private var prevCrankRevs: Int? = null
    private var prevCrankTime: Int? = null
    // v0.1.2 同步视频：Camera2 无预览录制 + MediaRecorder，10 分钟一段。
    private var pickResult: MethodChannel.Result? = null
    private var pickKind: String = ""
    // v0.1.7 拍照打点：与 pickFile 分开的 result/file，避免两者并发互相覆盖。
    private var photoResult: MethodChannel.Result? = null
    private var photoFile: File? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var mediaRecorder: MediaRecorder? = null
    private var videoSegments = mutableListOf<String>()
    private var videoRecording = false
    // v0.1.4 TTS（语音播报）+ 直连卫星。队列由 Dart 侧管理，原生只做单条播报
    // 与完成回调；已有通道名与分步权限逻辑一律不动，只新增方法。
    private var ttsSink: EventChannel.EventSink? = null
    private var gnssSink: EventChannel.EventSink? = null
    private var tts: TextToSpeech? = null
    private var ttsInitDone = false
    private var ttsReady = false
    private var ttsLanguage = "none"
    private var ttsRate = 1.0f
    private var ttsPitch = 1.0f
    private var ttsVolume = 1.0f
    private val ttsPendingActions = mutableListOf<() -> Unit>()
    // v0.1.9：用户在引擎选择器里选中的 TTS 引擎包名；null = 系统默认引擎。
    private var ttsEngineOverride: String? = null
    private var customAudioPlayer: MediaPlayer? = null
    private var locationActive = false
    private var directSatelliteMode = false
    private var lastGnssUsed = -1
    private var lastGnssSnapshot: Map<String, Any>? = null
    // Any 类型存回调，避免在 API < 24 设备上加载 GnssStatus 类；
    // 仅在 SDK >= N 时创建与注册（见 registerGnssCallback）。
    private var gnssCallback: Any? = null

    private val bleScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val dev = result.device
            val uuids = result.scanRecord?.serviceUuids?.map { it.uuid.toString() } ?: emptyList()
            val type = when {
                uuids.any { it.contains("1818") } -> "功率计"
                uuids.any { it.contains("1816") } -> "踏频/速度传感器"
                uuids.any { it.contains("180d") } -> "心率带"
                else -> "未知传感器"
            }
            bleDevSink?.success(mapOf(
                "address" to dev.address,
                "name" to (dev.name ?: dev.address),
                "rssi" to result.rssi,
                "type" to type,
                "serviceUuids" to uuids
            ))
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                reconnectAttempts = 0
                bleDataSink?.success(mapOf("type" to "connected", "address" to gatt.device.address))
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                bleDataSink?.success(mapOf("type" to "disconnected"))
                if (autoReconnect && lastBleAddress != null && reconnectAttempts < 6) {
                    reconnectAttempts++
                    handler.postDelayed({
                        val dev = bluetoothAdapter?.getRemoteDevice(lastBleAddress)
                        if (dev != null) {
                            this@MainActivity.gatt = dev.connectGatt(this@MainActivity, false, this)
                        }
                    }, 5000)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            for (svc in gatt.services) {
                val su = svc.uuid.toString()
                for (ch in svc.characteristics) {
                    val cu = ch.uuid.toString()
                    when {
                        su.contains("1818") && cu.contains("2a63") -> enableNotify(gatt, ch)
                        su.contains("1816") && cu.contains("2a5b") -> enableNotify(gatt, ch)
                        su.contains("180d") && cu.contains("2a37") -> enableNotify(gatt, ch)
                        su.contains("180f") && cu.contains("2a19") -> gatt.readCharacteristic(ch)
                    }
                }
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray) {
            parseBle(ch.uuid.toString(), value)
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic) {
            parseBle(ch.uuid.toString(), ch.value ?: return)
        }

        override fun onCharacteristicRead(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            if (ch.uuid.toString().contains("2a19") && value.isNotEmpty()) {
                bleDataSink?.success(mapOf("type" to "battery", "value" to (value[0].toInt() and 0xFF)))
            }
            val pr = pendingReadResult
            if (pr != null && pendingReadUuid == ch.uuid.toString()) {
                pendingReadResult = null
                pendingReadUuid = null
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    pr.success(value.map { it.toInt() and 0xFF })
                } else {
                    pr.error("READ_FAILED", "status=$status", null)
                }
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, status: Int) {
            if (ch.uuid.toString().contains("2a19")) {
                val v = ch.value
                if (v != null && v.isNotEmpty()) {
                    bleDataSink?.success(mapOf("type" to "battery", "value" to (v[0].toInt() and 0xFF)))
                }
            }
        }
    }

    private fun enableNotify(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic) {
        gatt.setCharacteristicNotification(ch, true)
        val desc = ch.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34b0"))
        if (desc != null) {
            desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            gatt.writeDescriptor(desc)
        }
    }

    private fun u16(v: ByteArray, off: Int): Int =
        (v[off].toInt() and 0xFF) or ((v[off + 1].toInt() and 0xFF) shl 8)

    private fun parseBle(uuid: String, value: ByteArray) {
        when {
            uuid.contains("2a63") -> {
                if (value.size >= 3) {
                    val power = (value[1].toInt() and 0xFF) or ((value[2].toInt() shl 8))
                    bleDataSink?.success(mapOf("type" to "power", "value" to power.toDouble()))
                }
            }
            uuid.contains("2a5b") -> {
                if (value.isEmpty()) return
                val flags = value[0].toInt()
                var off = 1
                if (flags and 0x01 != 0) off += 6
                if (flags and 0x02 != 0 && value.size >= off + 4) {
                    val revs = u16(value, off)
                    val time = u16(value, off + 2)
                    if (prevCrankRevs != null && prevCrankTime != null) {
                        var dRevs = revs - prevCrankRevs!!
                        var dTime = time - prevCrankTime!!
                        if (dRevs < 0) dRevs += 65536
                        if (dTime < 0) dTime += 65536
                        if (dTime > 0 && dRevs >= 0) {
                            val cad = dRevs / (dTime / 1024.0) * 60.0
                            if (cad in 0.0..300.0) {
                                bleDataSink?.success(mapOf("type" to "cadence", "value" to cad))
                            }
                        }
                    }
                    prevCrankRevs = revs
                    prevCrankTime = time
                }
            }
            uuid.contains("2a37") -> {
                if (value.isEmpty()) return
                val flags = value[0].toInt()
                val hr = if (flags and 0x01 == 0) {
                    if (value.size >= 2) value[1].toInt() and 0xFF else return
                } else {
                    if (value.size >= 3) u16(value, 1) else return
                }
                bleDataSink?.success(mapOf("type" to "hr", "value" to hr))
            }
            // v0.1.3 通用通知（GoPro 响应、BleDIY UART 等未知特征）：原样转发字节，
            // Dart 侧按特征 UUID 分发解析，绝不在原生层猜协议。
            else -> {
                bleDataSink?.success(mapOf(
                    "type" to "bleNotification",
                    "characteristicUuid" to uuid,
                    "bytes" to value.map { it.toInt() and 0xFF }
                ))
            }
        }
    }

    // v0.1.3 通用 BLE 辅助：按 UUID 在已连接 GATT 里找特征。
    private fun findCharacteristic(serviceUuid: String, characteristicUuid: String): BluetoothGattCharacteristic? {
        val g = gatt ?: return null
        for (svc in g.services) {
            if (!svc.uuid.toString().contains(serviceUuid, ignoreCase = true) &&
                svc.uuid.toString() != serviceUuid) continue
            for (ch in svc.characteristics) {
                if (ch.uuid.toString().contains(characteristicUuid, ignoreCase = true) ||
                    ch.uuid.toString() == characteristicUuid) return ch
            }
        }
        return null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // v0.1.7 视频回顾：Flutter 内置 AndroidView + 原生 VideoView 应用内播放。
        // 零第三方插件、无 ffmpeg、无烧录重编码；HUD 由 Dart 层叠加在画面上。
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "drivetrack/video_view",
            DriveTrackVideoViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        bluetoothAdapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "drivetrack/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFilesDir" -> result.success(filesDir.absolutePath)
                    // v1.0.3：切换桌面启动图标 alias。Manifest 里主 Activity
                    // 不带 LAUNCHER 过滤器，两个 alias（LauncherRed 默认
                    // 启用、LauncherBlue 默认禁用）各带 LAUNCHER 过滤器
                    // 与对应图标；此处启用选中 alias、禁用另一个。
                    // DONT_KILL_APP：切换瞬间不杀 App、不丢数据，桌面
                    // 图标由启动器在刷新后变化（部分厂商 ROM 有延迟，
                    // 见主题页回落说明）。
                    "setAppIcon" -> {
                        val icon = call.argument<String>("icon") ?: "red"
                        try {
                            val pm = packageManager
                            val redAlias = ComponentName(this, "com.chixi.drive_track.LauncherRed")
                            val blueAlias = ComponentName(this, "com.chixi.drive_track.LauncherBlue")
                            val (enable, disable) = if (icon == "blue") blueAlias to redAlias else redAlias to blueAlias
                            pm.setComponentEnabledSetting(enable, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                            pm.setComponentEnabledSetting(disable, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "getCacheDir" -> result.success(cacheDir.absolutePath)
                    "startForeground" -> {
                        val intent = Intent(this, TrackService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stopForeground" -> {
                        stopService(Intent(this, TrackService::class.java))
                        result.success(null)
                    }
                    // v0.1.8 记录时保持屏幕常亮：根因是系统锁屏超时自动熄屏，
                    // 不是定位权限问题。FLAG_KEEP_SCREEN_ON 只属于当前窗口，
                    // Activity 销毁即失效，绝不会在 App 退出后残留。返回
                    // {ok, enabled}，失败时 Dart 侧必须按“未开启”显示。
                    "setKeepScreenOn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        try {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(mapOf("ok" to true, "enabled" to enabled))
                        } catch (e: Exception) {
                            result.success(mapOf("ok" to false, "enabled" to false, "error" to (e.message ?: "unknown")))
                        }
                    }
                    // v0.1.8 电池优化检测 + 跳设置页：只读检测，不自动申请白名单；
                    // 跳转走 ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS，
                    // 让用户在系统页手动选本应用（厂商后台管理各家不同，
                    // 仍需在厂商管家/后台管理里允许后台运行）。
                    "checkBatteryOptimization" -> {
                        try {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            result.success(mapOf("ignored" to pm.isIgnoringBatteryOptimizations(packageName)))
                        } catch (_: Exception) {
                            result.success(mapOf("ignored" to false))
                        }
                    }
                    "openBatteryOptimizationSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NO_SETTINGS", e.message, null)
                        }
                    }
                    // v1.0.2 跳系统 TTS 设置页：用 android.settings.TTS_SETTINGS
                    // （系统“文字转语音输出”页）。注意：Settings.ACTION_TEXT_TO_SPEECH_SETTINGS
                    // 在本 SDK 里不存在、编译不过，工人原写法已修正为字面动作名。
                    // 刻意不用 TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA /
                    // ACTION_CHECK_TTS_DATA：无 Google TTS 的设备上没有处理
                    // 它们的 Activity，直接 startActivity 会抛
                    // ActivityNotFoundException 导致崩溃；也不用
                    // ACTION_VOICE_INPUT_SETTINGS（语音输入，不是 TTS）。
                    // try/catch 兜底：个别 OEM 无此设置页时报 NO_TTS_SETTINGS，
                    // Dart 侧改显示文字引导，不再起第二个 Intent 猜路径。
                    "openTtsSettings" -> {
                        try {
                            startActivity(Intent("android.settings.TTS_SETTINGS"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NO_TTS_SETTINGS", e.message, null)
                        }
                    }
                    "startLocation" -> {
                        startLocation()
                        result.success(null)
                    }
                    "stopLocation" -> {
                        locationActive = false
                        unregisterGnssCallback()
                        try { locationManager.removeUpdates(this) } catch (_: Exception) {}
                        result.success(null)
                    }
                    // v0.1.4 语音播报：语言优先中文，不可用时回退默认语言；
                    // 无引擎时返回 ok=false + error，不静默假装播了。
                    // 完成回调经 drivetrack/tts 事件流回 Dart，队列由 Dart 侧管理。
                    "ttsIsAvailable" -> whenTtsReady {
                        result.success(ttsStatusMap())
                    }
                    "ttsSpeak" -> {
                        val text = call.argument<String>("text") ?: ""
                        val uid = call.argument<String>("utteranceId")
                            ?: "dt_${System.currentTimeMillis()}"
                        ttsSpeak(text, uid, result)
                    }
                    "ttsStop" -> {
                        try { tts?.stop() } catch (_: Exception) {}
                        result.success(null)
                    }
                    "ttsSetRate" -> {
                        ttsRate = (call.argument<Number>("rate")?.toFloat() ?: 1.0f)
                            .coerceIn(0.25f, 4.0f)
                        try { tts?.setSpeechRate(ttsRate) } catch (_: Exception) {}
                        result.success(null)
                    }
                    "ttsSetPitch" -> {
                        ttsPitch = (call.argument<Number>("pitch")?.toFloat() ?: 1.0f)
                            .coerceIn(0.25f, 4.0f)
                        try { tts?.setPitch(ttsPitch) } catch (_: Exception) {}
                        result.success(null)
                    }
                    "ttsSetVolume" -> {
                        ttsVolume = (call.argument<Number>("volume")?.toFloat() ?: 1.0f)
                            .coerceIn(0.0f, 1.0f)
                        result.success(null)
                    }
                    // v0.1.9 TTS 引擎选择器：列出系统已装引擎 + 当前默认引擎；
                    // 切换引擎时重建 TextToSpeech 实例，语言仍优先中文。
                    "ttsEngines" -> whenTtsReady {
                        val engines = try {
                            tts?.engines?.map { it.name } ?: emptyList()
                        } catch (_: Exception) { emptyList<String>() }
                        val current = try { tts?.defaultEngine ?: "" } catch (_: Exception) { "" }
                        result.success(mapOf("engines" to engines, "current" to current))
                    }
                    "ttsSetEngine" -> {
                        val engine = call.argument<String>("engine") ?: ""
                        try { tts?.shutdown() } catch (_: Exception) {}
                        tts = null
                        ttsInitDone = false
                        ttsReady = false
                        ttsLanguage = "none"
                        ttsEngineOverride = engine.ifEmpty { null }
                        whenTtsReady {
                            result.success(mapOf("ok" to ttsReady))
                        }
                    }
                    // v0.1.9 自定义语音服务回放：播放 Dart 侧保存的音频文件。
                    "playAudioFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        try {
                            customAudioPlayer?.release()
                            val mp = MediaPlayer()
                            customAudioPlayer = mp
                            mp.setDataSource(path)
                            mp.setOnCompletionListener { it.release(); customAudioPlayer = null }
                            mp.setOnErrorListener { player, _, _ -> player.release(); customAudioPlayer = null; true }
                            mp.prepare()
                            mp.start()
                            result.success(mapOf("ok" to true))
                        } catch (_: Exception) {
                            result.success(mapOf("ok" to false, "error" to "play_failed"))
                        }
                    }
                    // v0.1.4 设备静音判断：响铃模式非正常，或音乐流音量为 0。
                    "audioMuted" -> {
                        try {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val ringerStr = when (am.ringerMode) {
                                AudioManager.RINGER_MODE_NORMAL -> "normal"
                                AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                                AudioManager.RINGER_MODE_SILENT -> "silent"
                                else -> "unknown"
                            }
                            val vol = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                            result.success(mapOf(
                                "muted" to (am.ringerMode != AudioManager.RINGER_MODE_NORMAL || vol == 0),
                                "ringerMode" to ringerStr,
                                "musicVolume" to vol
                            ))
                        } catch (_: Exception) {
                            result.success(mapOf("muted" to false, "ringerMode" to "unknown", "musicVolume" to -1))
                        }
                    }
                    // v0.1.4 直连卫星：只用 GPS_PROVIDER 出位置，网络仅辅星历；
                    // 关闭恢复 GPS + NETWORK。定位权限未授予时不假装切换。
                    // 注意：本方法不改分步权限逻辑，仍要求前台定位已授予。
                    "setDirectSatelliteMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (!foregroundGranted()) {
                            result.success(mapOf(
                                "ok" to false,
                                "directMode" to directSatelliteMode,
                                "error" to "location_not_granted"
                            ))
                        } else {
                            directSatelliteMode = enabled
                            if (locationActive) {
                                try { locationManager.removeUpdates(this) } catch (_: Exception) {}
                                registerLocationProviders()
                            }
                            result.success(mapOf("ok" to true, "directMode" to directSatelliteMode))
                        }
                    }
                    "getGnssStatus" -> {
                        val snap = lastGnssSnapshot
                        if (snap == null) {
                            result.success(mapOf("available" to false))
                        } else {
                            result.success(mapOf("available" to true) + snap)
                        }
                    }
                    "startSensors" -> {
                        startSensors()
                        result.success(null)
                    }
                    "stopSensors" -> {
                        try { sensorManager.unregisterListener(this) } catch (_: Exception) {}
                        result.success(null)
                    }
                    "checkPermissions" -> result.success(checkPermissionsMap())
                    "requestStep" -> {
                        val step = call.argument<String>("step") ?: ""
                        requestStep(step, result)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "openAppSettings" -> {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    // 残留调用兼容：旧名只走 foreground 一步，不再打包后台/通知/蓝牙。
                    // 打包是 v0.1.0 的 bug 根因（见 requestStep 注释），切勿恢复打包逻辑。
                    "requestPermissions" -> requestStep("foreground", result)
                    "startBleScan" -> {
                        startBleScan()
                        result.success(null)
                    }
                    // v0.1.3 通用 BLE：带服务过滤的扫描（GoPro FEA6、NUS 等）。
                    "scanBleWithServices" -> {
                        val uuids = call.argument<List<String>>("serviceUuids") ?: emptyList()
                        scanServiceFilter = uuids
                        startBleScan()
                        result.success(null)
                    }
                    "writeBleCharacteristic" -> {
                        val addr = call.argument<String>("address")
                        val svc = call.argument<String>("serviceUuid") ?: ""
                        val chr = call.argument<String>("characteristicUuid") ?: ""
                        val bytes = (call.argument<List<Int>>("bytes") ?: emptyList()).map { it.toByte() }.toByteArray()
                        val withResp = call.argument<Boolean>("withResponse") ?: true
                        val g = gatt
                        if (g == null || addr == null || g.device.address != addr) {
                            result.success(mapOf("ok" to false, "error" to "not_connected"))
                        } else {
                            val ch = findCharacteristic(svc, chr)
                            if (ch == null) {
                                result.success(mapOf("ok" to false, "error" to "characteristic_not_found"))
                            } else {
                                ch.writeType = if (withResp) BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                                    else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                                ch.value = bytes
                                val ok = g.writeCharacteristic(ch)
                                result.success(mapOf("ok" to ok))
                            }
                        }
                    }
                    "subscribeBleCharacteristic" -> {
                        val addr = call.argument<String>("address")
                        val svc = call.argument<String>("serviceUuid") ?: ""
                        val chr = call.argument<String>("characteristicUuid") ?: ""
                        val g = gatt
                        if (g == null || addr == null || g.device.address != addr) {
                            result.success(mapOf("ok" to false, "error" to "not_connected"))
                        } else {
                            val ch = findCharacteristic(svc, chr)
                            if (ch == null) {
                                result.success(mapOf("ok" to false, "error" to "characteristic_not_found"))
                            } else {
                                enableNotify(g, ch)
                                result.success(mapOf("ok" to true))
                            }
                        }
                    }
                    "unsubscribeBleCharacteristic" -> {
                        val svc = call.argument<String>("serviceUuid") ?: ""
                        val chr = call.argument<String>("characteristicUuid") ?: ""
                        val g = gatt
                        if (g != null) {
                            val ch = findCharacteristic(svc, chr)
                            if (ch != null) g.setCharacteristicNotification(ch, false)
                        }
                        result.success(null)
                    }
                    "readBleCharacteristic" -> {
                        val addr = call.argument<String>("address")
                        val svc = call.argument<String>("serviceUuid") ?: ""
                        val chr = call.argument<String>("characteristicUuid") ?: ""
                        val g = gatt
                        if (g == null || addr == null || g.device.address != addr) {
                            result.error("NOT_CONNECTED", "not_connected", null)
                        } else {
                            val ch = findCharacteristic(svc, chr)
                            if (ch == null) {
                                result.error("NOT_FOUND", "characteristic_not_found", null)
                            } else {
                                pendingReadResult = result
                                pendingReadUuid = ch.uuid.toString()
                                if (!g.readCharacteristic(ch)) {
                                    pendingReadResult = null
                                    pendingReadUuid = null
                                    result.error("READ_FAILED", "read_call_failed", null)
                                }
                            }
                        }
                    }
                    "getConnectedWifiSsid" -> {
                        try {
                            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                            var ssid = wm.connectionInfo?.ssid?.trim('"')
                            if (ssid == null || ssid == "<unknown ssid>" || ssid.isEmpty()) ssid = null
                            result.success(ssid)
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }
                    "stopBleScan" -> {
                        try { bluetoothAdapter?.bluetoothLeScanner?.stopScan(bleScanCallback) } catch (_: Exception) {}
                        result.success(null)
                    }
                    "connectBle" -> {
                        val addr = call.argument<String>("address")
                        if (addr != null) {
                            lastBleAddress = addr
                            reconnectAttempts = 0
                            val dev = bluetoothAdapter?.getRemoteDevice(addr)
                            gatt?.close()
                            gatt = dev?.connectGatt(this, false, gattCallback)
                        }
                        result.success(null)
                    }
                    "disconnectBle" -> {
                        lastBleAddress = null
                        try { gatt?.disconnect() } catch (_: Exception) {}
                        try { gatt?.close() } catch (_: Exception) {}
                        gatt = null
                        result.success(null)
                    }
                    "setBleAutoReconnect" -> {
                        autoReconnect = call.argument<Boolean>("value") ?: true
                        result.success(null)
                    }
                    "zeroCalibrate" -> {
                        var done = false
                        val g = gatt
                        if (g != null) {
                            for (svc in g.services) {
                                if (!svc.uuid.toString().contains("1818")) continue
                                for (ch in svc.characteristics) {
                                    if (ch.uuid.toString().contains("2a66")) {
                                        ch.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                                        ch.value = byteArrayOf(0x0C)
                                        done = g.writeCharacteristic(ch)
                                    }
                                }
                            }
                        }
                        bleDataSink?.success(mapOf("type" to "calibration", "value" to if (done) 1 else 0))
                        result.success(null)
                    }
                    "startVideoRecording" -> startVideoRecording(result)
                    "stopVideoRecording" -> stopVideoRecording(result)
                    "playVideo" -> {
                        val path = call.argument<String>("path") ?: ""
                        try {
                            val file = File(path)
                            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "video/mp4")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(intent, "播放视频"))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("PLAY_FAILED", e.message, null)
                        }
                    }
                    "pickFile" -> {
                        val kind = call.argument<String>("kind") ?: "font"
                        pickKind = kind
                        pickResult = result
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = if (kind == "image") "image/*" else "*/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        try {
                            startActivityForResult(
                                Intent.createChooser(intent, "选择文件"),
                                if (kind == "image") 2002 else 2001
                            )
                        } catch (e: Exception) {
                            pickResult = null
                            result.error("PICK_FAILED", e.message, null)
                        }
                    }
                    // v0.1.7 拍照打点（新增，原先只有 Camera2 视频录制，
                    // 没有静态照片通道）：系统相机 ACTION_IMAGE_CAPTURE，
                    // FileProvider 输出到 filesDir/photo_points/ 唯一文件；
                    // 取消返回 null。相机权限由 Dart 侧 requestStep('camera')
                    // 先申请；同步视频录制占用相机时部分机型可能拍不了，
                    // 失败走 error，由 Dart 侧提示、不写成照片点。
                    "takePhoto" -> {
                        try {
                            val dir = File(filesDir, "photo_points")
                            if (!dir.exists()) dir.mkdirs()
                            val file = File(dir, "photo_${System.currentTimeMillis()}.jpg")
                            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            }
                            photoResult = result
                            photoFile = file
                            startActivityForResult(intent, 2003)
                        } catch (e: Exception) {
                            photoResult = null
                            photoFile = null
                            result.error("PHOTO_FAILED", e.message, null)
                        }
                    }
                    "shareFiles" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        val mime = call.argument<String>("mime") ?: "text/plain"
                        val text = call.argument<String>("text") ?: ""
                        shareFiles(paths, mime, text)
                        result.success(null)
                    }
                    // v0.1.5 在线更新安装：复用 FileProvider（与视频播放 /
                    // 分享同一配置），ACTION_VIEW 调起系统安装器；用户未
                    // 授予“安装未知应用”时系统引导去授权，本侧不静默失败。
                    "installApk" -> {
                        val path = call.argument<String>("path") ?: ""
                        try {
                            val file = File(path)
                            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "drivetrack/location")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { locSink = events }
                override fun onCancel(args: Any?) { locSink = null }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "drivetrack/sensors")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { senSink = events }
                override fun onCancel(args: Any?) { senSink = null }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "drivetrack/bleDevices")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { bleDevSink = events }
                override fun onCancel(args: Any?) { bleDevSink = null }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "drivetrack/bleData")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { bleDataSink = events }
                override fun onCancel(args: Any?) { bleDataSink = null }
            })
        // v0.1.4：GNSS 卫星事件流与 TTS 完成事件流。
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "drivetrack/gnss")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { gnssSink = events }
                override fun onCancel(args: Any?) { gnssSink = null }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "drivetrack/tts")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { ttsSink = events }
                override fun onCancel(args: Any?) { ttsSink = null }
            })
    }

    private fun hasPerm(p: String) =
        ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun foregroundGranted(): Boolean =
        hasPerm(Manifest.permission.ACCESS_FINE_LOCATION) ||
            hasPerm(Manifest.permission.ACCESS_COARSE_LOCATION)

    private fun candidatePerms(): List<String> {
        val list = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            list.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            list.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            list.add(Manifest.permission.BLUETOOTH_SCAN)
            list.add(Manifest.permission.BLUETOOTH_CONNECT)
        }
        list.add(Manifest.permission.CAMERA)
        list.add(Manifest.permission.RECORD_AUDIO)
        return list
    }

    private fun checkPermissionsMap(): Map<String, Any> {
        val backgroundGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            hasPerm(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        } else true
        val notificationsGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            hasPerm(Manifest.permission.POST_NOTIFICATIONS)
        } else true
        val bluetoothGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPerm(Manifest.permission.BLUETOOTH_SCAN) &&
                hasPerm(Manifest.permission.BLUETOOTH_CONNECT)
        } else true
        // 永久拒绝判定（按任务约定）：已拒绝且 shouldShowRequestPermissionRationale
        // 为 false。注意：从未申请过时 rationale 同样为 false，因此 Dart 侧只在
        // 刚发起过一次该步请求、复查仍拒绝时，才把该列表当作永久拒绝。
        val permanentlyDenied = candidatePerms().filter { perm ->
            !hasPerm(perm) &&
                !ActivityCompat.shouldShowRequestPermissionRationale(this, perm)
        }
        return mapOf(
            "location" to foregroundGranted(),
            "foreground" to foregroundGranted(),
            "camera" to hasPerm(Manifest.permission.CAMERA),
            "microphone" to hasPerm(Manifest.permission.RECORD_AUDIO),
            "background" to backgroundGranted,
            "notifications" to notificationsGranted,
            "bluetooth" to bluetoothGranted,
            "permanentlyDenied" to permanentlyDenied
        )
    }

    private fun requestOrImmediate(
        requestCode: Int,
        step: String,
        needed: List<String>,
        result: MethodChannel.Result
    ) {
        if (needed.isEmpty()) {
            result.success(checkPermissionsMap() + mapOf("step" to step, "requested" to false))
            return
        }
        // 同 code 已有未回执的请求时不再重复拉系统框，也不覆盖旧回执：
        // 新调用直接以当前状态回执，旧回执仍等系统回调分发。
        if (pendingPermResults.containsKey(requestCode)) {
            result.success(checkPermissionsMap() + mapOf("step" to step, "requested" to false))
            return
        }
        pendingPermResults[requestCode] = result
        ActivityCompat.requestPermissions(this, needed.toTypedArray(), requestCode)
    }

    private fun requestStep(step: String, result: MethodChannel.Result) {
        when (step) {
            "foreground" -> {
                val needed = listOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ).filter { !hasPerm(it) }
                requestOrImmediate(1001, "foreground", needed, result)
            }
            "extras" -> {
                val needed = mutableListOf<String>()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    !hasPerm(Manifest.permission.POST_NOTIFICATIONS)
                ) {
                    needed.add(Manifest.permission.POST_NOTIFICATIONS)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (!hasPerm(Manifest.permission.BLUETOOTH_SCAN)) {
                        needed.add(Manifest.permission.BLUETOOTH_SCAN)
                    }
                    if (!hasPerm(Manifest.permission.BLUETOOTH_CONNECT)) {
                        needed.add(Manifest.permission.BLUETOOTH_CONNECT)
                    }
                }
                requestOrImmediate(1002, "extras", needed, result)
            }
            "background" -> {
                // Android 11+ 强制分步：仅在前台定位已授予时才发起后台定位请求，
                // 否则不拉系统框（打包/前置申请都会被系统静默丢弃）。
                if (!foregroundGranted()) {
                    result.success(
                        checkPermissionsMap() + mapOf(
                            "step" to "background",
                            "requested" to false,
                            "reason" to "foreground_not_granted"
                        )
                    )
                    return
                }
                val needed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                    !hasPerm(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                ) {
                    listOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                } else emptyList()
                requestOrImmediate(1003, "background", needed, result)
            }
            "camera" -> {
                // 按需：仅在用户勾选同步视频并开始记录时才拉相机/麦克风框，
                // 不在首屏自动申请；麦克风被拒时仍可录无声视频（本实现不设音频源）。
                val needed = listOf(
                    Manifest.permission.CAMERA,
                    Manifest.permission.RECORD_AUDIO
                ).filter { !hasPerm(it) }
                requestOrImmediate(1004, "camera", needed, result)
            }
            // v0.1.3：麦克风独立分步（仅 RECORD_AUDIO），与相机步分开。
            "microphone" -> {
                val needed = listOf(Manifest.permission.RECORD_AUDIO).filter { !hasPerm(it) }
                requestOrImmediate(1005, "microphone", needed, result)
            }
            else -> result.error("INVALID_STEP", "Unknown permission step: $step", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val pending = pendingPermResults.remove(requestCode) ?: return
        val step = permStepByCode[requestCode] ?: "unknown"
        pending.success(checkPermissionsMap() + mapOf("step" to step, "requested" to true))
    }

    private fun startLocation() {
        if (!hasPerm(Manifest.permission.ACCESS_FINE_LOCATION) && !hasPerm(Manifest.permission.ACCESS_COARSE_LOCATION)) return
        locationActive = true
        registerLocationProviders()
        registerGnssCallback()
    }

    // v0.1.4：按直连模式注册 Provider。直连时只注册 GPS（网络仅辅星历，
    // 不直接出位置）；关闭时恢复 GPS + NETWORK（即 v0.1.3 原有行为）。
    private fun registerLocationProviders() {
        try {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000, 0f, this, Looper.getMainLooper())
        } catch (_: Exception) {}
        if (!directSatelliteMode) {
            try {
                locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000, 0f, this, Looper.getMainLooper())
            } catch (_: Exception) {}
        }
    }

    override fun onLocationChanged(location: Location) {
        val map = mapOf<String, Any>(
            "lat" to location.latitude,
            "lon" to location.longitude,
            "alt" to location.altitude,
            // v0.1.7：NETWORK 定位常无海拔，此时 altitude 恒为占位 0；
            // Dart 侧以 hasAlt=false 标记无效，绝不把 0 当海平面数据。
            "hasAlt" to location.hasAltitude(),
            "speed" to location.speed.toDouble(),
            "bearing" to location.bearing.toDouble(),
            "hAcc" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) location.accuracy.toDouble() else 999.0,
            "vAcc" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) location.verticalAccuracyMeters.toDouble() else 999.0,
            "sAcc" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) location.speedAccuracyMetersPerSecond.toDouble() else 999.0,
            "provider" to (location.provider ?: ""),
            // v0.1.4：最近一次 GNSS 历元的参与解算卫星数；从未收到回调时为 -1，
            // Dart 侧（Recorder 接线）收到 -1 应存 null，不要写进轨迹文件。
            "satCount" to lastGnssUsed,
            "timeMs" to location.time
        )
        runOnUiThread { locSink?.success(map) }
    }

    // ---------- v0.1.4 TTS ----------
    private fun ttsStatusMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>(
            "available" to ttsReady,
            "language" to ttsLanguage
        )
        if (!ttsReady) map["error"] = "tts_unavailable"
        return map
    }

    // TTS 引擎初始化是异步的：未完成时把调用排队，回调里依次执行；
    // 已完成时直接执行。Dart 侧保证同一时间只有一个 ttsSpeak 在途。
    private fun whenTtsReady(action: () -> Unit) {
        if (ttsInitDone) {
            action()
            return
        }
        ttsPendingActions.add(action)
        if (tts != null) return // 初始化进行中，等回调
        try {
            val initListener = TextToSpeech.OnInitListener { status ->
                ttsInitDone = true
                if (status == TextToSpeech.SUCCESS) {
                    val zh = tts?.setLanguage(java.util.Locale.CHINESE)
                    if (zh == TextToSpeech.LANG_AVAILABLE || zh == TextToSpeech.LANG_COUNTRY_AVAILABLE) {
                        ttsLanguage = "zh"
                        ttsReady = true
                    } else {
                        val dflt = tts?.setLanguage(java.util.Locale.getDefault())
                        if (dflt == TextToSpeech.LANG_AVAILABLE || dflt == TextToSpeech.LANG_COUNTRY_AVAILABLE) {
                            ttsLanguage = "default"
                            ttsReady = true
                        } else {
                            ttsLanguage = "none"
                            ttsReady = false
                        }
                    }
                    if (ttsReady) {
                        try { tts?.setSpeechRate(ttsRate) } catch (_: Exception) {}
                        try { tts?.setPitch(ttsPitch) } catch (_: Exception) {}
                        try { tts?.setOnUtteranceProgressListener(ttsListener) } catch (_: Exception) {}
                    }
                } else {
                    ttsLanguage = "none"
                    ttsReady = false
                }
                val actions = ttsPendingActions.toList()
                ttsPendingActions.clear()
                actions.forEach { it() }
            }
            tts = if (ttsEngineOverride != null) {
                TextToSpeech(this, initListener, ttsEngineOverride)
            } else {
                TextToSpeech(this, initListener)
            }
        } catch (_: Exception) {
            ttsInitDone = true
            ttsReady = false
            ttsLanguage = "none"
            val actions = ttsPendingActions.toList()
            ttsPendingActions.clear()
            actions.forEach { it() }
        }
    }

    private val ttsListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {}
        override fun onDone(utteranceId: String?) {
            runOnUiThread {
                ttsSink?.success(mapOf("type" to "done", "utteranceId" to (utteranceId ?: "")))
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            runOnUiThread {
                ttsSink?.success(mapOf("type" to "error", "utteranceId" to (utteranceId ?: "")))
            }
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            // 不调 super：默认实现会转调单参数版，避免一次失败报两次。
            runOnUiThread {
                ttsSink?.success(mapOf("type" to "error", "utteranceId" to (utteranceId ?: "")))
            }
        }
    }

    private fun ttsSpeak(text: String, utteranceId: String, result: MethodChannel.Result) {
        whenTtsReady {
            if (!ttsReady) {
                result.success(mapOf("ok" to false, "error" to "tts_unavailable"))
                return@whenTtsReady
            }
            try {
                val params = android.os.Bundle()
                params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, ttsVolume)
                val code = tts?.speak(text, TextToSpeech.QUEUE_ADD, params, utteranceId)
                if (code == TextToSpeech.SUCCESS) {
                    result.success(mapOf("ok" to true, "utteranceId" to utteranceId))
                } else {
                    result.success(mapOf("ok" to false, "error" to "tts_speak_failed"))
                }
            } catch (_: Exception) {
                result.success(mapOf("ok" to false, "error" to "tts_speak_failed"))
            }
        }
    }

    // ---------- v0.1.4 GNSS 卫星状态 ----------
    private fun registerGnssCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        if (gnssCallback != null) return
        try {
            val cb = object : GnssStatus.Callback() {
                override fun onSatelliteStatusChanged(status: GnssStatus) {
                    var used = 0
                    var cn0Sum = 0.0
                    var cn0Count = 0
                    var l5 = false
                    val by = mutableMapOf<String, Int>()
                    val usedBy = mutableMapOf<String, Int>()
                    for (i in 0 until status.satelliteCount) {
                        val c = when (status.getConstellationType(i)) {
                            GnssStatus.CONSTELLATION_GPS -> "gps"
                            GnssStatus.CONSTELLATION_BEIDOU -> "beidou"
                            GnssStatus.CONSTELLATION_GALILEO -> "galileo"
                            GnssStatus.CONSTELLATION_GLONASS -> "glonass"
                            else -> "other" // QZSS / IRNSS / SBAS 统一归 other
                        }
                        by[c] = (by[c] ?: 0) + 1
                        if (status.usedInFix(i)) {
                            used++
                            usedBy[c] = (usedBy[c] ?: 0) + 1
                        }
                        // CN0 需 Android 10+；无数据时 avgCn0 发 -1，Dart 侧转 null。
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val cn0 = status.getCn0DbHz(i)
                            if (cn0 > 0) {
                                cn0Sum += cn0
                                cn0Count++
                            }
                        }
                        // L5 频点（1176.45 MHz ± 2 MHz）仅说明本历元见过 L5，
                        // 不是机型双频能力的鉴定结论，界面不得写成“支持双频”。
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            status.hasCarrierFrequencyHz(i)
                        ) {
                            val f = status.getCarrierFrequencyHz(i)
                            if (f >= 1174450000.0 && f <= 1178450000.0) l5 = true
                        }
                    }
                    lastGnssUsed = used
                    val snap: Map<String, Any> = mapOf(
                        "visible" to status.satelliteCount,
                        "used" to used,
                        "avgCn0" to if (cn0Count > 0) cn0Sum / cn0Count else -1.0,
                        "byConstellation" to by,
                        "usedByConstellation" to usedBy,
                        "l5Seen" to l5,
                        "timeMs" to System.currentTimeMillis()
                    )
                    lastGnssSnapshot = snap
                    runOnUiThread { gnssSink?.success(snap) }
                }
            }
            gnssCallback = cb
            locationManager.registerGnssStatusCallback(cb, Handler(Looper.getMainLooper()))
        } catch (_: Exception) {}
    }

    private fun unregisterGnssCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val cb = gnssCallback as? GnssStatus.Callback ?: return
        try {
            locationManager.unregisterGnssStatusCallback(cb)
        } catch (_: Exception) {}
        gnssCallback = null
    }

    private fun startSensors() {
        val types = listOf(
            Sensor.TYPE_LINEAR_ACCELERATION,
            Sensor.TYPE_GYROSCOPE,
            Sensor.TYPE_ROTATION_VECTOR,
            Sensor.TYPE_PRESSURE
        )
        for (t in types) {
            sensorManager.getDefaultSensor(t)?.let {
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> latestRv = event.values.copyOf()
            Sensor.TYPE_PRESSURE -> latestPressure = event.values[0]
            Sensor.TYPE_LINEAR_ACCELERATION -> {
                val rv = latestRv
                val map = mapOf<String, Any>(
                    "ax" to event.values[0].toDouble(),
                    "ay" to event.values[1].toDouble(),
                    "az" to event.values[2].toDouble(),
                    "rv" to (rv?.map { it.toDouble() } ?: emptyList<Double>()),
                    "pressure" to latestPressure.toDouble(),
                    "timeMs" to System.currentTimeMillis()
                )
                runOnUiThread { senSink?.success(map) }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun startBleScan() {
        val scanner = bluetoothAdapter?.bluetoothLeScanner ?: return
        // v0.1.3：scanBleWithServices 传入过滤列表时优先用它，否则用骑行三类默认过滤。
        val filters = scanServiceFilter?.mapNotNull { s ->
            try {
                val full = when {
                    s.length == 4 -> "0000$s-0000-1000-8000-00805f9b34b0"
                    s.length == 8 -> "$s-0000-1000-8000-00805f9b34b0"
                    else -> s
                }
                ScanFilter.Builder().setServiceUuid(android.os.ParcelUuid(UUID.fromString(full))).build()
            } catch (_: Exception) { null }
        }?.takeIf { it.isNotEmpty() } ?: listOf(
            ScanFilter.Builder().setServiceUuid(android.os.ParcelUuid(UUID.fromString("00001818-0000-1000-8000-00805f9b34b0"))).build(),
            ScanFilter.Builder().setServiceUuid(android.os.ParcelUuid(UUID.fromString("00001816-0000-1000-8000-00805f9b34b0"))).build(),
            ScanFilter.Builder().setServiceUuid(android.os.ParcelUuid(UUID.fromString("0000180d-0000-1000-8000-00805f9b34b0"))).build()
        )
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        try {
            scanner.startScan(filters, settings, bleScanCallback)
        } catch (_: Exception) {
            try { scanner.startScan(bleScanCallback) } catch (_: Exception) {}
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        // v0.1.7 拍照：成功且文件非空返回路径；取消/失败返回 null，
        // 并删掉可能残留的空文件，不留 0 字节占位。
        if (requestCode == 2003) {
            val res = photoResult
            val file = photoFile
            photoResult = null
            photoFile = null
            if (res == null) return
            if (resultCode == Activity.RESULT_OK && file != null && file.exists() && file.length() > 0) {
                res.success(file.absolutePath)
            } else {
                try { if (file != null && file.exists()) file.delete() } catch (_: Exception) {}
                res.success(null)
            }
            return
        }
        if (requestCode != 2001 && requestCode != 2002) return
        val res = pickResult
        pickResult = null
        if (res == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            res.success(null)
            return
        }
        try {
            val uri = data.data!!
            val out = File(filesDir, if (pickKind == "image") "avatar.jpg" else "custom_font.ttf")
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { output -> input.copyTo(output) }
            }
            res.success(out.absolutePath)
        } catch (e: Exception) {
            res.error("COPY_FAILED", e.message, null)
        }
    }

    // ---------- 同步视频（无预览录制） ----------
    private fun backCameraId(cm: CameraManager): String? {
        return try {
            cm.cameraIdList.firstOrNull { id ->
                cm.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun buildRecorder(file: File): MediaRecorder? {
        return try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val backId = backCameraId(cm) ?: return null
            val map = cm.getCameraCharacteristics(backId)
                .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return null
            val sizes = map.getOutputSizes(MediaRecorder::class.java) ?: return null
            // 1080p 优先，设备不支持则取最大的 ≤1080p 档位。
            val size = sizes.filter { it.width <= 1920 && it.height <= 1080 }
                .maxByOrNull { it.width * it.height } ?: sizes.firstOrNull() ?: return null
            val rec = MediaRecorder()
            rec.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            rec.setVideoSize(size.width, size.height)
            rec.setVideoFrameRate(30)
            rec.setVideoEncodingBitRate(8_000_000)
            rec.setMaxDuration(10 * 60 * 1000) // 每段最长 10 分钟，防长途无限写满存储
            rec.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED && videoRecording) {
                    restartVideoSegment()
                }
            }
            rec.setOutputFile(file.absolutePath)
            rec.prepare()
            rec
        } catch (_: Exception) {
            null
        }
    }

    private fun newVideoFile(): File {
        val dir = File(filesDir, "videos")
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "trip_${System.currentTimeMillis()}.mp4")
    }

    private fun createVideoSession() {
        val cam = cameraDevice ?: return
        val rec = mediaRecorder ?: return
        try {
            val surface = rec.surface
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val config = SessionConfiguration(
                    SessionConfiguration.SESSION_REGULAR,
                    listOf(OutputConfiguration(surface)),
                    mainExecutor,
                    object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(session: CameraCaptureSession) {
                            captureSession = session
                            try {
                                val req = cam.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                                    .apply { addTarget(surface) }.build()
                                session.setRepeatingRequest(req, null, Handler(Looper.getMainLooper()))
                            } catch (_: Exception) {}
                        }

                        override fun onConfigureFailed(session: CameraCaptureSession) {}
                    }
                )
                cam.createCaptureSession(config)
            } else {
                @Suppress("DEPRECATION")
                cam.createCaptureSession(
                    listOf(surface),
                    object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(session: CameraCaptureSession) {
                            captureSession = session
                            try {
                                val req = cam.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                                    .apply { addTarget(surface) }.build()
                                session.setRepeatingRequest(req, null, Handler(Looper.getMainLooper()))
                            } catch (_: Exception) {}
                        }

                        override fun onConfigureFailed(session: CameraCaptureSession) {}
                    },
                    Handler(Looper.getMainLooper())
                )
            }
        } catch (_: Exception) {}
    }

    private fun restartVideoSegment() {
        if (!videoRecording) return
        try { captureSession?.close() } catch (_: Exception) {}
        captureSession = null
        try { mediaRecorder?.stop() } catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
        val file = newVideoFile()
        val rec = buildRecorder(file) ?: return
        mediaRecorder = rec
        videoSegments.add(file.absolutePath)
        createVideoSession()
    }

    private fun startVideoRecording(result: MethodChannel.Result) {
        if (videoRecording) {
            result.success(mapOf("ok" to true, "path" to (videoSegments.lastOrNull() ?: "")))
            return
        }
        val file = newVideoFile()
        val rec = buildRecorder(file)
        if (rec == null) {
            result.success(mapOf("ok" to false, "error" to "设备不支持无预览录制（无后置摄像头或编码器不可用）"))
            return
        }
        mediaRecorder = rec
        videoSegments.add(file.absolutePath)
        videoRecording = true
        var sent = false
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val backId = backCameraId(cm)
            if (backId == null) {
                videoRecording = false
                result.success(mapOf("ok" to false, "error" to "设备无后置摄像头"))
                return
            }
            cm.openCamera(backId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createVideoSession()
                    if (!sent) {
                        sent = true
                        result.success(mapOf("ok" to true, "path" to file.absolutePath))
                    }
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                    videoRecording = false
                    if (!sent) {
                        sent = true
                        result.success(mapOf("ok" to false, "error" to "相机打开失败（错误码 $error），该设备可能不支持无预览录制"))
                    }
                }
            }, Handler(Looper.getMainLooper()))
        } catch (e: Exception) {
            videoRecording = false
            if (!sent) result.success(mapOf("ok" to false, "error" to (e.message ?: "相机打开失败")))
        }
    }

    private fun stopVideoRecording(result: MethodChannel.Result) {
        videoRecording = false
        try { captureSession?.close() } catch (_: Exception) {}
        captureSession = null
        try { mediaRecorder?.stop() } catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
        try { cameraDevice?.close() } catch (_: Exception) {}
        cameraDevice = null
        val kept = videoSegments.filter { File(it).exists() && File(it).length() > 0 }
        videoSegments.clear()
        result.success(kept)
    }

    private fun shareFiles(paths: List<String>, mime: String, text: String) {
        val uris = paths.map { p ->
            FileProvider.getUriForFile(this, "$packageName.fileprovider", File(p))
        }
        val intent = if (uris.size > 1) {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = mime
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
            }
        } else if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uris[0])
            }
        } else {
            Intent(Intent.ACTION_SEND).apply { type = "text/plain" }
        }
        intent.putExtra(Intent.EXTRA_TEXT, text)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(intent, "分享行程"))
    }
}

// v0.1.7 视频回顾 PlatformView：一个 Dart AndroidView 对应一个 VideoView。
// 方法通道按视图 id 分离（drivetrack/video_view_<id>），Dart 在
// onPlatformViewCreated 后建通道并接回调，避免多段切换时串台。
// 方法：play / pause / seekTo{position} / getPosition / getDuration /
// isPlaying；回调：onPrepared{duration} / onCompleted / onError{what,extra}。
// seekTo 走 VideoView（MediaPlayer）关键帧就近定位，不是帧精确。
// 注意：本类只做应用内播放，不做烧录重编码，HUD 由 Dart 层叠加。
class DriveTrackVideoViewFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val path = (args as? Map<*, *>)?.get("path") as? String ?: ""
        return DriveTrackVideoView(context, messenger, viewId, path)
    }
}

class DriveTrackVideoView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    path: String
) : PlatformView {
    private val videoView = VideoView(context)
    private val channel = MethodChannel(messenger, "drivetrack/video_view_$viewId")

    init {
        videoView.setMediaController(null)
        if (path.isNotEmpty()) {
            videoView.setVideoPath(path)
        }
        videoView.setOnPreparedListener { mp ->
            channel.invokeMethod(
                "onPrepared", mapOf("duration" to mp.duration)
            )
        }
        videoView.setOnCompletionListener {
            channel.invokeMethod("onCompleted", null)
        }
        videoView.setOnErrorListener { _, what, extra ->
            channel.invokeMethod(
                "onError", mapOf("what" to what, "extra" to extra)
            )
            true
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    try {
                        videoView.start()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("PLAY_FAILED", e.message, null)
                    }
                }
                "pause" -> {
                    try {
                        videoView.pause()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("PAUSE_FAILED", e.message, null)
                    }
                }
                "seekTo" -> {
                    val pos = call.argument<Int>("position") ?: 0
                    try {
                        videoView.seekTo(pos)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SEEK_FAILED", e.message, null)
                    }
                }
                "getPosition" -> result.success(videoView.currentPosition)
                "getDuration" -> result.success(videoView.duration)
                "isPlaying" -> result.success(videoView.isPlaying)
                else -> result.notImplemented()
            }
        }
    }

    override fun getView(): View = videoView

    override fun dispose() {
        try {
            videoView.stopPlayback()
        } catch (_: Exception) {
        }
        channel.setMethodCallHandler(null)
    }
}
