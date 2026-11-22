#!/usr/bin/env python3
"""DriveTrack enclosure v10 — compact sealed box for PCB V6 (62 x 62 mm).

Process: MJF PA12, black dyed (base + lid).  The light pipe must stay a
transparent part (PETG / PC / PMMA) because MJF cannot be clear.

Changes vs v9:
  * board 62 x 62 (was 52 x 70), cell 103450 34 x 50 (was 104060 40 x 60)
  * NO user button: no side holes. USB insert + motion wake, APP/5 min idle off
  * NO external flange: four M2 screws inside the gasket, flush on the lid
  * single RGB LED window instead of a 5-LED strip
  * internal screws also clamp the PCB (no separate PCB standoffs)
  * vent moved to the west wall, aligned with BMP390

Coordinate system: X east, Y south (USB wall), Z up.
Board origin = north-west corner of the PCB; board sits at (3.3, 3.3, 13.2).

Run with Python 3.12 + cadquery 2.8:
    /root/.pyenv/versions/3.12.15/bin/python enclosure_v10.py
"""
from __future__ import annotations

import math
import os

import cadquery as cq

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Locked to PCB V6 (62 x 62). See layout-plan.md / placement.csv.
# ---------------------------------------------------------------------------
BOARD_W = BOARD_H = 62.00
BOARD_T = 1.60

CLR = 0.50              # board-to-wall clearance
WALL = 2.80
BODY = BOARD_W + 2 * (WALL + CLR)      # 68.60
PLAN_R = 6.00

FLOOR = 2.00
CELL_W, CELL_L, CELL_T = 34.00, 50.00, 10.00
FOAM = 0.80
INSULATOR = 0.30

PCB_X0 = PCB_Y0 = WALL + CLR            # 3.30
PCB_X1 = PCB_Y1 = PCB_X0 + BOARD_W      # 65.30
CELL_X0, CELL_Y0 = PCB_X0 + 26.00, PCB_Y0 + 6.00    # 29.30, 9.30
CELL_X1, CELL_Y1 = CELL_X0 + CELL_W, CELL_Y0 + CELL_L

CELL_Z0 = FLOOR + FOAM                  # 2.80
CELL_Z1 = CELL_Z0 + CELL_T              # 12.80
PCB_Z0 = CELL_Z1 + INSULATOR            # 13.20
PCB_Z1 = PCB_Z0 + BOARD_T               # 14.80

SPLIT_Z = 19.40         # base rim / lid seat
TOP_Z = 21.00           # overall height (roof 1.60)
ROOF = TOP_Z - SPLIT_Z

# ---------------------------------------------------------------------------
# Board feature anchors (board coords -> enclosure coords)
# ---------------------------------------------------------------------------
def b(x: float, y: float) -> tuple[float, float]:
    return PCB_X0 + x, PCB_Y0 + y


# GNSS patch centre (13.5, 13.0), 25 x 25 -> lid radome
GPS_CX, GPS_CY = b(13.50, 13.00)
GPS_S = 25.00

# BMP390 (3.5, 45.0) -> west wall vent
BMP_X, BMP_Y = b(3.50, 45.00)
VENT_Z = 15.60

# RGB LED (56.0, 8.0) -> lid window + light pipe
LED_X, LED_Y = b(56.00, 8.00)

# ESP32 IPEX toward north edge -> FPC pocket in the lid
IPEX_X, IPEX_Y = b(46.00, 4.50)

# USB-C on the south edge, mid-mount => opening centred on the PCB mid-plane
USB_XC = b(31.00, 0)[0]
USB_ZC = 0.5 * (PCB_Z0 + PCB_Z1)        # 14.00
USB_OPEN_W, USB_OPEN_H = 10.50, 4.40
USB_RECESS_W, USB_RECESS_H, USB_RECESS_D = 14.00, 8.00, 0.90

# Four M2 screws: through lid + PCB into base bosses (all outside the cell)
MH = [
    b(30.00, 3.00),     # 33.30, 6.30
    b(54.00, 3.00),     # 57.30, 6.30
    b(21.50, 59.00),    # 24.80, 62.30  (moved west of the USB-C receptacle)
    b(54.00, 59.00),    # 57.30, 62.30
]
BOSS_D, PILOT_D, PILOT_DEPTH = 4.40, 1.60, 5.50
SCREW_THRU_D, SCREW_CB_D, SCREW_CB_DEPTH = 2.20, 4.40, 1.10

# Gasket groove in the base rim + matching tongue on the lid
GROOVE_W, GROOVE_D = 1.60, 1.20
GROOVE_OUT = 0.60                      # material left on the outside
TONGUE_W, TONGUE_D = 1.40, 1.20

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def rrect(x0, y0, z0, x1, y1, z1, r):
    wp = (
        cq.Workplane("XY")
        .workplane(offset=z0)
        .center(0.5 * (x0 + x1), 0.5 * (y0 + y1))
        .rect(x1 - x0, y1 - y0)
        .extrude(z1 - z0)
    )
    if r > 0.05:
        wp = wp.edges("|Z").fillet(r)
    return wp


