package com.chixi.drive_track

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import java.io.IOException
import java.util.UUID

/// 外置蓝牙 GPS 接收器的原生管理：经典蓝牙 SPP + 经典蓝牙发现 +
/// 无过滤 BLE 扫描。本文件独立于 MainActivity，只通过两个 sink 回调
/// 与 Dart 通信；MainActivity 仅做通道注册与方法转发。
///
/// 事件分流（关键：不污染页级通用扫描列表）：
/// - 设备发现事件（无过滤 BLE 扫描、经典蓝牙发现）走 btGpsDevSink，
///   只被外接 GPS 区订阅；页级“附近扫描结果”只听 bleDeviceStream，
///   不会因此多出一条重复设备。
/// - SPP 数据事件（sppConnected / sppNmea / sppDisconnected）走
///   bleDataSink，与 BLE 通知共用 main.dart 的全局监听，复用同一
///   条接管链路（main.dart 的 BleDiyGpsFeed + Recorder 注入）。
/// - SPP 不占 GATT 名额，可与 BLE 传感器共存；BLE 路径仍复用
///   MainActivity 的单 GATT（连新设备会断开旧设备是既有行为）。
class BtGpsManager(
    private val activity: Activity,
    private val emitData: (Map<String, Any>) -> Unit,
    private val emitDevice: (Map<String, Any>) -> Unit,
) {
    companion object {
        val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F1A34B")
    }

    private fun adapter(): BluetoothAdapter? {
        val manager =
            activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    // ---------------- SPP ----------------

    @Volatile
    private var sppActive = false
    private var sppSocket: BluetoothSocket? = null
    private var sppAddress: String? = null

    /** 已配对经典蓝牙设备列表。无蓝牙 / 无权限时返回空列表，绝不崩溃。 */
    fun bondedDevices(): List<Map<String, Any>> {
        return try {
            val bonded = adapter()?.bondedDevices ?: return emptyList()
            bonded.map { dev ->
                mapOf<String, Any>(
                    "address" to dev.address,
                    "name" to (dev.name ?: ""),
                    "type" to "已配对经典蓝牙",
                )
            }
        } catch (_: SecurityException) {
            emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** 后台线程连接 SPP。结果经 bleDataSink 回报，不阻塞 UI 线程。 */
    fun connectSpp(address: String) {
        disconnectSpp()
        sppAddress = address
        sppActive = true
        Thread {
            var socket: BluetoothSocket? = null
            try {
                val ad = adapter()
                if (ad == null) {
                    emitSppDisconnected("no_adapter")
                    return@Thread
                }
                val device: BluetoothDevice = try {
                    ad.getRemoteDevice(address)
                } catch (_: IllegalArgumentException) {
                    emitSppDisconnected("bad_address")
                    return@Thread
                }
                socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                sppSocket = socket
                socket.connect()
                if (!sppActive) return@Thread
                emitData(
                    mapOf<String, Any>(
                        "type" to "sppConnected",
                        "address" to address,
                    ),
                )
                val reader = socket.inputStream.bufferedReader()
                while (sppActive) {
                    val line = try {
                        reader.readLine()
                    } catch (_: IOException) {
                        break
                    } ?: break
                    if (line.isNotBlank()) {
                        emitData(
                            mapOf<String, Any>(
                                "type" to "sppNmea",
                                "address" to address,
                                "line" to line,
                            ),
                        )
                    }
                }
                if (sppActive) emitSppDisconnected("eof")
            } catch (_: SecurityException) {
                if (sppActive) emitSppDisconnected("permission")
            } catch (_: IOException) {
                if (sppActive) emitSppDisconnected("io_error")
            } catch (_: Exception) {
                if (sppActive) emitSppDisconnected("error")
            } finally {
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
                if (sppSocket === socket) sppSocket = null
            }
        }.start()
    }

    private fun emitSppDisconnected(reason: String) {
        sppActive = false
        emitData(
            mapOf<String, Any>(
                "type" to "sppDisconnected",
                "address" to (sppAddress ?: ""),
                "reason" to reason,
            ),
        )
    }

    fun disconnectSpp() {
        sppActive = false
        try {
            sppSocket?.close()
        } catch (_: Exception) {
        }
        sppSocket = null
    }

    // ---------------- 经典蓝牙发现 ----------------

    private var classicReceiver: BroadcastReceiver? = null

    /** 开始经典蓝牙发现。返回 false = 蓝牙不可用或无权限（不崩溃）。 */
    fun startClassicDiscovery(): Boolean {
        val ad = adapter() ?: return false
        if (classicReceiver != null) return true
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val dev: BluetoothDevice? =
                            intent.getParcelableExtra(
                                BluetoothDevice.EXTRA_DEVICE,
                            )
                        val rssi = intent.getShortExtra(
                            BluetoothDevice.EXTRA_RSSI,
                            0,
                        ).toInt()
                        if (dev != null) {
                            emitDevice(
                                mapOf<String, Any>(
                                    "type" to "classic",
                                    "address" to dev.address,
                                    "name" to (dev.name ?: ""),
                                    "rssi" to rssi,
                                ),
                            )
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        emitDevice(
                            mapOf<String, Any>(
                                "type" to "classicDiscoveryFinished",
                            ),
                        )
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        return try {
            activity.registerReceiver(receiver, filter)
            classicReceiver = receiver
            ad.startDiscovery()
        } catch (_: SecurityException) {
            try {
                activity.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    fun stopClassicDiscovery() {
        try {
            adapter()?.cancelDiscovery()
        } catch (_: Exception) {
        }
        val receiver = classicReceiver
        classicReceiver = null
        if (receiver != null) {
            try {
                activity.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
        }
    }

    // ---------------- 无过滤 BLE 扫描 ----------------

    private val unfilteredScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val dev = result.device
            val uuids = result.scanRecord?.serviceUuids?.map { it.uuid.toString() }
                ?: emptyList()
            emitDevice(
                mapOf<String, Any>(
                    "type" to "ble",
                    "address" to dev.address,
                    "name" to (dev.name ?: ""),
                    "rssi" to result.rssi,
                    "serviceUuids" to uuids,
                ),
            )
        }

        override fun onScanFailed(errorCode: Int) {
            emitDevice(
                mapOf<String, Any>(
                    "type" to "bleScanFailed",
                    "errorCode" to errorCode,
                ),
            )
        }
    }

    /** 无过滤 BLE 扫描：按设备名发现不广播 NUS 的 GPS 设备。 */
    fun startUnfilteredBleScan(): Boolean {
        return try {
            val scanner = adapter()?.bluetoothLeScanner ?: return false
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            scanner.startScan(null, settings, unfilteredScanCallback)
            true
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    fun stopUnfilteredScan() {
        try {
            adapter()?.bluetoothLeScanner?.stopScan(unfilteredScanCallback)
        } catch (_: Exception) {
        }
    }
}
