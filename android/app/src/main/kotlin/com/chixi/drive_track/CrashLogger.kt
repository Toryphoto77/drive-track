package com.chixi.drive_track

import android.content.Context
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// 原生崩溃 / 异常落盘（只写本机 filesDir/crash_native.log，不联网、不上传）。
// 目的：后台闪退时不再“无堆栈可查”，用户可在设置页导出给开发者定位。
// 200KB 上限，超出后只保留最近一半，避免长期占用存储。
object CrashLogger {
    const val FILE_NAME = "crash_native.log"
    private const val MAX_BYTES = 200L * 1024L
    private val lock = Any()

    @Volatile
    private var dir: File? = null

    @Volatile
    private var installed = false

    fun init(context: Context) {
        dir = context.filesDir
        if (installed) return
        installed = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            log("uncaught(${thread.name})", e)
            previous?.uncaughtException(thread, e)
        }
    }

    fun log(tag: String, e: Throwable?) {
        val detail = if (e == null) {
            ""
        } else {
            val sw = StringWriter()
            e.printStackTrace(PrintWriter(sw))
            sw.toString()
        }
        append("$tag\n$detail")
    }

    fun append(message: String) {
        val d = dir ?: return
        synchronized(lock) {
            try {
                val f = File(d, FILE_NAME)
                if (f.length() > MAX_BYTES) {
                    val bytes = f.readBytes()
                    val keepFrom = (bytes.size - (MAX_BYTES / 2).toInt()).coerceAtLeast(0)
                    f.writeBytes(bytes.copyOfRange(keepFrom, bytes.size))
                }
                val ts = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
                f.appendText("[$ts] $message\n")
            } catch (_: Throwable) {
                // 日志写失败绝不能反过来拖垮业务。
            }
        }
    }
}
