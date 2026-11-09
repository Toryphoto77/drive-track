plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.chixi.drive_track"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.chixi.drive_track"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // v1.0.0 正式签名：DriveTrack 专属密钥库，绝不用 Ordnance 的
    // guns-map-release.keystore，也绝不用 debug 签名。
    // 密码只从环境变量读（构建脚本从 ~/release-keystore/ 的 600 权限
    // 密码文件读出后以环境变量传入），不写进本文件、不另建 properties 文件。
    // 密钥库路径：环境变量 DRIVETRACK_KEYSTORE（构建脚本会传入），未设时
    // 回落 ~/release-keystore/drive-track-release.keystore。不再写死某台
    // 机器的绝对路径；任何电脑只要按维护说明放好密钥库即可编正式包。
    val releaseKeystorePath: String = System.getenv("DRIVETRACK_KEYSTORE")
        ?: "${System.getProperty("user.home")}/release-keystore/drive-track-release.keystore"
    signingConfigs {
        create("release") {
            storeFile = file(releaseKeystorePath)
            storePassword = System.getenv("DRIVETRACK_STORE_PASSWORD")
            keyAlias = System.getenv("DRIVETRACK_KEY_ALIAS") ?: "drivetrack"
            keyPassword = System.getenv("DRIVETRACK_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // release 默认 lintVital 在离线镜像下缺 lint-gradle；App 已过 analyze，
    // 关掉 release lint 检查（与 Ordnance 正式版同一处理）。
    lint {
        checkReleaseBuilds = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
