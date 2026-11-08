# 驰迹 DriveTrack

> 一台手机，就是你的赛道遥测站。

[![Latest Release](https://img.shields.io/github/v/release/Toryphoto77/drive-track)](https://github.com/Toryphoto77/drive-track/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84)](https://github.com/Toryphoto77/drive-track/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B)](https://flutter.dev)
[![Downloads](https://img.shields.io/github/downloads/Toryphoto77/drive-track/total)](https://github.com/Toryphoto77/drive-track/releases/latest)

**驰迹**是一款极简风轨迹记录 App：开车、骑车、摩托，一键开始记录。轨迹、地图、G 值、车速、姿态、定位精度——尽量只用手机本身的传感器，不依赖外设。

黑色 HUD 界面，没有导航式的杂乱信息：记录时只看该看的，结束后再慢慢复盘。

## 下载

最新版见 [Releases](https://github.com/Toryphoto77/drive-track/releases/latest)（当前 v1.5.3）。三个安装包按手机架构选一个即可，大多数手机用 arm64-v8a：

| 安装包 | 适用机型 |
| --- | --- |
| `DriveTrack-v*-release-arm64-v8a.apk` | 绝大多数安卓手机 |
| `DriveTrack-v*-release-armeabi-v7a.apk` | 老款 32 位手机 |
| `DriveTrack-v*-release-x86_64.apk` | x86 平板 / 模拟器 |

直接覆盖安装即可升级，不要卸载重装（本机行程存在本地，卸载会丢）。

## 能做什么

### 记录

- 轨迹、地图、G 值、时间、车速、姿态、定位精度，全程记录
- 开始记录前安全守则一键确认（可设“今日内不再弹出”）
- 出行天气滚动播报；记录页自绘黑色 3D 透视地图 + OpenStreetMap 路网
- 街道模式超速语音提示、GPS 丢失报警；赛道模式报圈速与 Delta
- 自定义语音：支持 8 家 TTS（OpenAI / Azure / Google / MiniMax / ElevenLabs / Fish Audio / 豆包 / CosyVoice）
- 321 倒计时带强震反馈

### 赛道

- 赛道模式：大字当前圈 + 分段着色、官方分段点、带符号的 Delta、单圈最佳为默认参照
- 赛道库：78 条赛道（F1、中国系列、经典赛道），几何逐条核对，长度对照 FIA 官方数据
- 0–100 / 100–0 性能测试；驾驶习惯评分，扣分项透明可见

### 复盘

- 行程结束数据页为车队遥测风格：速度 / G 值 / 海拔 / 压弯曲线统一时间轴联动
- 赛后分析页：曲线 + 着色线路，不依赖视频
- 行程可导出、可分享；赛道包支持官方更新与本地编辑（官方更新不覆盖本地改动）

### 云端（可选）

- 匿名登录即可用；行程只在你点上传时才上传，不自动同步
- 行程与公开资料可设为公开（默认仅本人可见）
- 云端走腾讯 CloudBase（上海），免费体验版

### 外接设备

- 外置 GPS 单入口一键扫描：DEXIAN D1、RaceBox、Dragy、Qstarz 等（通用 NMEA 兼容；私有协议设备以实测为准）
- 自研 GPS+IMU 硬件方案也在推进中（ESP32-S3 + NEO-M9N + BMI088 + 气压计，车顶安装）

## 版本

当前：1.5.3（versionCode 58），包名 `com.chixi.drive_track`，三 ABI 同发。

## 在线更新

关于页 → 检查更新，走本仓库的 GitHub Releases 最新版接口：

`https://api.github.com/repos/Toryphoto77/drive-track/releases/latest`

解析 tag 与对应架构的 APK 附件。有新版时下载并调起系统安装器。
Release 本身与 APK 附件需另行创建；Release 建好之前，检查会如实报失败，
不谎称“已是最新版”。

## 构建

Debug（不需要签名）：

```sh
flutter build apk --debug --target-platform android-arm64
```

Release 签名配置在本机构建脚本与密钥库里，不进仓库。
自行发正式版时，请用自己的密钥库替换 `android/app/build.gradle.kts`
里的 release signing 配置，不要把密钥库或密码提交到仓库。

## 说明与限制

- 本仓库的快照推送只含 UTF-8 文本源码：二进制资源（`assets/app_icon_*.png`、
  `assets/fonts/*`、启动图标 mipmap PNG）不在推送里，拉下来后需自行恢复
  这些资源再构建；图标与字体属本地资源。
- 传感器校准零偏只存内存，重启 App 即失效，需重新校零。
- 外接 GPS 协议未公开，仅通用 NMEA 兼容，未经实测验证。
- 路网来自公开 Overpass 服务，服务繁忙或国内直连不通时会显示失败原因，
  并可点按状态小字手动重拉；上次成功的数据会按位置缓存。
- 数据默认只存本机；个人页邮箱仅存本机，不发验证码、不是账号登录绑定。
  云端上传与公开均为手动操作，不会自动同步。
