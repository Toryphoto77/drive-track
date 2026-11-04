#!/usr/bin/env python3
"""Map lap-fraction sector boundaries onto OSM package centerlines.

Step 1 of the DriveTrack sector work (2026-11-05). Sources live in
tools/sector-sources.json: sector-END fractions from openly licensed
simulator data (Lovely Sim Racing track data, CC BY-NC-SA 4.0) or from
track-atlas measured sector lines (Laguna Seca), plus track-atlas
start_finish anchors and corner locations used for validation.

Method
------
* The centerline is treated as a closed loop. Cumulative haversine arc
  length gives total L (checked against the package lengthM).
* Anchor: track-atlas start_finish for every mapped package. Our own
  package starts were proven misplaced for 5 of 6 checked packages
  (114-625 m along the start straight), so they are NOT used as anchors;
  with --apply they are corrected to the anchor, because LapTimer sectors
  only work when the lap origin equals the sector origin (sector points
  are crossed in index order within a lap).
* Direction validation (one of three tests, all must pass their gate):
  - per-corner: track-atlas corner locations projected onto our loop;
    forward fractions from the anchor must match their markers
    (median <= 25 m and <= 0.25x the reversed median).
  - set: Lovely turn markers vs our package corners (nearest neighbour,
    no shift scan — a shift would hide an anchor error);
    forward mean <= 100 m and <= 0.6x reversed mean.
  - end-line (Laguna Seca): forward-mapped sector points must land within
    50 m of the measured sector-end line midpoints, while reversed-mapped
    points must miss by >= 200 m.
* Sector fraction f -> arc (s0 + f*L) mod L -> linear interpolation on
  the polyline. The centerline itself is never modified. Only the first
  n-1 markers are written (the final 1.0 is the start/finish line, and
  LapTimer takes sectorPoints.take(2)).

Usage:  python3 tools/sector_map.py [--apply]
  Without --apply: dry run, prints the validation report only.
  With --apply: writes data/packages/*.json (sectorPoints, sectorNote,
  version 1->2, plus start/finish correction where recorded) and bumps
  the same versions in data/tracks-manifest.json. dataVersion untouched.
"""

import json
import math
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PKG_DIR = ROOT / "data" / "packages"
MANIFEST = ROOT / "data" / "tracks-manifest.json"
SOURCES = ROOT / "tools" / "sector-sources.json"
EARTH_R = 6371000.0


def hav(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dq = p2 - p1, math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dq / 2) ** 2
    return EARTH_R * 2 * math.asin(math.sqrt(h))


class Loop:
    """Closed centerline polyline with arc-length parameterisation."""

    def __init__(self, pts):
        if len(pts) > 1 and pts[0] == pts[-1]:
            pts = pts[:-1]
        self.pts = pts
        self.seg_len = []
        self.cum = [0.0]
        n = len(pts)
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            d = hav(a[0], a[1], b[0], b[1])
            self.seg_len.append(d)
            self.cum.append(self.cum[-1] + d)
        self.total = self.cum[-1]

    def project(self, lat, lon):
        """Return (arc_s, off_line_m) of the nearest point on the loop."""
        lat0 = math.radians(lat)
        best = None
        for i in range(len(self.pts)):
            a, b = self.pts[i], self.pts[(i + 1) % len(self.pts)]

            def xy(p):
                return (
                    math.radians(p[1] - lon) * math.cos(lat0) * EARTH_R,
                    math.radians(p[0] - lat) * EARTH_R,
                )

            ax, ay = xy(a)
            bx, by = xy(b)
            dx, dy = bx - ax, by - ay
            seg2 = dx * dx + dy * dy
            t = 0.0 if seg2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / seg2))
            off = math.hypot(ax + t * dx, ay + t * dy)
            if best is None or off < best[1]:
                best = (self.cum[i] + t * self.seg_len[i], off)
        return best

    def point_at(self, s):
        s %= self.total
        lo, hi = 0, len(self.cum) - 1
        while lo < hi - 1:
            mid = (lo + hi) // 2
            if self.cum[mid] <= s:
                lo = mid
            else:
                hi = mid
        i = lo
        seg = self.seg_len[i]
        t = 0.0 if seg == 0 else (s - self.cum[i]) / seg
        a, b = self.pts[i], self.pts[(i + 1) % len(self.pts)]
        return (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))


def circ_dist(a, b):
    d = abs(a - b) % 1.0
    return min(d, 1.0 - d)