def box(x0, y0, z0, x1, y1, z1):
    return (
        cq.Workplane("XY")
        .workplane(offset=z0)
        .center(0.5 * (x0 + x1), 0.5 * (y0 + y1))
        .rect(x1 - x0, y1 - y0)
        .extrude(z1 - z0)
    )


def cyl_z(x, y, z0, z1, d):
    return (
        cq.Workplane("XY")
        .workplane(offset=z0)
        .center(x, y)
        .circle(d / 2)
        .extrude(z1 - z0)
    )


def cyl_x(x0, x1, y, z, d):
    return (
        cq.Workplane("YZ")
        .workplane(offset=x0)
        .center(y, z)
        .circle(d / 2)
        .extrude(x1 - x0)
    )


def single(wp, what):
    n = len(wp.solids().vals())
    if n != 1:
        raise RuntimeError(f"{what}: expected 1 solid, got {n}")
    return wp


# ---------------------------------------------------------------------------
# Base
# ---------------------------------------------------------------------------
def build_base():
    outer = rrect(0, 0, 0, BODY, BODY, SPLIT_Z, PLAN_R)
    cav = rrect(WALL, WALL, FLOOR, BODY - WALL, BODY - WALL, SPLIT_Z + 0.20,
                PLAN_R - WALL)
    base = outer.cut(cav)

    # West-edge shelf under the sensor strip (board not over the cell there)
    shelf_x1 = PCB_X0 + 5.00
    base = base.union(box(PCB_X0, PCB_Y0, FLOOR, shelf_x1, PCB_Y1, PCB_Z0))

    # Four PCB/screw bosses, top exactly at the PCB underside
    for (x, y) in MH:
        base = base.union(cyl_z(x, y, FLOOR, PCB_Z0, BOSS_D))
        base = base.cut(cyl_z(x, y, PCB_Z0 - PILOT_DEPTH, PCB_Z0 + 0.10, PILOT_D))

    # Gasket groove (ring cut into the rim)
    go = rrect(GROOVE_OUT, GROOVE_OUT, SPLIT_Z - GROOVE_D,
               BODY - GROOVE_OUT, BODY - GROOVE_OUT, SPLIT_Z + 0.10,
               PLAN_R - GROOVE_OUT)
    gi = rrect(GROOVE_OUT + GROOVE_W, GROOVE_OUT + GROOVE_W,
               SPLIT_Z - GROOVE_D,
               BODY - GROOVE_OUT - GROOVE_W, BODY - GROOVE_OUT - GROOVE_W,
               SPLIT_Z + 0.10, PLAN_R - GROOVE_OUT - GROOVE_W)
    base = base.cut(go.cut(gi))

    # USB-C: shallow plug recess + through opening (mid-mount, below the split)
    base = base.cut(box(USB_XC - USB_RECESS_W / 2, BODY - USB_RECESS_D,
                        USB_ZC - USB_RECESS_H / 2,
                        USB_XC + USB_RECESS_W / 2, BODY + 0.50,
                        USB_ZC + USB_RECESS_H / 2))
    base = base.cut(box(USB_XC - USB_OPEN_W / 2, BODY - WALL - 1.00,
                        USB_ZC - USB_OPEN_H / 2,
                        USB_XC + USB_OPEN_W / 2, BODY + 0.50,
                        USB_ZC + USB_OPEN_H / 2))

    # Pressure vent on the west wall: 3 mm hole + 12 x 12 outer recess for the
    # adhesive Gore membrane.  Keeping the membrane outside leaves the inner
    # rim (0.6 mm land next to the gasket groove) intact.
    base = base.cut(cyl_x(-0.50, 3.00, BMP_Y, VENT_Z, 3.00))
    base = base.cut(box(-0.10, BMP_Y - 6.00, VENT_Z - 6.00,
                        0.55, BMP_Y + 6.00, VENT_Z + 6.00))

    return single(base.clean(), "base")


