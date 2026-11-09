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

## Notes

- Force-stop from system settings kills the sticky service; recovery depends on drafts already on disk.
- After Activity death without force-stop, `TrackService` may keep writing phone GPS to `recording_native_points.ndjson` (no G/OBD/external BLE in that sidecar).
