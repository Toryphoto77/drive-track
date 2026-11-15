#!/bin/bash
# 驰迹 DriveTrack 正式包构建（armeabi-v7a，32 位）。
# 与 build-apk-release.sh（arm64）流程一致，只改 --target-platform、
# release 引擎检查路径与输出文件名。
# 签名材料只放在本机，运行时通过环境变量传给构建进程，构建结束即清除；
# 不写进 gradle，也不进仓库。
# 目标机型：32 位 ARM 手机（老机型 / 低端机）；64 位手机优先用 arm64 包。
# 版本号从 pubspec.yaml 读取（避免硬编码版本号漂移），
# 文件名用完整 ABI 名 armeabi-v7a，与 arm64 旧简称区分。
# 注意：本脚本只准备、不构建——跑构建是协调人的事。
set -e
# 路径可用环境变量覆盖（装在别处时不必改脚本）。
export JAVA_HOME=${DRIVETRACK_JAVA_HOME:-$HOME/sdk/jdk17}
FLUTTER_HOME=${DRIVETRACK_FLUTTER_HOME:-$HOME/sdk/flutter}
export ANDROID_HOME=${DRIVETRACK_ANDROID_HOME:-$HOME/sdk/android-sdk}
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$FLUTTER_HOME/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH
export JAVA_OPTS="-Djava.net.preferIPv4Stack=true"
export GRADLE_OPTS="$JAVA_OPTS"
# 关键：本机以 root 运行，Java user.home 默认是 /root（VM 替换后会被清空），
# 而完整 Gradle 发行包与缓存实际在 /home/hatch/.gradle；必须显式指定，
# 否则 wrapper 会去 /root 下重下发行包并被沙箱拦截。
export GRADLE_USER_HOME=$HOME/.gradle
cd "$(dirname "$0")"
for d in "$ANDROID_HOME/platforms/android-36" "$ANDROID_HOME/build-tools/36.0.0" "$ANDROID_HOME/ndk/28.2.13676358"; do
  if [ ! -d "$d" ]; then echo "缺 SDK 组件：$d"; exit 1; fi
done
# 离线镜像（仅本机沙箱用）：有镜像走离线构建，无镜像走在线构建（需联网）。
if [ -d "$HOME/gradle-offline-mirror" ]; then
  OFFLINE_BUILD=1
else
  OFFLINE_BUILD=0
  echo "未找到本地离线镜像，走在线构建（需联网下载 Gradle 依赖）"
fi
# release 引擎与 debug 不同：构建前核对齐全，缺失即停，不编出半成品。
# armeabi-v7a 对应 android-arm-release（已核实本地存在）。
if [ ! -f "$FLUTTER_HOME/bin/cache/artifacts/engine/android-arm-release/flutter.jar" ]; then
  echo "缺 Flutter release 引擎：android-arm-release/flutter.jar"; exit 1
fi
KEYSTORE=${DRIVETRACK_KEYSTORE:-$HOME/release-keystore/drive-track-release.keystore}
PW_FILE=${DRIVETRACK_KEYSTORE_PASSWORD_FILE:-$HOME/release-keystore/drive-track-release.password}
if [ ! -f "$KEYSTORE" ]; then echo "缺正式密钥库：$KEYSTORE"; exit 1; fi
if [ ! -f "$PW_FILE" ]; then echo "缺密钥库密码文件：$PW_FILE"; exit 1; fi
# 把签名材料路径传给 Gradle（变量名见 build.gradle.kts）。
export DRIVETRACK_KEYSTORE="$KEYSTORE"
export DRIVETRACK_STORE_PASSWORD="$(cat "$PW_FILE")"
export DRIVETRACK_KEY_PASSWORD="$(cat "$PW_FILE")"
cleanup() {
  unset DRIVETRACK_STORE_PASSWORD DRIVETRACK_KEY_PASSWORD
  rm -f "$GUH/init.d/offline.gradle"
}
(cd android && ./gradlew --stop >/dev/null 2>&1) || true
GUH=$HOME/.gradle
if [ "$OFFLINE_BUILD" = 1 ]; then
  mkdir -p "$GUH/init.d"
  printf 'gradle.startParameter.offline = true\n' > "$GUH/init.d/offline.gradle"
fi
trap cleanup EXIT
# 版本号从 pubspec.yaml 读（形如 version: 1.4.1+54，取 + 前的部分）；
# 读不到即停，不编出文件名带空版本号的包。
VERSION="$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)"
if [ -z "$VERSION" ]; then echo "读不到 pubspec.yaml 的 version"; exit 1; fi
# 可选：高德底图 Key，从本机文件读取后以 --dart-define 注入；
# 无文件则不传，代码侧空值即关闭该数据源；内容不打印。
AMAP_DEFINE=()
if [ -f .amap-key ]; then
  AMAP_DEFINE=(--dart-define="AMAP_KEY=$(cat .amap-key)")
fi
# 可选：云端环境标识，从本机文件读取后以 --dart-define 注入；
# 无文件则不传，代码侧空值即云端未配置；内容不打印。
CLOUDBASE_DEFINE=()
if [ -f .cloudbase-env ]; then
  CLOUDBASE_DEFINE=(--dart-define="CLOUDBASE_ENV_ID=$(cat .cloudbase-env)")
fi
flutter build apk --release --target-platform android-arm --no-android-gradle-daemon "${AMAP_DEFINE[@]}" "${CLOUDBASE_DEFINE[@]}"
cp build/app/outputs/flutter-apk/app-release.apk "./DriveTrack-v${VERSION}-release-armeabi-v7a.apk"
ls -la "./DriveTrack-v${VERSION}-release-armeabi-v7a.apk"
echo BUILD_DONE
