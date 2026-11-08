package com.chixi.drive_track

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import java.io.IOException
import java.util.UUID

/// OBD（ELM327）原生管理：经典蓝牙 SPP + 后台读写线程。
///
/// 与外接 GPS 的 BtGpsManager 完全独立（各自的 socket 与线程，
/// 可与 GPS SPP 共存）；Dart 侧经 drivetrack/obd 事件流收响应行。
///
/// 事件（走 emitData，即 MainActivity 的 bleDataSink 吗？不——
/// 走独立的 obdSink，见 MainActivity 的 drivetrack/obd 注册，
/// 避免 OBD 响应行混进 main.dart 的 GPS / 传感器监听）：
/// - obdConnected：SPP 已连通，Dart 侧随后发 ATZ 等初始化命令；
/// - obdLine：ELM327 响应行（按 \r / \n 切行，'>' 提示行单独发出，
///   Dart 靠它判定一条命令的响应结束）；
/// - obdDisconnected：socket 断开，reason 为 eof / io_error /
///   permission / no_adapter / bad_address / error。
/// 无蓝牙 / 无权限 / 地址非法时一律发 obdDisconnected，绝不崩溃。
/// Android 12+ 蓝牙权限复用现有分步流程（Dart 侧 requestStep('extras')
/// 申请 BLUETOOTH_SCAN / BLUETOOTH_CONNECT），本文件不另起权限流程。
class ObdManager(
    private val activity: Activity,
    private val emitData: (Map<String, Any>) -> Unit,
) {
    companion object {
        // 标准 SPP UUID。注意：BtGpsManager 里写的是
        // 00001101-...-00805F1A34B（F1A，笔误），OBD 这里用正确值。
        val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private fun adapter(): BluetoothAdapter? {
        val manager =
            activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    @Volatile
    private var active = false
    private var socket: BluetoothSocket? = null
    private var output: java.io.OutputStream? = null
    private var address: String? = null

    /** 已配对经典蓝牙设备列表（ELM327 须先在系统蓝牙里配对）。 */
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

    /** 后台线程连接 SPP。结果经 obd 事件流回报，不阻塞 UI 线程。 */
    fun connect(address: String) {
        disconnect()
        this.address = address
        active = true
        Thread {
            var sock: BluetoothSocket? = null
            try {
                val ad = adapter()
                if (ad == null) {
                    emitDisconnected("no_adapter")
                    return@Thread
                }
                val device: BluetoothDevice = try {
                    ad.getRemoteDevice(address)
                } catch (_: IllegalArgumentException) {
                    emitDisconnected("bad_address")
                    return@Thread
                }
                sock = device.createRfcommSocketToServiceRecord(SPP_UUID)
                socket = sock
                sock.connect()
                if (!active) return@Thread
                output = sock.outputStream
                emitData(
                    mapOf<String, Any>(
                        "type" to "obdConnected",
                        "address" to address,
                    ),
                )
                val reader = sock.inputStream.bufferedReader()
                val buf = StringBuilder()
                val tmp = CharArray(256)
                while (active) {
                    val n = try {
                        reader.read(tmp)
                    } catch (_: IOException) {
                        break
                    }
                    if (n <= 0) break
                    buf.append(tmp, 0, n)
                    while (true) {
                        val s = buf.toString()
                        val idx = s.indexOfFirst { it == '\r' || it == '\n' }
                        if (idx < 0) break
                        val line = s.substring(0, idx).trim()
                        buf.delete(0, idx + 1)
                        if (line.isNotEmpty()) {
                            emitData(
                                mapOf<String, Any>(
                                    "type" to "obdLine",
                                    "address" to address,
                                    "line" to line,
                                ),
                            )
                        }
                    }
                }
                if (active) emitDisconnected("eof")
            } catch (_: SecurityException) {
                if (active) emitDisconnected("permission")
            } catch (_: IOException) {
                if (active) emitDisconnected("io_error")
            } catch (_: Exception) {
                if (active) emitDisconnected("error")
            } finally {
                try {
                    sock?.close()
                } catch (_: Exception) {
                }
                if (socket === sock) {
                    socket = null
                    output = null
                }
            }
        }.start()
    }

    private fun emitDisconnected(reason: String) {
        active = false
        emitData(
            mapOf<String, Any>(
                "type" to "obdDisconnected",
                "address" to (address ?: ""),
                "reason" to reason,
            ),
        )
    }

    fun disconnect() {
        active = false
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
        output = null
    }

    /** 发一条 ELM327 命令（Dart 侧不带 '\r'，这里补）。返回 false = 未连接。 */
    fun sendCommand(command: String): Boolean {
        return try {
            val out = output ?: return false
            out.write((command + "\r").toByteArray(Charsets.US_ASCII))
            out.flush()
            true
        } catch (_: Exception) {
            false
        }
    }
}
