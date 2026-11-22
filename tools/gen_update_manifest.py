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
import argparse, hashlib, json, os, re, subprocess, sys

ABIS = ["arm64-v8a", "armeabi-v7a", "x86_64"]
REPO = "Toryphoto77/drive-track"


def find_aapt(root):
    """定位 aapt：优先 ANDROID_HOME/ANDROID_SDK_ROOT，其次 android/local.properties 的 sdk.dir。"""
    sdks = []
    for env in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        v = os.environ.get(env)
        if v:
            sdks.append(v)
    lp = os.path.join(root, "android", "local.properties")
    if os.path.exists(lp):
        try:
            for line in open(lp, encoding="utf-8"):
                if line.strip().startswith("sdk.dir="):
                    sdks.append(line.split("=", 1)[1].strip().replace("\\\\", "\\"))
        except Exception:
            pass
    for sdk in sdks:
        bt = os.path.join(sdk, "build-tools")
        if not os.path.isdir(bt):
            continue
        for ver in sorted(os.listdir(bt), reverse=True):
            exe = os.path.join(bt, ver, "aapt.exe" if os.name == "nt" else "aapt")
            if os.path.exists(exe):
                return exe
    return None


def apk_version(aapt, path):
    """读 APK 真实 versionName / versionCode；失败返回 None。"""
    if not aapt:
        return None
    try:
        out = subprocess.run(
            [aapt, "dump", "badging", path],
            capture_output=True, text=True, timeout=120,
        ).stdout
    except Exception:
        return None
    m = re.search(r"versionCode='([0-9]+)'\s+versionName='([^']*)'", out)
    if not m:
        return None
    return int(m.group(1)), m.group(2)


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
    ap.add_argument(
        "--force",
        action="store_true",
        help="允许用同一 versionCode 重出清单（只用于修包；正常发版不要用）",
    )
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
    # 发布前校验：包内真实 versionName / versionCode 必须与 pubspec 一致。
    # 之前出过“目录里是旧包、清单写成新版本”的事故，安装时会报“版本号重复”。
    aapt = find_aapt(root)
    if not aapt:
        print("警告：未找到 aapt，跳过 APK 版本号校验（请人工确认包内版本）")
    apks = {}
    for abi in ABIS:
        fn = f"DriveTrack-v{name}-release-{abi}.apk"
        p = os.path.join(root, fn)
        if not os.path.exists(p):
            if a.allow_missing:
                print(f"跳过（缺文件）：{fn}")
                continue
            sys.exit(f"缺正式包：{fn}（先跑对应的 build-apk-*-release.sh）")
        got = apk_version(aapt, p)
        if aapt and got is None:
            sys.exit(f"读不出包内版本号：{fn}（包可能损坏，请重新构建）")
        if got is not None and got != (code, name):
            sys.exit(
                f"版本号不一致：{fn} 实际是 {got[1]}+{got[0]}，"
                f"pubspec 是 {name}+{code}。请重新构建，否则安装会报版本号重复。"
            )
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
    # 版本编号可用性：不得小于已发布版本；等于已发布版本时只允许原包重写清单。
    old_code = old.get("versionCode")
    if isinstance(old_code, int):
        if code < old_code:
            sys.exit(
                f"版本号回退：pubspec {code} 小于已发布清单 {old_code}，"
                f"安卓会拒绝安装（版本号重复/降级）。请提升 versionCode。"
            )
        if code == old_code and not a.force:
            old_apks = old.get("apks") or {}
            same = all(
                (old_apks.get(abi) or {}).get("sha256") == e["sha256"]
                for abi, e in apks.items()
            )
            if not same:
                sys.exit(
                    f"版本号 {code} 已被占用且包内容已变化（已发布清单里是别的包）。"
                    f"正常发版请把 pubspec 的 +版本号 加一；只修包可加 --force。"
                )

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
