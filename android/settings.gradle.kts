pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("../flutter-tools-gradle")

    repositories {
        // 离线镜像（仅本机沙箱用：Gradle 直连被拦才需要）。
        // 目录不存在时跳过，走下面的在线仓库；用户自己电脑上
        // 一般没有这个目录，直接联网下载即可。
        val offlineMirrorPath = providers.gradleProperty("offlineMirror").orNull
            ?: System.getenv("GRADLE_OFFLINE_MIRROR")
            ?: "/home/hatch/gradle-offline-mirror"
        val offlineMirror = File(offlineMirrorPath)
        if (offlineMirror.isDirectory) {
            maven { url = uri(offlineMirror.toURI()) }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        val offlineMirrorPath = providers.gradleProperty("offlineMirror").orNull
            ?: System.getenv("GRADLE_OFFLINE_MIRROR")
            ?: "/home/hatch/gradle-offline-mirror"
        val offlineMirror = File(offlineMirrorPath)
        if (offlineMirror.isDirectory) {
            maven { url = uri(offlineMirror.toURI()) }
        }
        google()
        mavenCentral()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}
