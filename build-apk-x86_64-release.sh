#!/bin/bash
# 驰迹 DriveTrack 正式签名 APK 离线构建（x86_64）。
# 与 build-apk-release.sh（release，arm64）平行：只改 --target-platform、
# release 引擎检查路径与输出文件名，其余流程（SDK 检查、离线镜像、
# GRADLE_USER_HOME、offline.gradle、正式密钥库、AMAP_KEY 与
# CLOUDBASE_ENV_ID 注入）一字照搬。现有两个脚本不动。
# 签名：DriveTrack 专属密钥库 ~/release-keystore/drive-track-release.keystore
# （alias drivetrack），绝不用 Ordnance 的 guns-map-release.keystore，
# 绝不用 debug 签名。密码只从 600 权限密码文件读出、以环境变量传给
# 构建进程，构建结束即清除环境变量；密码不写进 gradle、不进仓库。
# 目标机型：x86_64 手机 / 平板极少（多为模拟器与 Chromebook 侧载），
# 主力仍是 arm64；本包只作覆盖，不作主推。
# 版本号从 pubspec.yaml 读取（避免硬编码版本号漂移），
# 文件名用完整 ABI 名 x86_64。
# 注意：本脚本只准备、不构建——跑构建是协调人的事。
set -e
export JAVA_HOME=$HOME/sdk/jdk17
export ANDROID_HOME=$HOME/sdk/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$HOME/sdk/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH
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
if [ ! -d "$HOME/gradle-offline-mirror" ]; then echo "缺本地镜像仓库"; exit 1; fi
# release 引擎与 debug 不同：构建前核对齐全，缺失即停，不编出半成品。
# x86_64 对应 android-x64-release（已核实本地存在）。
if [ ! -f "$HOME/sdk/flutter/bin/cache/artifacts/engine/android-x64-release/flutter.jar" ]; then
  echo "缺 Flutter release 引擎：android-x64-release/flutter.jar"; exit 1
fi
KEYSTORE=$HOME/release-keystore/drive-track-release.keystore
PW_FILE=$HOME/release-keystore/drive-track-release.password
if [ ! -f "$KEYSTORE" ]; then echo "缺正式密钥库：$KEYSTORE"; exit 1; fi
if [ ! -f "$PW_FILE" ]; then echo "缺密钥库密码文件：$PW_FILE"; exit 1; fi
export DRIVETRACK_STORE_PASSWORD="$(cat "$PW_FILE")"
export DRIVETRACK_KEY_PASSWORD="$(cat "$PW_FILE")"
cleanup() {
  unset DRIVETRACK_STORE_PASSWORD DRIVETRACK_KEY_PASSWORD
  rm -f "$GUH/init.d/offline.gradle"
}
(cd android && ./gradlew --stop >/dev/null 2>&1) || true
GUH=$HOME/.gradle
mkdir -p "$GUH/init.d"
printf 'gradle.startParameter.offline = true\n' > "$GUH/init.d/offline.gradle"
trap cleanup EXIT
# 版本号从 pubspec.yaml 读（形如 version: 1.4.1+54，取 + 前的部分）；
# 读不到即停，不编出文件名带空版本号的包。
VERSION="$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)"
if [ -z "$VERSION" ]; then echo "读不到 pubspec.yaml 的 version"; exit 1; fi
# 高德 Web 服务 Key（仅本地 .amap-key 文件，600 权限，
# gitignore，不进仓库、不进推送清单）：有则以 --dart-define 注入，
# 无则不传，代码侧空值即禁用高德源；Key 绝不回显到日志。
AMAP_DEFINE=()
if [ -f .amap-key ]; then
  AMAP_DEFINE=(--dart-define="AMAP_KEY=$(cat .amap-key)")
fi
# 云端二期：CloudBase 环境 ID（仅本地 .cloudbase-env 文件，600 权限，
# gitignore，不进仓库、不进推送清单）：有则以 --dart-define 注入，
# 无则不传，代码侧空值即云端未配置、上传禁用；内容绝不回显到日志。
CLOUDBASE_DEFINE=()
if [ -f .cloudbase-env ]; then
  CLOUDBASE_DEFINE=(--dart-define="CLOUDBASE_ENV_ID=$(cat .cloudbase-env)")
fi
flutter build apk --release --target-platform android-x64 --no-android-gradle-daemon "${AMAP_DEFINE[@]}" "${CLOUDBASE_DEFINE[@]}"
cp build/app/outputs/flutter-apk/app-release.apk "./DriveTrack-v${VERSION}-release-x86_64.apk"
ls -la "./DriveTrack-v${VERSION}-release-x86_64.apk"
echo BUILD_DONE
