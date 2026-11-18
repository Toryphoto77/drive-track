#!/usr/bin/env python3
"""Geometric checks for DriveTrack enclosure v9 STLs. Inspection only."""
from __future__ import annotations

import math
import os
import sys
import traceback

import numpy as np
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import enclosure_v9 as e  # noqa: E402


def load(name):
    path = os.path.join(HERE, name)
    m = trimesh.load(path, force="mesh")
    if not isinstance(m, trimesh.Trimesh):
        m = trimesh.util.concatenate(tuple(m.geometry.values()))
    return path, m


def bbox(m):
    b = m.bounds
    return b[0], b[1], b[1] - b[0]


def ray_hits(mesh, origins, dirs):
    locs, idx_ray, _ = mesh.ray.intersects_location(origins, dirs, multiple_hits=True)
    groups = [[] for _ in range(len(origins))]
    for loc, r in zip(locs, idx_ray):
        groups[int(r)].append(loc)
    return groups


def contains_xy_zrange(mesh, x, y, z0, z1, n=7):
    """True if a downward and upward ray through (x,y) hits a surface in [z0,z1]."""
    origins = np.array([[x, y, z1 + 2.0], [x, y, z0 - 2.0]])
    dirs = np.array([[0, 0, -1.0], [0, 0, 1.0]])
    hits = ray_hits(mesh, origins, dirs)
    zs = []
    for group in hits:
        for p in group:
            zs.append(p[2])
    in_range = [z for z in zs if z0 - 0.05 <= z <= z1 + 0.05]
    return len(in_range) > 0, zs


def point_is_inside(mesh, points):
    try:
        return mesh.contains(points)
    except Exception:
        # fallback: odd number of hits upward
        origins = np.asarray(points)
        dirs = np.tile(np.array([[0.0, 0.0, 1.0]]), (len(origins), 1))
        hits = ray_hits(mesh, origins, dirs)
        return np.array([len(h) % 2 == 1 for h in hits])


def min_dist_point_to_ring(px, py, polygon):
    from shapely.geometry import Point
    return Point(px, py).distance(polygon.exterior)