# ---------------------------------------------------------------------------
# Lid
# ---------------------------------------------------------------------------
def build_lid():
    lid = rrect(0, 0, SPLIT_Z, BODY, BODY, TOP_Z, PLAN_R)

    # Gasket tongue (slightly smaller than the groove)
    to = rrect(GROOVE_OUT + 0.10, GROOVE_OUT + 0.10, SPLIT_Z - TONGUE_D,
               BODY - GROOVE_OUT - 0.10, BODY - GROOVE_OUT - 0.10,
               SPLIT_Z + 0.15, PLAN_R - GROOVE_OUT - 0.10)
    ti = rrect(GROOVE_OUT + 0.10 + TONGUE_W, GROOVE_OUT + 0.10 + TONGUE_W,
               SPLIT_Z - TONGUE_D,
               BODY - GROOVE_OUT - 0.10 - TONGUE_W,
               BODY - GROOVE_OUT - 0.10 - TONGUE_W,
               SPLIT_Z + 0.15,
               PLAN_R - GROOVE_OUT - 0.10 - TONGUE_W)
    lid = lid.union(to.cut(ti))

    # Thinned radome area over the ceramic patch (1.2 mm roof instead of 1.6)
    lid = lid.cut(box(GPS_CX - GPS_S / 2 - 0.40, GPS_CY - GPS_S / 2 - 0.40,
                      SPLIT_Z - 0.05,
                      GPS_CX + GPS_S / 2 + 0.40, GPS_CY + GPS_S / 2 + 0.40,
                      SPLIT_Z + 0.40))

    # 2.4 GHz FPC pocket in the lid underside, above / around the IPEX
    # 0.6 mm deep -> 1.0 mm of roof left, enough for a drop without support
    lid = lid.cut(box(IPEX_X - 7.00, 4.00, SPLIT_Z - 0.05,
                      IPEX_X + 6.00, 38.00, SPLIT_Z + 0.60))

    # RGB LED window: through hole + flange recess for the printed lens
    lid = lid.cut(box(LED_X - 3.00, LED_Y - 3.00, SPLIT_Z - 0.10,
                      LED_X + 3.00, LED_Y + 3.00, TOP_Z + 0.10))
    lid = lid.cut(box(LED_X - 3.80, LED_Y - 3.80, TOP_Z - 1.20,
                      LED_X + 3.80, LED_Y + 3.80, TOP_Z + 0.10))

    # Four M2 through holes + flush counterbores
    for (x, y) in MH:
        lid = lid.cut(cyl_z(x, y, SPLIT_Z - 1.50, TOP_Z + 0.10, SCREW_THRU_D))
        lid = lid.cut(cyl_z(x, y, TOP_Z - SCREW_CB_DEPTH, TOP_Z + 0.10,
                            SCREW_CB_D))

    return single(lid.clean(), "lid")


# ---------------------------------------------------------------------------
# Light pipe lens (print in clear PETG)
# ---------------------------------------------------------------------------
def build_lens():
    flange = box(LED_X - 3.70, LED_Y - 3.70, TOP_Z - 1.15,
                 LED_X + 3.70, LED_Y + 3.70, TOP_Z)
    stem = box(LED_X - 2.40, LED_Y - 2.40, 16.20,
               LED_X + 2.40, LED_Y + 2.40, TOP_Z - 1.00)
    return single(flange.union(stem).clean(), "lens")


# ---------------------------------------------------------------------------
def check(name, solid, pt, expect_inside):
    inside = bool(solid.isInside(cq.Vector(*pt), 1e-6))
    if inside != expect_inside:
        raise RuntimeError(
            f"{name}: point {pt} inside={inside}, expected {expect_inside}")


def verify(base, lid, lens):
    bb = base.val().BoundingBox()
    if abs(bb.xlen - BODY) > 0.05 or abs(bb.ylen - BODY) > 0.05:
        raise RuntimeError(f"base footprint {bb.xlen:.2f} x {bb.ylen:.2f}")
    if abs(bb.zlen - SPLIT_Z) > 0.05:
        raise RuntimeError(f"base height {bb.zlen:.2f}")

    lb = lid.val().BoundingBox()
    if abs(lb.zmax - TOP_Z) > 0.05:
        raise RuntimeError(f"lid top {lb.zmax:.2f}")

    # open / closed probes
    check("usb", base.val(), (USB_XC, BODY - 0.20, USB_ZC), False)
    check("vent", base.val(), (0.20, BMP_Y, VENT_Z), False)
    check("wall", base.val(), (1.00, 34.00, 10.00), True)
    check("cavity", base.val(), (34.00, 34.00, 10.00), False)
    check("ledge", base.val(), (5.00, 34.00, 12.00), True)
    check("led", lid.val(), (LED_X, LED_Y, 20.00), False)
    check("roof", lid.val(), (10.00, 34.00, 20.20), True)
    check("groove", base.val(), (GROOVE_OUT + 0.80, 34.00, 18.80), False)

    for nm, s in (("base", base), ("lid", lid), ("lens", lens)):
        if not s.val().isValid():
            raise RuntimeError(f"{nm} is not a valid solid")
        print(f"{nm:5s} volume {s.val().Volume() / 1000:.2f} cm^3  "
              f"bbox {s.val().BoundingBox().xlen:.2f} x "
              f"{s.val().BoundingBox().ylen:.2f} x "
              f"{s.val().BoundingBox().zlen:.2f}")


def main():
    base = build_base()
    lid = build_lid()
    lens = build_lens()
    verify(base, lid, lens)

    out = {
        "base-v10.stl": base,
        "lid-v10.stl": lid,
        "lens-v10.stl": lens,
        "assembled-v10-DO-NOT-PRINT.stl": base.union(lid).union(lens),
    }
    for fn, wp in out.items():
        path = os.path.join(HERE, fn)
        cq.exporters.export(wp, path, tolerance=0.02, angularTolerance=0.15)
        cq.exporters.export(wp, os.path.splitext(path)[0] + ".step")
        print("wrote", fn)

    print(f"\nBody {BODY:.1f} x {BODY:.1f} x {TOP_Z:.1f} mm")
    print(f"Cell {CELL_W} x {CELL_L} x {CELL_T} at "
          f"X {CELL_X0:.1f}-{CELL_X1:.1f}, Y {CELL_Y0:.1f}-{CELL_Y1:.1f}")


if __name__ == "__main__":
    main()
