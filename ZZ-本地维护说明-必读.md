# DriveTrack 本地维护说明（必读）

工程版本：**v1.5.4+59**（2026-11-09 打包）。包名 `com.chixi.drive_track`，仓库 Toryphoto77/drive-track。

## ⚠️ 先看安全警告

本源码包是**脱敏版**：不含签名密钥库、密钥库密码、高德 Key、CloudBase 环境 ID、`local.properties`、构建缓存。这些文件只在你自己的备份里，**绝不要放进源码包、公开仓库或群聊**：

- 正式签名密钥库 `drive-track-release.keystore`（alias drivetrack）+ 密码文件：丢了它，以后编的包就装不到现在这台手机上（签名对不上，只能卸载重装，本机行程全丢）。**密钥库和密码分开保管**，不要放在同一个压缩包里。
- `.amap-key`：高德 Web 服务 Key（没有它，高德地图功能会被禁用）。它会经 `--dart-define` 编进 APK，任何人都能从 APK 里取出来，所以请在高德控制台设好用量上限。
- `.cloudbase-env`：腾讯 CloudBase 环境 ID。它本身不是密码（同样会编进 APK），安全靠数据库 / 存储的 RLS 策略（见 `cloudbase/`）。
- `.supabase-key`：旧 Supabase 项目已废弃，那个 service_role key 绝不能进 App。

模板：`.amap-key.example`、`.cloudbase-env.example`（只有占位说明，没有真实值）。复制成 `.amap-key` / `.cloudbase-env` 并填入真实值即可，这两个文件已在 `.gitignore` 里。

## 包里有什么、没什么

包含：`lib/`（全部 Dart 源码）、`android/`（原生代码与配置，含 Gradle wrapper）、`test/`、`assets/`、`data/`（赛道库数据）、`cloudbase/`（云端 SQL）、`tools/`（含 `gen_update_manifest.py`）、`icon-concepts/`、`build-logs/`（历史记录，内容是当时的结果，不代表本版）、`flutter-tools-gradle/`（Flutter Gradle 插件，必需）、`tracks-space-data.json`、6 个构建脚本、密钥模板。

没包含：签名密钥与密码、`.amap-key`、`.cloudbase-env`、`android/local.properties`（`flutter` 命令会自动生成）、`build/`、`.dart_tool/`、各类 `.gradle/` `.kotlin/` 缓存、`__pycache__`、历史 APK。

## 在自己电脑上搭环境

1. 装 Flutter **3.47.8**、JDK **17**、Android SDK（需要 API 36、build-tools 36.0.0、NDK 28.2.13676358），建议装 Android Studio。
2. 解压后进工程目录，先跑 `flutter pub get`。
3. 签名密钥：把密钥库和密码文件放到 `~/release-keystore/`（默认位置：`drive-track-release.keystore` 与 `drive-track-release.password`）。放在别处时用环境变量指定，不用改脚本 / Gradle：
   - `DRIVETRACK_KEYSTORE=/path/to/drive-track-release.keystore`
   - `DRIVETRACK_KEYSTORE_PASSWORD_FILE=/path/to/drive-track-release.password`
   - （可选）`DRIVETRACK_KEY_ALIAS`，默认 `drivetrack`
   `android/app/build.gradle.kts` 不再写死某台机器的绝对路径，读 `DRIVETRACK_KEYSTORE`，未设时回落 `~/release-keystore/`。
4. 检查：`flutter analyze` 应为 No issues；`flutter test` 应全部通过（以实际输出为准）。

### 构建脚本的两种模式（2026-11-09 已改好）

构建脚本（`build-apk*.sh`）现在是双模式的，会自动判断：

- **有离线镜像**（本机沙箱才有）：走离线构建。
- **无离线镜像**（你自己的电脑一般没有）：走**在线构建**，Gradle 直接联网下载依赖。

所以在你电脑上不用建什么镜像，联网就能编。另有两点要注意：

- 脚本默认 Flutter 在 `~/sdk/flutter`、JDK 在 `~/sdk/jdk17`、Android SDK 在 `~/sdk/android-sdk`；装在别处时设环境变量 `DRIVETRACK_FLUTTER_HOME` / `DRIVETRACK_JAVA_HOME` / `DRIVETRACK_ANDROID_HOME`，不必改脚本。
- `flutter-tools-gradle/` 这个目录**必须留着**（已放进包里）：`android/settings.gradle.kts` 用 `includeBuild` 引用它，而 `flutter pub get` 不会重新生成它，删了就编不过。里面的 `.gradle/`、`build/`、`.kotlin/` 缓存已去掉，重新编时会自动生成。

## 编正式包

```bash
./build-apk-release.sh            # arm64-v8a（你手机用的）
./build-apk-armeabi-v7a-release.sh
./build-apk-x86_64-release.sh
```

产物在工程根目录，形如 `DriveTrack-v1.5.4-release-arm64-v8a.apk`。**正式包直接覆盖安装，绝不卸载**（卸载丢本机行程）。验签：`apksigner verify --verbose` 应显示 v2 scheme true，指纹 SHA-256 应为 `5ba8fb8f…`（与密钥库一致）。

