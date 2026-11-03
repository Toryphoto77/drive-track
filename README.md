# 驰迹 DriveTrack

极简风轨迹记录 App（汽车 / 摩托 / 骑行），Flutter + Android，本地存储、不登录、不上传。

- 轨迹、地图、G 值、时间、车速、姿态、定位精度，尽量用手机本身传感器
- 出行天气滚动播报；记录页自绘黑色 3D 透视地图 + OpenStreetMap 路网（Overpass）
- 驾驶习惯评分、0–100 / 100–0 性能测试、赛道模式与赛道图鉴
- 行程结束数据页为车队遥测风格：速度 / G 值 / 海拔 / 压弯曲线统一时间轴联动
- 开始记录前安全守则一键确认（可设“今日内不再弹出”）

## 版本

当前：1.0.7（versionCode 19），包名 `com.chixi.drive_track`，arm64。

## 在线更新

关于页 → 检查更新，走本仓库的 GitHub Releases 最新版接口：

`https://api.github.com/repos/wangtao969/drive-track/releases/latest`

解析 tag 与 arm64 APK 附件。有新版时下载并调起系统安装器。
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
- 传感器校准零偏为运行时内存值，不进设置备份；重装后需重新校零。
- 外接 GPS（Dragy / DEXIAN 等）协议未公开，仅通用 NMEA 兼容，未经实测验证。
- 路网来自公开 Overpass 服务，服务繁忙或国内直连不通时会显示失败原因，
  并可点按状态小字手动重拉；上次成功的数据会按位置缓存。
- 数据仅存本机；个人页邮箱仅存本机，不发验证码、不是账号登录绑定。