def main():
    apply = "--apply" in sys.argv
    sources = json.loads(SOURCES.read_text())
    report = {}
    for pid, cfg in sources.items():
        if pid.startswith("_") or "sectors" not in cfg or "anchor" not in cfg:
            continue
        pkg = json.loads((PKG_DIR / f"{pid}.json").read_text())
        loop = Loop([(p["lat"], p["lon"]) for p in pkg["centerline"]])
        anchor = cfg["anchor"]
        s0, anchor_off = loop.project(anchor["lat"], anchor["lon"])
        entry = {
            "loop_total_m": round(loop.total, 1),
            "pkg_lengthM": pkg["lengthM"],
            "anchor_off_m": round(anchor_off, 1),
        }
        ok = anchor_off <= 25.0
        # Direction validation.
        if "taCorners" in cfg:
            fwd, rev = [], []
            for m, lat, lon in cfg["taCorners"]:
                s, off = loop.project(lat, lon)
                if off > 50.0:
                    continue
                fwd.append(circ_dist(((s - s0) % loop.total) / loop.total, m))
                rev.append(circ_dist(((s0 - s) % loop.total) / loop.total, m))
            fwd_m = statistics.median(fwd) * loop.total
            rev_m = statistics.median(rev) * loop.total
            entry.update({"test": "per-corner", "fwd_med_m": round(fwd_m, 1),
                          "rev_med_m": round(rev_m, 1)})
            ok = ok and fwd_m <= 25.0 and fwd_m <= 0.25 * rev_m
        elif "sectorEndLines" in cfg:
            def map_pts(direction):
                pts = []
                for f in cfg["sectors"]:
                    if f >= 1.0:
                        continue
                    s = (s0 + direction * f * loop.total) % loop.total
                    pts.append(loop.point_at(s))
                return pts

            fwd_d = [hav(p[0], p[1], e["lat"], e["lon"])
                     for p, e in zip(map_pts(1), cfg["sectorEndLines"])]
            rev_d = [hav(p[0], p[1], e["lat"], e["lon"])
                     for p, e in zip(map_pts(-1), cfg["sectorEndLines"])]
            entry.update({"test": "end-line", "fwd_m": [round(d, 1) for d in fwd_d],
                          "rev_m": [round(d, 1) for d in rev_d]})
            ok = ok and max(fwd_d) <= 50.0 and min(rev_d) >= 200.0
        elif "lovelyMarkers" in cfg:
            fwd, rev = [], []
            for c in pkg["corners"]:
                sc, offc = loop.project(c["lat"], c["lon"])
                if offc > 50.0:
                    continue
                fwd.append(((sc - s0) % loop.total) / loop.total)
                rev.append(((s0 - sc) % loop.total) / loop.total)

            def set_err(markers, arcs):
                return sum(min(circ_dist(m, a) for a in arcs)
                           for m in markers) / len(markers) * loop.total

            fwd_m = set_err(cfg["lovelyMarkers"], fwd)
            rev_m = set_err(cfg["lovelyMarkers"], rev)
            entry.update({"test": "set", "fwd_mean_m": round(fwd_m, 1),
                          "rev_mean_m": round(rev_m, 1)})
            ok = ok and fwd_m <= 100.0 and fwd_m <= 0.6 * rev_m
        else:
            ok = False
            entry["test"] = "none"
        mapped = []
        if ok:
            for f in cfg["sectors"]:
                if f >= 1.0:
                    continue
                lat, lon = loop.point_at((s0 + f * loop.total) % loop.total)
                mapped.append({"lat": round(lat, 6), "lon": round(lon, 6)})
        entry["mapped"] = mapped
        entry["ok"] = ok
        report[pid] = entry
        print(f"== {pid}: loop={loop.total:.0f}m anchor_off={anchor_off:.1f}m "
              f"test={entry['test']} mapped={len(mapped)} ok={ok} "
              f"{ {k: v for k, v in entry.items() if k.endswith('_m') or k.endswith('_med_m') or k.endswith('_mean_m')} }")
        if apply and ok:
            pkg["sectorPoints"] = mapped
            pkg["sectorNote"] = cfg["sectorNote"]
            pkg["version"] = pkg["version"] + 1
            if "startCorrection" in cfg:
                pkg["start"] = {"lat": anchor["lat"], "lon": anchor["lon"]}
                pkg["finish"] = {"lat": anchor["lat"], "lon": anchor["lon"]}
                d = cfg["startCorrection"]["distanceM"]
                pkg["startNote"] = (
                    f"起终点已校正：原 OSM 节点偏离真实起终点线约 {d}m，"
                    f"2026-11-05 按 track-atlas 起终点线位置修正"
                    f"（分段计时要求起终点与分段同一起点）"
                )
                print(f"   start corrected by {d}m")
            if cfg.get("startAdded"):
                pkg["start"] = {"lat": anchor["lat"], "lon": anchor["lon"]}
                pkg["finish"] = {"lat": anchor["lat"], "lon": anchor["lon"]}
                pkg["startNote"] = (
                    "起终点新增：本包原无起终点，2026-11-05 按 track-atlas "
                    "起终点线位置补入（分段计时要求起终点与分段同一起点）"
                )
                print("   start added")
            (PKG_DIR / f"{pid}.json").write_text(
                json.dumps(pkg, ensure_ascii=False, indent=2) + "\n"
            )
            print(f"   wrote {pid}.json version {pkg['version']}")
    if apply:
        manifest = json.loads(MANIFEST.read_text())
        bumped = []
        for p in manifest["packages"]:
            if p["id"] in report and report[p["id"]]["ok"]:
                p["version"] = p["version"] + 1
                bumped.append(p["id"])
        MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        print(f"manifest bumped: {bumped}")
    (ROOT / "tools" / "sector-map-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    )
    print("report -> tools/sector-map-report.json")


if __name__ == "__main__":
    main()