## 版本号怎么升

改版本号要同步改 7 处（有测试钉着，漏了测试会失败）：`pubspec.yaml`（如 `1.5.4+59`）、`lib/update_service.dart` 的 `currentVersionName` 与 `currentVersionCode`、`lib/main.dart` 的 `versionName`、4 处 `DriveTrack/x.y.z` User-Agent、`README.md`（2 处）、`update-manifest.json`（versionName / versionCode / apkUrl / notes）。测试里的“新版”模拟值必须高于当前版，否则测试会报 available/upToDate 不符。

## 在线更新清单

`update-manifest.json` 是 App 在线更新的国内优先清单。

- 新格式带 `apks`：按架构（arm64-v8a / armeabi-v7a / x86_64）各给下载地址和 `sha256`；App 按手机实际架构选包，有 `sha256` 时下载后校验，不一致直接丢弃、不安装；没有 `sha256` 时照常安装但明确提示“未校验”。
- 旧字段 `apkUrl`（arm64 包）保留，旧版 App 仍只读它。
- 生成方法：三个正式包编好后在工程根目录跑 `python3 tools/gen_update_manifest.py --notes "更新说明"`，它从 `pubspec.yaml` 读版本、按实际 APK 算摘要并写清单（只写本地文件，不联网）。
- 发版时清单要和 Release 附件一起推到 main，再刷新 jsDelivr 缓存：`https://purge.jsdelivr.net/gh/Toryphoto77/drive-track@main/update-manifest.json`。2026-11-09 核对时 main 上还没有这个文件（jsDelivr 返回 404），没推之前国内通道会回落到 GitHub 接口。
- GitHub 回落：按架构挑 Release 附件，GitHub 提供 `digest` 时同样校验。

## 录制草稿与恢复

记录中每 30 秒增量落盘（v2）：
- `recording_draft_meta.json`：模式 / 照片 / 圈速等元数据（原子整写）
- `recording_draft_points.ndjson` / `recording_draft_obd.ndjson`：只追加新点
- 仍可读旧版整文件 `recording_draft.json`

前台服务 `TrackService` 在记录中用 `START_STICKY`；Activity 被划掉后不主动停服务，服务继续把手机 GPS 追加到 `recording_native_points.ndjson`。下次启动 Flutter 草稿与原生侧车按时间合并。通知文案提示 Force-stop 可能中断。强制停止 App 时系统不会重建服务，只能靠已落盘草稿。

启动弹 “Unfinished recording”；选 Later 的旧草稿会在下次开始记录前自动存成行程。中断时未收尾的视频不关联到恢复行程。

## 行程文件扩展

轨迹点 ≥ 2000 时，主 JSON 的 `points` 置空，另写 `trip_{id}.points.ndjson`（键 `pointsFile`）。旧版内联 `trip_*.json` 仍可直接读取，无需一次性迁移。

## 数据文件写入

行程、索引、收藏、车辆档案、云端上传队列一律“先写 .tmp 再改名”（原子写）。索引损坏或丢失时自动从 `trip_*.json` 重建，损坏的旧索引改名为 `trips_index.corrupt-<时间>.json` 留底，不删任何行程文件。

## 底栏设备中心 / 冷启动 / 图标清理（2026-11-09）

- 设备中心是底栏第 2 页（与首页/记录/我的同壳、同 AnimatedSwitcher），`DeviceCenterPage(embedded: true)`：无返回 AppBar，页内标题“设备中心”，底部为药丸留白。设置等子页仍可 push 带返回的独立页。
- 冷启动：`values-v31` 系统 Splash 图标圆底纯黑；Flutter `SplashPage` 首帧图标满不透明、底色纯黑，避免无进程冷启动闪一下。
- 废弃 Flutter assets（`app_icon.png` / red / rb17 / valkyrie）与旧 adaptive `ic_launcher*` 已删；桌面 alias 用的 steering/checkered/rb17/valkyrie mipmap 保留。

## 发版流水线

本地：`bash tools/release_pipeline.sh`（可选 `--build`）。脚本生成并核对 `update-manifest.json` 三架构摘要，打印 push / Release / jsDelivr 刷新步骤，**不**代执行推送。真机项见 `RELEASE_CHECKLIST.md`。

## 重要约定（别踩）

- `android/gradle.properties` 里有 `kotlin.compiler.execution.strategy=in-process`，别删（Kotlin 守护进程在沙箱里起不来；你电脑上其实不需要，但留着也没坏处）。
- 赛道库数据只用 OSM（ODbL 需署名）+ 开源社区 + 官方公开事实 + 实测，严禁复制 RaceChrono / Harry's / VBOX 专有库；未核对的标“待核”，不得冒充实测/官方。
- 发布文档与所有文字须删竞品品牌/型号名，设备匹配与适配部分除外。
- 正式版软件里不能出现测试时的文案，操作指导该留的还得留着。
