#!/usr/bin/env bash
# DriveTrack 本地发版流水线（不推送、不上传、不改远端）。
# 用法（在工程根目录）：
#   bash tools/release_pipeline.sh           # 检查 + 生成清单（需已有三架构 release APK）
#   bash tools/release_pipeline.sh --build   # 先依次跑三架构正式构建，再生成清单
#   bash tools/release_pipeline.sh --notes "说明文字"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NOTES_ARG=()
DO_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build) DO_BUILD=1; shift ;;
    --notes) NOTES_ARG=(--notes "$2"); shift 2 ;;
    -h|--help)
      sed -n '1,12p' "$0"; exit 0 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

VERSION="$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)"
CODE="$(sed -n 's/^version: [0-9.]*+\([0-9]*\).*/\1/p' pubspec.yaml)"
if [[ -z "$VERSION" || -z "$CODE" ]]; then
  echo "读不到 pubspec.yaml 的 version"; exit 1
fi
echo "== DriveTrack release pipeline =="
echo "versionName=$VERSION versionCode=$CODE"
echo "本脚本不执行 git push / gh release / jsDelivr purge / 云端写入。"
echo

ABIS=(arm64-v8a armeabi-v7a x86_64)
SCRIPTS=(
  build-apk-release.sh
  build-apk-armeabi-v7a-release.sh
  build-apk-x86_64-release.sh
)

if [[ "$DO_BUILD" = 1 ]]; then
  for s in "${SCRIPTS[@]}"; do
    echo "---- build $s ----"
    bash "$s"
  done
fi

missing=0
for abi in "${ABIS[@]}"; do
  f="DriveTrack-v${VERSION}-release-${abi}.apk"
  if [[ ! -f "$f" ]]; then
    echo "缺正式包：$f"
    missing=1
  else
    echo "OK $f ($(wc -c <"$f") bytes) sha256=$(sha256sum "$f" | awk '{print $1}')"
  fi
done
if [[ "$missing" = 1 ]]; then
  echo
  echo "请先构建三架构正式包，或加 --build（需本机密钥库环境变量）。"
  echo "  bash build-apk-release.sh"
  echo "  bash build-apk-armeabi-v7a-release.sh"
  echo "  bash build-apk-x86_64-release.sh"
  exit 1
fi

echo
echo "---- gen_update_manifest.py ----"
python3 tools/gen_update_manifest.py "${NOTES_ARG[@]}"

echo
echo "---- verify manifest hashes ----"
python3 - <<'PY'
import json, hashlib, os, sys
m = json.load(open("update-manifest.json", encoding="utf-8"))
apks = m.get("apks") or {}
if not apks:
    sys.exit("清单缺少 apks 字段")
bad = 0
for abi, info in apks.items():
    url = info.get("url") or ""
    expect = (info.get("sha256") or "").lower()
    name = url.rsplit("/", 1)[-1]
    if not os.path.isfile(name):
        print(f"FAIL {abi}: 本地无 {name}"); bad += 1; continue
    got = hashlib.sha256(open(name, "rb").read()).hexdigest()
    if got != expect:
        print(f"FAIL {abi}: sha256 不一致"); bad += 1
    else:
        print(f"OK   {abi}: {got}")
# legacy arm64 fields
if m.get("sha256", "").lower() != (apks.get("arm64-v8a") or {}).get("sha256", "").lower():
    print("FAIL legacy sha256 与 apks.arm64-v8a 不一致"); bad += 1
else:
    print("OK   legacy apkUrl/sha256 对齐 arm64-v8a")
sys.exit(bad)
PY

echo
echo "==== 下一步（需你本人操作，本脚本不会代做）===="
cat <<NEXT
1) git status / diff 确认 update-manifest.json 与版本说明
2) git add / commit（信息自拟；本流水线不 commit）
3) git push origin main
4) 创建 GitHub Release v${VERSION}，上传三架构 APK：
     DriveTrack-v${VERSION}-release-arm64-v8a.apk
     DriveTrack-v${VERSION}-release-armeabi-v7a.apk
     DriveTrack-v${VERSION}-release-x86_64.apk
5) 刷新 jsDelivr 缓存：
     curl -s "https://purge.jsdelivr.net/gh/Toryphoto77/drive-track@main/update-manifest.json"
6) 真机按 RELEASE_CHECKLIST.md 回归后再对外宣布
NEXT
