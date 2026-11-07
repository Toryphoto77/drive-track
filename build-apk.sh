#!/bin/bash
# 驰迹 DriveTrack debug APK 离线构建（arm64）。
# 不用 Ordnance 的正式签名密钥库；debug 包用 Flutter 默认 debug 签名。
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
(cd android && ./gradlew --stop >/dev/null 2>&1) || true
GUH=$HOME/.gradle
mkdir -p "$GUH/init.d"
printf 'gradle.startParameter.offline = true\n' > "$GUH/init.d/offline.gradle"
trap 'rm -f "$GUH/init.d/offline.gradle"' EXIT
# 云端二期：CloudBase 环境 ID（仅本地 .cloudbase-env 文件，600 权限，
# gitignore，不进仓库、不进推送清单）：有则以 --dart-define 注入，
# 无则不传，代码侧空值即云端未配置、上传禁用；内容绝不回显到日志。
CLOUDBASE_DEFINE=()
if [ -f .cloudbase-env ]; then
  CLOUDBASE_DEFINE=(--dart-define="CLOUDBASE_ENV_ID=$(cat .cloudbase-env)")
fi
flutter build apk --debug --target-platform android-arm64 --no-android-gradle-daemon "${CLOUDBASE_DEFINE[@]}"
cp build/app/outputs/flutter-apk/app-debug.apk ./DriveTrack-v0.1.10-debug-arm64.apk
ls -la ./DriveTrack-v0.1.10-debug-arm64.apk
echo BUILD_DONE