def main():
    lines = []
    ok = True

    def log(msg=""):
        print(msg)
        lines.append(msg)

    def check(name, cond, detail=""):
        nonlocal ok
        flag = "PASS" if cond else "FAIL"
        if not cond:
            ok = False
        log(f"  [{flag}] {name}" + (f" — {detail}" if detail else ""))

    log("DriveTrack enclosure v9 — geometric verify")
    log(f"  source: {e.__file__}")
    log()
    log("Locked dimensions (from enclosure_v9.py)")
    log(f"  body            {e.BODY_X1-e.BODY_X0:.2f} x {e.BODY_Y1-e.BODY_Y0:.2f} x {e.LID_TOP_Z:.2f} mm")
    log(f"  with seal flange {e.FLANGE_X1-e.FLANGE_X0:.2f} x {e.FLANGE_Y1-e.FLANGE_Y0:.2f} mm")
    log(f"  cavity          {e.CAV_X1-e.CAV_X0:.2f} x {e.CAV_Y1-e.CAV_Y0:.2f} mm")
    log(f"  inner height    {e.LID_CEILING_Z-e.FLOOR_Z:.2f} mm  (floor z={e.FLOOR_Z:.2f} to ceiling z={e.LID_CEILING_Z:.2f})")
    log(f"  PCB origin      ({e.PCB_X0:.2f}, {e.PCB_Y0:.2f}), thickness {e.BOARD_T:.2f}, seat z={e.PCB_Z0:.2f}..{e.PCB_Z1:.2f}")
    log(f"  USB inner       ({e.USB_XC:.2f}, {e.USB_Y_INNER:.2f}), opening {e.USB_OUT_W:.2f} x {e.USB_OUT_H:.2f} at z={e.USB_ZC:.2f}")
    log(f"  LED window      x={e.LED_X0:.2f}..{e.LED_X1:.2f}, y={e.LED_Y0:.2f}..{e.LED_Y1:.2f}, membrane {e.LED_MEMB_T:.2f} mm")
    log(f"  vent            (-X wall) y={e.VENT_YC:.2f}, z={e.VENT_ZC:.2f}, id={e.VENT_ID:.2f}")
    log(f"  battery bay     x={e.BATT_X0:.2f}..{e.BATT_X1:.2f}, y={e.BATT_Y0:.2f}..{e.BATT_Y1:.2f}, z={e.CELL_Z0:.2f}..{e.CELL_Z1:.2f}")
    log("  mounting holes (enclosure mm):")
    for name, (x, y) in e.MH.items():
        log(f"    {name}  ({x:.2f}, {y:.2f})  pilot Ø{e.STANDOFF_ID:.2f}, boss Ø{e.STANDOFF_OD:.2f}, blind below z={e.STANDOFF_Z0:.2f}")
    log("  lid screws (enclosure mm):")
    for i, (x, y) in enumerate(e.SCREW, 1):
        log(f"    S{i}  ({x:.2f}, {y:.2f})  thru Ø{e.SCREW_THRU_D:.2f}")
    log()

    meshes = {}
    for name in ("base-v9.stl", "lid-v9.stl", "assembled-v9-DO-NOT-PRINT.stl"):
        path, m = load(name)
        meshes[name] = m
        (lo, hi, size) = bbox(m)
        log(f"STL {name}")
        log(f"  path={path}  bytes={os.path.getsize(path)}  faces={len(m.faces)}  verts={len(m.vertices)}")
        log(f"  bbox=[{lo[0]:.2f},{lo[1]:.2f},{lo[2]:.2f}]..[{hi[0]:.2f},{hi[1]:.2f},{hi[2]:.2f}]  size={size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f}")
        log(f"  is_volume={m.is_volume}  is_watertight={m.is_watertight}  euler={m.euler_number}")
        try:
            log(f"  volume={m.volume:.1f} mm^3")
        except Exception as exc:
            log(f"  volume failed: {exc}")
        if name != "assembled-v9-DO-NOT-PRINT.stl":
            check(f"{name} is a volume", bool(m.is_volume))
            check(f"{name} is watertight", bool(m.is_watertight))
        log()

    base, lid = meshes["base-v9.stl"], meshes["lid-v9.stl"]
    blo, bhi, bsz = bbox(base)
    llo, lhi, lsz = bbox(lid)

    check("base XY matches flange", abs(bsz[0] - (e.FLANGE_X1 - e.FLANGE_X0)) < 0.15 and abs(bsz[1] - (e.FLANGE_Y1 - e.FLANGE_Y0)) < 0.15,
          f"{bsz[0]:.2f} x {bsz[1]:.2f}")
    check("base height to split", abs(bhi[2] - e.SPLIT_Z) < 0.15, f"zmax={bhi[2]:.2f}")
    check("lid XY matches flange", abs(llo[0] - e.FLANGE_X0) < 0.15 and abs(lhi[0] - e.FLANGE_X1) < 0.15)
    check("lid roof at LID_TOP_Z (+ typography relief)", abs(lhi[2] - (e.LID_TOP_Z + e.LID_RELIEF)) < 0.20, f"zmax={lhi[2]:.2f}")
    check("GPS lid thickness target 2.00 mm", abs((e.LID_TOP_Z - e.LID_CEILING_Z) - 2.00) < 0.01)

    # Blind standoffs: floor closed at z=0
    log()
    log("Standoffs (must be blind from below)")
    for name, (x, y) in e.MH.items():
        # ray from z=-2 upward
        hits = ray_hits(base, np.array([[x, y, -2.0]]), np.array([[0, 0, 1.0]]))[0]
        zs = sorted(p[2] for p in hits)
        floor_hit = any(z < e.STANDOFF_Z0 + 0.15 for z in zs)
        check(f"{name} floor closed", floor_hit, f"upward hits z={['{:.2f}'.format(z) for z in zs]}")
        # a point just under the mesh at z=-0.1 should be OUTSIDE, a point in the floor at (x,y,0.4) INSIDE
        inside_floor = point_is_inside(base, np.array([[x, y, 0.40]]))[0]
        check(f"{name} solid floor at z=0.40", bool(inside_floor))

    # LED membrane
    log()
    log("LED window membrane (0.80 mm, not a through-hole)")
    lx, ly = 0.5 * (e.LED_X0 + e.LED_X1), 0.5 * (e.LED_Y0 + e.LED_Y1)
    # membrane occupies z = LID_CEILING_Z .. LID_CEILING_Z+LED_MEMB_T (18.00..18.80)
    # recess above that to the roof
    mid_z = e.LID_CEILING_Z + 0.40
    in_mem = point_is_inside(lid, np.array([[lx, ly, mid_z]]))[0]
    above = point_is_inside(lid, np.array([[lx, ly, e.LID_TOP_Z - 0.10]]))[0]
    below = point_is_inside(lid, np.array([[lx, ly, e.LID_CEILING_Z - 0.40]]))[0]
    check("membrane present at mid-thickness", bool(in_mem), f"point ({lx:.2f},{ly:.2f},{mid_z:.2f})")
    check("no solid in the outer recess", not bool(above))
    check("window is not a through-hole into the cavity", not bool(below))

    # USB opening through the +Y body wall (not the low foot flange)
    log()
    log("USB opening")
    usb_pt = np.array([[e.USB_XC, (e.USB_Y_INNER + e.BODY_Y1) / 2, e.USB_ZC]])
    usb_filled = point_is_inside(base, usb_pt)[0]
    check("USB wall opening is empty", not bool(usb_filled), f"point {usb_pt[0]}")

    # Vent through -X wall
    log()
    log("Vent")
    vent_pt = np.array([[e.BODY_X0 + e.WALL / 2, e.VENT_YC, e.VENT_ZC]])
    vent_filled = point_is_inside(base, vent_pt)[0]
    check("vent bore is empty", not bool(vent_filled), f"point {vent_pt[0]}")

    # No power-button hole on the other walls (sample mid-height, mid-sides, skip USB/vent)
    log()
    log("No panel button hole (sampled side walls)")
    samples = [
        ("+X mid", e.BODY_X1 - e.WALL / 2, 0.5 * (e.BODY_Y0 + e.BODY_Y1), 8.0),
        ("-Y mid", 0.5 * (e.BODY_X0 + e.BODY_X1), e.BODY_Y0 + e.WALL / 2, 8.0),
        ("-X away from vent", e.BODY_X0 + e.WALL / 2, e.BODY_Y0 + 15.0, 8.0),
        ("+Y away from USB", e.BODY_X1 - 15.0, e.BODY_Y1 - e.WALL_USB / 2, 8.0),
    ]
    for name, x, y, z in samples:
        filled = point_is_inside(base, np.array([[x, y, z]]))[0]
        check(f"wall solid at {name}", bool(filled), f"({x:.2f},{y:.2f},{z:.2f})")

    # Gasket vs screws vs cavity
    log()
    log("Gasket / screw / cavity relationship")
    body = e._rounded_rect_poly(e.BODY_X0, e.BODY_Y0, e.BODY_X1, e.BODY_Y1, e.PLAN_R)
    cl = body.buffer(e.GASKET_CL_OUTSET, resolution=24, join_style=1)
    cav = e._rounded_rect_poly(e.CAV_X0, e.CAV_Y0, e.CAV_X1, e.CAV_Y1, max(0.5, e.PLAN_R - 1.50))
    from shapely.geometry import Point, box
    for i, (x, y) in enumerate(e.SCREW, 1):
        d_cl = Point(x, y).distance(cl.exterior)
        d_cav = Point(x, y).distance(cav)
        in_cav = cav.contains(Point(x, y))
        check(f"S{i} outside cavity", (not in_cav) and d_cav > 2.0, f"dist to cavity={d_cav:.2f} mm")
        check(f"S{i} outboard of gasket centerline", d_cl > (e.GROOVE_W / 2 + e.SCREW_THRU_D / 2),
              f"dist to CL={d_cl:.2f} mm (need > {e.GROOVE_W/2 + e.SCREW_THRU_D/2:.2f})")
    # groove actually exists: a point on the mid of the -Y gasket CL at split-0.7 should be empty
    mid_cl = (0.5 * (e.BODY_X0 + e.BODY_X1), e.BODY_Y0 - e.GASKET_CL_OUTSET, e.SPLIT_Z - e.GROOVE_H / 2)
    g_empty = not point_is_inside(base, np.array([mid_cl]))[0]
    check("groove empty at -Y mid-span", g_empty, f"point {tuple(round(v,2) for v in mid_cl)}")

    # FPC vs GPS
    log()
    log("Antenna keepout")
    fpc = box(e.FPC_X0, e.FPC_Y0, e.FPC_X1, e.FPC_Y1)
    gps = box(e.GPS_X0, e.GPS_Y0, e.GPS_X1, e.GPS_Y1)
    check("FPC pocket does not overlap GPS keepout", fpc.disjoint(gps),
          f"FPC {fpc.bounds}  GPS {gps.bounds}")
    ipex = box(e.IPEX_X - e.IPEX_W / 2, e.IPEX_Y - e.IPEX_W / 2,
               e.IPEX_X + e.IPEX_W / 2, e.IPEX_Y + e.IPEX_W / 2)
    check("IPEX well does not overlap GPS keepout", ipex.disjoint(gps), f"IPEX {ipex.bounds}")

    # Cell bay vs standoffs: posts must not punch through the pouch
    log()
    log("Cell bay vs standoffs")
    from shapely.geometry import Point, box
    cell = box(e.BATT_X0, e.BATT_Y0, e.BATT_X1, e.BATT_Y1)
    for name, (x, y) in e.MH.items():
        # post footprint
        post = Point(x, y).buffer(e.STANDOFF_OD / 2)
        hits = post.intersects(cell)
        d = Point(x, y).distance(cell)
        check(f"{name} post outside cell footprint", not hits,
              f"center ({x:.2f},{y:.2f}) dist to cell={d:.2f} mm (need > {e.STANDOFF_OD/2:.2f})")
    # FRONT shelf must end before the cell
    check("FRONT shelf ends before the cell", e.SHELF_Y1 <= e.BATT_Y0 + 0.05,
          f"shelf Y1={e.SHELF_Y1:.2f} cell Y0={e.BATT_Y0:.2f}")
    # USB opening mid-height is the stacked board mid-plane, much higher than v8
    check("USB center is at the stacked board mid-plane", abs(e.USB_ZC - 14.40) < 0.05, f"USB_ZC={e.USB_ZC:.2f}")
    check("USB opening sits below the seal lip", (e.USB_ZC + e.USB_OUT_H / 2) <= e.LIP_Z0 + 0.05,
          f"USB top={e.USB_ZC + e.USB_OUT_H/2:.2f} lip={e.LIP_Z0:.2f}")
    check("box height in 24-28 mm planning band", 24.0 <= e.LID_TOP_Z <= 28.0, f"{e.LID_TOP_Z:.2f}")

    # typography
    log()
    log("Typography")

    check("DriveTrack cap height target 7.00 mm (Inter Tight)", abs(e.DT_CAP - 7.00) < 1e-6)
    check("lid typography relief present (zmax > roof)", lhi[2] > e.LID_TOP_Z + 0.20, f"zmax={lhi[2]:.2f}")

    log()
    log("RESULT: " + ("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED"))
    out = os.path.join(HERE, "verify-v9.log")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    log(f"wrote {out}")
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        traceback.print_exc()
        sys.exit(2)
