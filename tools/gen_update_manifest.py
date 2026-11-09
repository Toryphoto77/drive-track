#!/usr/bin/env python3
"""生成 / 刷新在线更新清单 update-manifest.json（只写本地文件，不联网、不推送）。

用法（在工程根目录、三个正式包编好之后）：
    python3 tools/gen_update_manifest.py --notes "1.5.6：……"

做什么：
- 版本号从 pubspec.yaml 读（version: x.y.z+code），不在这里改版本；
- 找工程根目录下 DriveTrack-v<版本>-release-<abi>.apk（三种架构），
  逐个计算 SHA-256，写进 apks.<abi>.sha256；
- 保留旧字段 apkUrl（arm64-v8a 包）并附 sha256，旧版 App 照常能读；
- 缺任何一个 APK 默认报错退出（--allow-missing 时该架构不写入清单）。
发布前：把清单与 Release 附件一起推送，再刷新 jsDelivr 缓存（见维护说明）。

国内下载：本脚本不编造 CDN 地址。下一版把 APK 放到腾讯云 CloudBase / COS
公共读 URL 后，用 --cdn-base 写入 cdnUrl（每个架构文件名拼在 base 后面，
顶层 cdnUrl 指向 arm64 包）。不传则清单里不出现 cdnUrl。
"""
import argparse, hashlib, json, os, re, sys

ABIS = ["arm64-v8a", "armeabi-v7a", "x86_64"]
REPO = "Toryphoto77/drive-track"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.dirname(__file__), ".."))
    ap.add_argument("--notes", default=None, help="更新说明；不传则沿用现有清单的 notes")
    ap.add_argument("--allow-missing", action="store_true")
    ap.add_argument(
        "--cdn-base",
        default=None,
        help="CloudBase/COS 公共目录（以 / 结尾与否均可）。写入各架构 cdnUrl，不传则不写。",
    )
    ap.add_argument("--out", default=None, help="输出路径，默认 <root>/update-manifest.json")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    pub = open(os.path.join(root, "pubspec.yaml"), encoding="utf-8").read()
    m = re.search(r"^version:\s*([0-9.]+)\+([0-9]+)", pub, re.M)
    if not m:
        sys.exit("读不到 pubspec.yaml 的 version")
    name, code = m.group(1), int(m.group(2))
    out = a.out or os.path.join(root, "update-manifest.json")
    old = {}
    for src in (out, os.path.join(root, "update-manifest.json")):
        if os.path.exists(src):
            try:
                old = json.load(open(src, encoding="utf-8"))
                break
            except Exception:
                old = {}
    apks = {}
    for abi in ABIS:
        fn = f"DriveTrack-v{name}-release-{abi}.apk"
        p = os.path.join(root, fn)
        if not os.path.exists(p):
            if a.allow_missing:
                print(f"跳过（缺文件）：{fn}")
                continue
            sys.exit(f"缺正式包：{fn}（先跑对应的 build-apk-*-release.sh）")
        entry = {
            "url": f"https://github.com/{REPO}/releases/download/v{name}/{fn}",
            "sha256": sha256_file(p),
        }
        if a.cdn_base:
            base = a.cdn_base.rstrip("/") + "/"
            entry["cdnUrl"] = base + fn
        apks[abi] = entry
    if "arm64-v8a" not in apks:
        sys.exit("清单必须包含 arm64-v8a 包（旧版 App 只认 apkUrl = arm64 包）")
    manifest = {
        "_comment": old.get("_comment", "DriveTrack 在线更新清单（国内优先通道）。由 tools/gen_update_manifest.py 生成。"),
        "versionName": name,
        "versionCode": code,
        "apkUrl": apks["arm64-v8a"]["url"],
        "sha256": apks["arm64-v8a"]["sha256"],
        "apks": apks,
        "notes": a.notes if a.notes is not None else old.get("notes", ""),
    }
    if a.cdn_base and "arm64-v8a" in apks and apks["arm64-v8a"].get("cdnUrl"):
        manifest["cdnUrl"] = apks["arm64-v8a"]["cdnUrl"]
    with open(out + ".tmp", "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(out + ".tmp", out)
    print(f"已写入 {out}：{name}+{code}，架构 {', '.join(apks)}")


if __name__ == "__main__":
    main()
