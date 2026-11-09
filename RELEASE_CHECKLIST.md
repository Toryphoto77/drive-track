# DriveTrack release checklist

Use before announcing a build. Do not skip device rows for BLE / force-stop / overlay install.

## Build & publish (local script does not push)

- [ ] `bash tools/release_pipeline.sh` (or `--build` when keystore env is ready)
- [ ] Manifest `apks` has arm64-v8a / armeabi-v7a / x86_64 with matching SHA-256
- [ ] You push `update-manifest.json`, create the GitHub Release, upload the three APKs
- [ ] Purge jsDelivr cache for `update-manifest.json`
- [ ] Signing key unchanged from previous Play/sideload users (overlay install)

## Device regression

- [ ] **BLE / BT GPS / OBD**: scan → connect → live data; unfiltered scan after a filtered scan still works
- [ ] **Force-stop recovery**: record ≥2 minutes → force-stop in system settings → reopen → Unfinished recording → Save trip
- [ ] **Swipe away while recording**: notification stays (“Recording active…”); reopen app; draft / native points recover
- [ ] **Intentional stop**: End trip → foreground notification gone; no orphan GPS
- [ ] **Public trim**: publish with privacy trim on → public view missing ~400 m at each end; no local video/photo paths
- [ ] **Overlay install**: install new APK over old signed build without uninstall; trips still listed
- [ ] **Multi-arch update**: arm64 phone and a 32-bit (armeabi-v7a) device/emulator each get the matching package; wrong sha256 refuses install
- [ ] **GPS source HUD**: recording shows phone vs external, accuracy meters, device name when external is active
- [ ] **Cloud compare**: Cloud page → Compare local vs cloud shows Local N / Cloud N; no silent overwrite
- [ ] **Bottom nav alignment**: portrait, 4 tabs (首页 / 设备 / 记录 / 我的). The sliding selected circle shares a horizontal center with the icon and the tap target. Landscape recording hides the pill; if a future build shows it in landscape, recheck there too.
- [ ] **Top alignment**: 首页 / 设备 / 记录 / 我的 first content sits flush under the app bar. No extra blank band on 设备 or 我的.
- [ ] **My page scroll**: scroll 我的 to the end. The last buttons stay fully above the frosted pill and can be tapped.
- [ ] **Trip analysis**: 行程分析 uses the same cards and translucent app bar as the trip list. Title and range chips read in the current language. Nothing sits in a gap under the bar or under the gesture area.
- [ ] **Track landscape**: while recording a track in landscape, the map is on the left and the only instrument column is on the right (lap time, Delta, S1/S2/S3, speed, lat G / lean). Lap time and Delta are not repeated as a second full timing stack on the left. Delta is readable at a glance (green faster / red slower). Lap history stays behind「圈速明细」. Full map shows only corner capsules, not a second column. Portrait track timing is unchanged. Street landscape still has pause / hold-to-end.
- [ ] **G-G**: portrait street and portrait track show a G-G plot (lateral on X, longitudinal on Y, live dot, short trail, session peak ticks) plus a small numeric readout. Track landscape shows a compact cross (up/down long, left/right lat) with current and peak numbers, not a second full plot. Before heading calibration the label is 未标定 and the dot is absent. After calibration the axes stay vehicle-frame (smoothLong / smoothLat), not raw phone axes.

## Update mirrors (next ship, not this manifest)

- [ ] Host the three APKs on a Tencent CloudBase / COS public URL
- [ ] Put that URL in `cdnUrl` (per ABI and/or top-level for the arm64 `apkUrl`). Do not invent a placeholder URL
- [ ] `python3 tools/gen_update_manifest.py --notes "…" --cdn-base https://<bucket>/` writes `cdnUrl` from real files only
- [ ] In-app download tries `cdnUrl` / `mirrors` first, then GitHub, then the built-in proxies (`ghfast.top`, `gh-proxy.com`, `mirror.ghproxy.com`) unless `githubProxyFallback` is false
- [ ] Progress text shows 国内源 / GitHub / 备用源 and a speed. SHA-256 still rejects a bad file

## Notes

- Force-stop from system settings kills the sticky service; recovery depends on drafts already on disk.
- After Activity death without force-stop, `TrackService` may keep writing phone GPS to `recording_native_points.ndjson` (no G/OBD/external BLE in that sidecar).
