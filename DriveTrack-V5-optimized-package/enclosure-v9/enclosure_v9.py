#!/usr/bin/env python3
"""DriveTrack enclosure v9 — stacked roof box for PCB V5 stacked.

Built around the V5 52 x 70 mm board with the 104060 cell UNDER the
PCB. ASA prototype. Inspection model, not a production release.
See notes-v9.md.
"""
from __future__ import annotations

import math
import os
import sys

import cadquery as cq

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_PATH = os.path.join(HERE, "fonts", "InterTight-700.ttf")

# ---------------------------------------------------------------------------
# Locked to PCB V5 (board origin = north-west / LED / FRONT corner, Y toward USB)
# ---------------------------------------------------------------------------
BOARD_W, BOARD_H, BOARD_T = 52.00, 70.00, 1.60
CLR = 0.60
CELL_W, CELL_L, CELL_T = 40.00, 60.00, 10.00
CELL_FOAM = 0.80        # wrap around the pouch where space allows
INSULATOR = 0.40        # film / foam between cell top and PCB bottom

WALL = 2.50
WALL_USB = 3.00
PLAN_R = 6.00
FLANGE = 8.00
FLANGE_T = 2.20
FLANGE_R = 10.00

# Origins (board origin = FRONT / LED / -Y corner, Y toward USB)
PCB_X0 = WALL + CLR                 # 3.10
PCB_Y0 = WALL + CLR                 # 3.10
PCB_X1 = PCB_X0 + BOARD_W           # 55.10
PCB_Y1 = PCB_Y0 + BOARD_H           # 73.10  (USB wall inner face)

# Cell under the board: board X=0..40, Y=2..62
BATT_X0 = PCB_X0 + 0.00             # 3.10
BATT_X1 = PCB_X0 + 40.00            # 43.10
BATT_Y0 = PCB_Y0 + 2.00             # 5.10
BATT_Y1 = PCB_Y0 + 62.00            # 65.10

CAV_X0, CAV_Y0 = WALL, WALL         # 2.50, 2.50
CAV_X1 = PCB_X1 + CLR               # 55.70
CAV_Y1 = PCB_Y1                     # 73.10

BODY_X0, BODY_Y0 = 0.00, 0.00
BODY_X1 = CAV_X1 + WALL             # 58.20
BODY_Y1 = CAV_Y1 + WALL_USB         # 76.10

FLANGE_X0, FLANGE_Y0 = BODY_X0 - FLANGE, BODY_Y0 - FLANGE
FLANGE_X1, FLANGE_Y1 = BODY_X1 + FLANGE, BODY_Y1 + FLANGE

# Height stack-up (see notes-v9.md). JST-PH ~8 mm above the board is the
# tallest top-side part and sets the ceiling, not the 4 mm GPS patch.
FLOOR_Z = 2.20
FOAM_Z = 1.00
PCB_Z0 = FLOOR_Z + FOAM_Z + CELL_T + INSULATOR   # 13.60
PCB_Z1 = PCB_Z0 + BOARD_T                         # 15.20
SPLIT_Z = 20.00
LIP_Z0 = 18.20            # just above the USB opening top (17.80)
LID_TOP_Z = 26.50
LID_CEILING_Z = 24.50     # 2.00 mm roof, including over the GPS patch
CELL_Z0 = FLOOR_Z + FOAM_Z                       # 3.20
CELL_Z1 = CELL_Z0 + CELL_T                       # 13.20

# Mounting holes (board) -> enclosure. All four sit outside the cell.
MH = {
    "MH1": (PCB_X0 + 46.40, PCB_Y0 + 3.50),   # 49.50, 6.60  leftover FRONT
    "MH2": (PCB_X0 + 46.40, PCB_Y0 + 66.50),  # 49.50, 69.60 leftover USB
    "MH3": (PCB_X0 + 3.20,  PCB_Y0 + 66.50),  #  6.30, 69.60 USB-end -X
    "MH4": (PCB_X0 + 36.40, PCB_Y0 + 66.50),  # 39.50, 69.60 USB-end east of notch
}
STANDOFF_OD, STANDOFF_ID = 5.20, 1.70   # M2 thread-forming pilot, blind
STANDOFF_Z0 = 1.00                      # floor remains closed below

# USB (board origin 26.00, 64.77; shell flush with y=70)
USB_XC = PCB_X0 + 26.00                 # 29.10
USB_Y_INNER = PCB_Y1                    # 73.10
USB_ZC = (PCB_Z0 + PCB_Z1) / 2          # 14.40  mid-plane of the 1.6 mm board
USB_OUT_W, USB_OUT_H = 12.40, 6.80
USB_SEAL_W, USB_SEAL_H, USB_SEAL_D = 16.00, 9.20, 1.20

# Vent at U4 (4.40, 50.00) on the -X wall
VENT_YC = PCB_Y0 + 50.00                # 53.10
VENT_ZC = 16.20            # near the board, below the seal lip
VENT_ID, VENT_MEMB, VENT_MEMB_T = 3.00, 10.00, 0.80

# LED window in the lid, over DS1..DS5 (y=3.20, x=9.00..25.80)
LED_X0 = PCB_X0 + 9.00 - 2.20           # 9.90
LED_X1 = PCB_X0 + 25.80 + 2.20          # 31.10
LED_Y0 = PCB_Y0 + 3.20 - 2.00           # 4.30
LED_Y1 = PCB_Y0 + 3.20 + 2.00           # 8.30
LED_MEMB_T = 0.80

# GPS patch (16.80, 19.40), 25 x 25 — keep the lid over it clear
GPS_X0 = PCB_X0 + 16.80 - 13.00         # 6.90
GPS_X1 = PCB_X0 + 16.80 + 13.00         # 32.90
GPS_Y0 = PCB_Y0 + 19.40 - 13.00         # 9.50
GPS_Y1 = PCB_Y0 + 19.40 + 13.00         # 35.50

# 2.4G FPC pocket on the lid underside (34 x 12 + margin).
# 12 mm in X (east of the GPS keepout) and 34 mm in Y, south of the
# ESP32 IPEX, not over the ceramic patch.
FPC_W, FPC_H, FPC_MARGIN, FPC_D = 12.00, 34.00, 1.20, 1.40
FPC_X0 = GPS_X1 + 1.00                  # 33.90
FPC_X1 = FPC_X0 + FPC_W + 2 * FPC_MARGIN  # 48.30
FPC_Y0 = PCB_Y0 + 28.00                 # 31.10  south of the WROOM-1U body
FPC_Y1 = FPC_Y0 + FPC_H + 2 * FPC_MARGIN  # 67.50

# IPEX / cable well near U1 (40.60, 16.50), IPEX toward +Y
IPEX_X, IPEX_Y = PCB_X0 + 40.60, PCB_Y0 + 16.50 + 8.00  # 43.70, 27.60
IPEX_W, IPEX_D = 8.00, 1.80

SCREW_INSET = 4.50
SCREW = [
    (FLANGE_X0 + SCREW_INSET, FLANGE_Y0 + SCREW_INSET),
    (FLANGE_X1 - SCREW_INSET, FLANGE_Y0 + SCREW_INSET),
    (FLANGE_X0 + SCREW_INSET, FLANGE_Y1 - SCREW_INSET),
    (FLANGE_X1 - SCREW_INSET, FLANGE_Y1 - SCREW_INSET),
]
SCREW_CB_D, SCREW_THRU_D, SCREW_BOSS_D = 6.00, 3.20, 7.50   # M3 lid screws

GROOVE_W, GROOVE_H = 2.60, 1.50
GASKET_CL_OUTSET = 2.80
TONGUE_W, TONGUE_H = 1.60, 1.20

# Damping: 1 mm foam under the cell, plus small pads on the leftover
# floor / FRONT shelf (see notes). Board rests on insulator over the cell
# and on the FRONT shelf + four standoffs.
# FRONT board shelf (under board Y=0..1.80, cell starts at Y=2.00)
SHELF_Y1 = PCB_Y0 + 1.80                # 4.90
# Leftover foam-pad pockets, in the leftover strip, at floor level
BOARD_PAD = [
    (PCB_X0 + 46.40, PCB_Y0 + 16.00),
    (PCB_X0 + 46.40, PCB_Y0 + 36.00),
    (PCB_X0 + 46.40, PCB_Y0 + 52.00),
]
PAD_S, PAD_D = 8.00, 1.50

# JST cable well: leftover at the USB-end of the cell, so the pigtail
# can come up beside the pouch and plug into J3 from the west.
CABLE_X0 = BATT_X1                      # 43.10
CABLE_X1 = PCB_X1                       # 55.10
CABLE_Y0 = BATT_Y1 - 8.00               # 57.10
CABLE_Y1 = BATT_Y1 + 2.00               # 67.10

DT_CAP = 7.00


def _all_solids(s):
    if isinstance(s, cq.Workplane):
        try:
            sols = s.solids().vals()
            if sols:
                return sols
        except Exception:
            pass
        vals = s.vals()
        out = []
        for v in vals:
            out.extend(_all_solids(v))
        return out
    if isinstance(s, cq.Solid):
        return [s]
    if hasattr(s, "Solids"):
        sols = list(s.Solids())
        if sols:
            return sols
    return [s]


def as_solid(s):
    sols = _all_solids(s)
    if not sols:
        raise ValueError("no solids")
    acc = sols[0]
    for q in sols[1:]:
        try:
            acc = acc.fuse(q)
        except Exception:
            acc = cq.Compound.makeCompound([acc, q])
    return acc


def rounded_prism(x0, y0, z0, x1, y1, z1, r):
    r = min(r, (x1 - x0) / 2 - 0.05, (y1 - y0) / 2 - 0.05)
    wp = (
        cq.Workplane("XY")
        .workplane(offset=z0)
        .center(0.5 * (x0 + x1), 0.5 * (y0 + y1))
        .rect(x1 - x0, y1 - y0)
        .extrude(z1 - z0)
    )
    if r > 0.05:
        wp = wp.edges("|Z").fillet(r)
    return as_solid(wp)


def box(x0, y0, z0, x1, y1, z1):
    return as_solid(
        cq.Workplane("XY")
        .workplane(offset=z0)
        .center(0.5 * (x0 + x1), 0.5 * (y0 + y1))
        .rect(x1 - x0, y1 - y0)
        .extrude(z1 - z0)
    )


def cyl_z(x, y, z0, z1, d):
    return as_solid(
        cq.Workplane("XY").workplane(offset=z0).center(x, y).circle(d / 2).extrude(z1 - z0)
    )


def cyl_along_y(x, z, y0, y1, d):
    h = y1 - y0
    if h < 0:
        y0, y1, h = y1, y0, -h
    return as_solid(cq.Solid.makeCylinder(d / 2, h, cq.Vector(x, y0, z), cq.Vector(0, 1, 0)))


def pill_along_y(xc, zc, width, height, y0, y1):
    """Horizontal capsule in the XZ plane, extruded along +Y (USB wall openings)."""
    r = min(width, height) / 2 - 0.01
    slab = box(xc - width / 2 + r, y0, zc - height / 2, xc + width / 2 - r, y1, zc + height / 2)
    c1 = cyl_along_y(xc - width / 2 + r, zc, y0, y1, height)
    c2 = cyl_along_y(xc + width / 2 - r, zc, y0, y1, height)
    return as_solid(as_solid(slab.fuse(c1)).fuse(c2))


def log(label, obj):
    s = as_solid(obj)
    bb = s.BoundingBox()
    print(
        f"  [{label}] vol={s.Volume():.1f}  "
        f"bbox=[{bb.xmin:.2f},{bb.ymin:.2f},{bb.zmin:.2f}].."
        f"[{bb.xmax:.2f},{bb.ymax:.2f},{bb.zmax:.2f}]"
    )
    return s


def _rounded_rect_poly(x0, y0, x1, y1, r, res=24):
    from shapely.geometry import box
    r = min(r, (x1 - x0) / 2 - 0.05, (y1 - y0) / 2 - 0.05)
    return box(x0 + r, y0 + r, x1 - r, y1 - r).buffer(r, resolution=res, join_style=1)


def _poly_to_solid(poly, z0, z1):
    """Extrude a shapely polygon (with holes) to a CadQuery solid."""
    if poly.is_empty:
        raise ValueError("empty polygon")
    geoms = list(poly.geoms) if poly.geom_type == "MultiPolygon" else [poly]
    acc = None
    for g in geoms:
        outer = as_solid(
            cq.Workplane("XY")
            .workplane(offset=z0)
            .polyline(list(g.exterior.coords)[:-1])
            .close()
            .extrude(z1 - z0)
        )
        for hole in g.interiors:
            h = as_solid(
                cq.Workplane("XY")
                .workplane(offset=z0 - 0.5)
                .polyline(list(hole.coords)[:-1])
                .close()
                .extrude(z1 - z0 + 1.0)
            )
            outer = as_solid(outer.cut(h))
        acc = outer if acc is None else as_solid(acc.fuse(outer))
    return acc


def gasket_ring(width, z0, z1, extra=0.0):
    """Ring in the flange, offset outside the body wall, around the whole cavity.

    The centerline follows the body outer wall at GASKET_CL_OUTSET. Corner
    lid-screw columns stay outboard of this loop (verified in verify_v8.py).
    """
    body = _rounded_rect_poly(BODY_X0, BODY_Y0, BODY_X1, BODY_Y1, PLAN_R)
    half = width / 2 + extra
    ring = body.buffer(GASKET_CL_OUTSET + half, resolution=24, join_style=1).difference(
        body.buffer(GASKET_CL_OUTSET - half, resolution=24, join_style=1)
    )
    return _poly_to_solid(ring, z0, z1)


def add_text(solid, text, cx, cy, z0, height, thick, font=FONT_PATH):
    """Emboss text on the lid top, +Z, cap-ish height in mm.

    The glyph solid is sunk 0.25 mm into the lid so the boolean has a
    clear overlap; the remainder stands proud of the roof.
    """
    if not os.path.isfile(font):
        print(f"  WARN: font missing ({font}), skip '{text}'")
        return as_solid(solid)
    try:
        txt = (
            cq.Workplane("XY")
            .workplane(offset=z0)
            .center(cx, cy)
            .text(
                txt=text,
                fontsize=height,
                distance=thick,
                font="Inter Tight",
                fontPath=font,
                halign="center",
                valign="center",
            )
        )
        fused = cq.Workplane("XY").newObject([as_solid(solid)]).union(txt)
        out = as_solid(fused)
        print(f"    embossed '{text}' vol={out.Volume():.1f}")
        return out
    except Exception as exc:
        print(f"  typography skip '{text}': {type(exc).__name__}: {exc}")
        return as_solid(solid)


def build_base():
    print("v9 base: body + flange")
    body = rounded_prism(BODY_X0, BODY_Y0, 0, BODY_X1, BODY_Y1, SPLIT_Z, PLAN_R)
    flange = rounded_prism(FLANGE_X0, FLANGE_Y0, 0, FLANGE_X1, FLANGE_Y1, FLANGE_T, FLANGE_R)
    base = as_solid(body.fuse(flange))
    log("body+flange", base)

    print("v9 base: cavity")
    cav = rounded_prism(CAV_X0, CAV_Y0, FLOOR_Z, CAV_X1, CAV_Y1, SPLIT_Z + 0.20, PLAN_R - 1.50)
    base = as_solid(base.cut(cav))
    log("cavity", base)

    print("v9 base: PCB standoffs (blind from below)")
    for name, (x, y) in MH.items():
        boss = cyl_z(x, y, FLOOR_Z - 0.05, PCB_Z0, STANDOFF_OD)
        base = as_solid(base.fuse(boss))
        pilot = cyl_z(x, y, STANDOFF_Z0, PCB_Z0 + 0.20, STANDOFF_ID)
        base = as_solid(base.cut(pilot))
    log("standoffs", base)

    print("v9 base: stacked cell bay + foam pocket (under the PCB)")
    # Low rails around the pouch, kept clear of the standoffs and of the
    # leftover cable well at the USB-end / leftover corner.
    rail_t, rail_h = 1.20, 2.20
    # FRONT rail (between the FRONT shelf and the cell)
    rail_n = box(BATT_X0 - 0.20, BATT_Y0 - rail_t, FLOOR_Z, BATT_X1 + 0.20, BATT_Y0, FLOOR_Z + rail_h)
    # Leftover-side rail, stopped before the cable well
    rail_e = box(BATT_X1, BATT_Y0, FLOOR_Z, BATT_X1 + rail_t, CABLE_Y0, FLOOR_Z + rail_h)
    base = as_solid(base.fuse(rail_n).fuse(rail_e))
    cell_pocket = box(
        BATT_X0 + 1.0, BATT_Y0 + 1.0, FLOOR_Z - 0.05,
        BATT_X1 - 1.0, BATT_Y1 - 1.0, FLOOR_Z + FOAM_Z,
    )
    base = as_solid(base.cut(cell_pocket))

    print("v9 base: FRONT board shelf (no screw at the GPS corner)")
    # A 1.8 mm deep shelf under the FRONT edge of the board, ending
    # before the cell starts at board Y=2.00.
    shelf = box(PCB_X0, PCB_Y0, FLOOR_Z, PCB_X1, SHELF_Y1, PCB_Z0)
    base = as_solid(base.fuse(shelf))

    print("v9 base: leftover-strip damping pockets")
    for x, y in BOARD_PAD:
        pad = box(x - PAD_S / 2, y - PAD_S / 2, FLOOR_Z - 0.05,
                  x + PAD_S / 2, y + PAD_S / 2, FLOOR_Z + PAD_D)
        base = as_solid(base.cut(pad))
    log("pockets", base)

    print("v9 base: split-face seal lip (flange band, holds the gasket)")
    lip_outer = rounded_prism(FLANGE_X0, FLANGE_Y0, LIP_Z0, FLANGE_X1, FLANGE_Y1, SPLIT_Z, FLANGE_R)
    lip_inner = rounded_prism(BODY_X0 - 0.05, BODY_Y0 - 0.05, LIP_Z0 - 0.20, BODY_X1 + 0.05, BODY_Y1 + 0.05, SPLIT_Z + 0.20, PLAN_R)
    lip = as_solid(lip_outer.cut(lip_inner))
    base = as_solid(base.fuse(lip))
    log("lip", base)

    print("v9 base: gasket groove in the seal lip, outside the body wall")
    groove = gasket_ring(GROOVE_W, SPLIT_Z - GROOVE_H, SPLIT_Z + 0.20)
    v0 = base.Volume() if hasattr(base, "Volume") else as_solid(base).Volume()
    base = as_solid(base.cut(groove))
    v1 = as_solid(base).Volume()
    print(f"    groove cut delta={v0-v1:.1f} mm^3 (expect ~{GROOVE_W * 1:.0f} * path * depth)")
    if v0 - v1 < 200:
        raise RuntimeError(f"gasket groove cut too small or missed the lip ({v0:.1f} -> {v1:.1f})")
    log("groove", base)

    print("v9 base: lid-screw columns and through paths in the flange (outside gasket)")
    for x, y in SCREW:
        boss = cyl_z(x, y, 0, SPLIT_Z, SCREW_BOSS_D)
        base = as_solid(base.fuse(boss))
        # through hole from the bottom, socket head counterbore, no opening into the cavity
        thru = cyl_z(x, y, -0.20, SPLIT_Z + 0.20, SCREW_THRU_D)
        cbore = cyl_z(x, y, -0.20, 3.20, SCREW_CB_D)
        base = as_solid(base.cut(thru).cut(cbore))
    log("screws", base)

    print("v9 base: USB opening + seal recess (through the +Y wall)")
    usb = pill_along_y(
        USB_XC, USB_ZC, USB_OUT_W, USB_OUT_H,
        USB_Y_INNER - 0.20, BODY_Y1 + 0.40,
    )
    v0 = as_solid(base).Volume()
    base = as_solid(base.cut(usb))
    seal = pill_along_y(
        USB_XC, USB_ZC, USB_SEAL_W, USB_SEAL_H,
        BODY_Y1 - USB_SEAL_D, BODY_Y1 + 0.20,
    )
    base = as_solid(base.cut(seal))
    v1 = as_solid(base).Volume()
    print(f"    USB cut delta={v0-v1:.1f} mm^3")
    if v0 - v1 < 80:
        raise RuntimeError(f"USB opening cut too small ({v0:.1f} -> {v1:.1f})")
    log("usb", base)

    print("v9 base: vent hole + membrane recess on the west wall")
    vent = as_solid(
        cq.Workplane("YZ")
        .workplane(offset=BODY_X0 - 0.40)
        .center(VENT_YC, VENT_ZC)
        .circle(VENT_ID / 2)
        .extrude(WALL + 1.00)
    )
    base = as_solid(base.cut(vent))
    memb = as_solid(
        cq.Workplane("YZ")
        .workplane(offset=BODY_X0 - 0.10)
        .center(VENT_YC, VENT_ZC)
        .circle(VENT_MEMB / 2)
        .extrude(VENT_MEMB_T)
    )
    base = as_solid(base.cut(memb))
    log("vent", base)

    return as_solid(base)


def build_lid():
    print("v9 lid: shell")
    # Lid sits on the split, full body + flange outline, roof at LID_TOP_Z
    outer = rounded_prism(FLANGE_X0, FLANGE_Y0, SPLIT_Z, FLANGE_X1, FLANGE_Y1, LID_TOP_Z, FLANGE_R)
    # Hollow the interior down to the ceiling, following the cavity
    hollow = rounded_prism(
        CAV_X0, CAV_Y0, SPLIT_Z - 0.20, CAV_X1, CAV_Y1, LID_CEILING_Z, PLAN_R - 1.50
    )
    lid = as_solid(outer.cut(hollow))
    log("lid shell", lid)

    print("v9 lid: gasket tongue (mates the base groove)")
    tongue = gasket_ring(TONGUE_W, SPLIT_Z - TONGUE_H, SPLIT_Z + 0.05)
    lid = as_solid(lid.fuse(tongue))
    log("tongue", lid)

    print("v9 lid: screw bosses in the flange (outside gasket, no path into the cavity)")
    for x, y in SCREW:
        boss = cyl_z(x, y, SPLIT_Z, LID_TOP_Z, SCREW_BOSS_D)
        lid = as_solid(lid.fuse(boss))
        # Short blind pilot in the lid so an M3 screw from the base engages the lid
        # without piercing the lid top.
        pilot = cyl_z(x, y, SPLIT_Z - 0.20, LID_TOP_Z - 1.20, 2.50)
        lid = as_solid(lid.cut(pilot))
    log("lid screws", lid)

    print("v9 lid: 0.80 mm LED membrane window (not a through-hole)")
    # Recess from the outside, leaving LED_MEMB_T of material
    recess_z0 = LID_CEILING_Z + LED_MEMB_T
    win = box(LED_X0, LED_Y0, recess_z0, LED_X1, LED_Y1, LID_TOP_Z + 0.20)
    lid = as_solid(lid.cut(win))
    log("led window", lid)

    print("v9 lid: FPC pocket + IPEX well (not over the GPS patch)")
    fpc = box(FPC_X0, FPC_Y0, LID_CEILING_Z - FPC_D, FPC_X1, FPC_Y1, LID_CEILING_Z + 0.10)
    lid = as_solid(lid.cut(fpc))
    well = box(
        IPEX_X - IPEX_W / 2, IPEX_Y - IPEX_W / 2, LID_CEILING_Z - IPEX_D,
        IPEX_X + IPEX_W / 2, IPEX_Y + IPEX_W / 2, LID_CEILING_Z + 0.10,
    )
    lid = as_solid(lid.cut(well))
    log("antenna pockets", lid)

    print("v9 lid: typography is applied later as a mesh union (OpenCASCADE + Inter Tight is unreliable)")
    return as_solid(lid)


CAP_PER_EM = 1490.0 / 2048.0  # measured for Inter Tight
DT_TRACKING = 0.20
FRONT_CAP = 2.50
FRONT_TRACKING = 0.25
LID_RELIEF = 0.45


def _letter_polygons(ch, fontsize, font_path):
    """Return valid shapely polygons (holes included) for one glyph."""
    from matplotlib.textpath import TextPath
    from matplotlib.font_manager import FontProperties
    from shapely.geometry import Polygon

    fp = FontProperties(fname=font_path, size=1.0)
    path = TextPath((0.0, 0.0), ch, size=fontsize, prop=fp)
    raw = []
    for ring in path.to_polygons():
        if len(ring) < 4:
            continue
        poly = Polygon(ring)
        if not poly.is_valid:
            poly = poly.buffer(0)
        if poly.is_empty or poly.area < 1e-4:
            continue
        if poly.geom_type == "MultiPolygon":
            raw.extend([g for g in poly.geoms if g.area > 1e-4])
        else:
            raw.append(poly)
    raw.sort(key=lambda p: p.area, reverse=True)
    used = set()
    out = []
    for i, outer in enumerate(raw):
        if i in used:
            continue
        holes = []
        for j, inner in enumerate(raw):
            if j <= i or j in used:
                continue
            if outer.contains(inner):
                holes.append(list(inner.exterior.coords))
                used.add(j)
        poly = Polygon(list(outer.exterior.coords), holes)
        if not poly.is_valid:
            poly = poly.buffer(0)
        if not poly.is_empty:
            out.append(poly)
        used.add(i)
    return out


def _word_mesh(text, cap_h, thick, tracking):
    import numpy as np
    import trimesh
    from fontTools.ttLib import TTFont

    font = TTFont(FONT_PATH)
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()
    upem = font["head"].unitsPerEm
    fontsize = cap_h / CAP_PER_EM
    scale = fontsize / upem
    meshes = []
    cursor = 0.0
    for i, ch in enumerate(text):
        polys = _letter_polygons(ch, fontsize, FONT_PATH)
        if not polys:
            raise RuntimeError(f"no outline for {ch!r}")
        parts = [trimesh.creation.extrude_polygon(poly, thick) for poly in polys]
        letter = parts[0] if len(parts) == 1 else trimesh.boolean.union(parts, engine="manifold")
        letter.apply_translation((cursor, 0.0, 0.0))
        meshes.append(letter)
        adv = glyphs[cmap[ord(ch)]].width * scale
        cursor += adv + (tracking if i < len(text) - 1 else 0.0)
    word = trimesh.util.concatenate(meshes)
    b = word.bounds
    cx, cy = 0.5 * (b[0, 0] + b[1, 0]), 0.5 * (b[0, 1] + b[1, 1])
    word.apply_translation((-cx, -cy, 0.0))
    # Mirror across X so letter tops point toward FRONT (-Y). A 180° Z
    # rotation would also swap left and right, which made "DriveTrack"
    # read backwards. The FRONT arrow is a separate mesh and already
    # points toward -Y, so it is not mirrored here.
    S = np.eye(4)
    S[1, 1] = -1.0
    word.apply_transform(S)
    return word, (b[1, 0] - b[0, 0]), (b[1, 1] - b[0, 1])


def typography_meshes():
    import trimesh
    from shapely.geometry import Polygon as SPoly

    if not os.path.isfile(FONT_PATH):
        raise FileNotFoundError(FONT_PATH)
    thick = LID_RELIEF + 0.25  # 0.25 mm sink into the roof, remainder proud
    z0 = LID_TOP_Z - 0.25
    cx = 0.5 * (BODY_X0 + BODY_X1)
    cy = 0.5 * (BODY_Y0 + BODY_Y1) + 4.00

    dt, dw, dh = _word_mesh("DriveTrack", DT_CAP, thick, DT_TRACKING)
    print(f"    DriveTrack size {dw:.2f} x {dh:.2f} mm (cap target {DT_CAP})")
    dt.apply_translation((cx, cy, z0))

    fr, fw, fh = _word_mesh("FRONT", FRONT_CAP, thick, FRONT_TRACKING)
    print(f"    FRONT size {fw:.2f} x {fh:.2f} mm (cap target {FRONT_CAP})")
    frx, fry = PCB_X0 + 40.00, PCB_Y0 + 13.20
    fr.apply_translation((frx, fry, z0))

    tip_y = PCB_Y0 + 5.20
    head_len, head_half = 2.20, 1.20
    shaft_len, shaft_half = 2.80, 0.32
    head_base = tip_y + head_len
    shaft_end = head_base + shaft_len
    arrow_poly = SPoly([
        (frx, tip_y),
        (frx + head_half, head_base),
        (frx + shaft_half, head_base),
        (frx + shaft_half, shaft_end),
        (frx - shaft_half, shaft_end),
        (frx - shaft_half, head_base),
        (frx - head_half, head_base),
    ])
    arrow = trimesh.creation.extrude_polygon(arrow_poly, thick)
    arrow.apply_translation((0.0, 0.0, z0))
    return [dt, fr, arrow]


def solid_to_trimesh(solid, tolerance=0.04, angular=0.12):
    import trimesh
    import tempfile

    fd, path = tempfile.mkstemp(suffix=".stl")
    os.close(fd)
    try:
        as_solid(solid).exportStl(path, tolerance=tolerance, angularTolerance=angular)
        m = trimesh.load(path, force="mesh")
    finally:
        try:
            os.remove(path)
        except OSError:
            pass
    if not isinstance(m, trimesh.Trimesh):
        m = trimesh.util.concatenate(tuple(m.geometry.values()))
    m.merge_vertices()
    m.process(validate=False)
    return m


def union_typography(lid_mesh, typo):
    import trimesh

    acc = lid_mesh
    for i, t in enumerate(typo):
        t.merge_vertices()
        try:
            acc = trimesh.boolean.union([acc, t], engine="manifold")
            print(f"    union typography[{i}] ok  vol={acc.volume:.1f} is_volume={acc.is_volume}")
        except Exception as exc:
            print(f"    union typography[{i}] failed ({exc}); concatenating instead")
            acc = trimesh.util.concatenate([acc, t])
    return acc


def export_mesh(mesh, path):
    mesh.export(path)
    print(f"  wrote {path}  ({os.path.getsize(path)} bytes)  vol={getattr(mesh, 'volume', float('nan')):.1f}  is_volume={getattr(mesh, 'is_volume', None)}")


def export_stl(obj, path):
    as_solid(obj).exportStl(path, tolerance=0.04, angularTolerance=0.2)
    print(f"  wrote {path}  ({os.path.getsize(path)} bytes)")


def main():
    print("DriveTrack enclosure v9")
    print(f"  outer body {BODY_X1-BODY_X0:.2f} x {BODY_Y1-BODY_Y0:.2f} x {LID_TOP_Z:.2f}")
    print(f"  with flange {FLANGE_X1-FLANGE_X0:.2f} x {FLANGE_Y1-FLANGE_Y0:.2f}")
    print(f"  cavity {CAV_X1-CAV_X0:.2f} x {CAV_Y1-CAV_Y0:.2f}")
    print(f"  PCB origin ({PCB_X0:.2f}, {PCB_Y0:.2f})  USB ({USB_XC:.2f}, wall Y={USB_Y_INNER:.2f})")
    if not os.path.isfile(FONT_PATH):
        sys.exit(f"missing typography font: {FONT_PATH}")

    base = build_base()
    lid = build_lid()

    print("v9 typography: mesh union with Inter Tight")
    typo = typography_meshes()
    lid_mesh = union_typography(solid_to_trimesh(lid), typo)
    base_mesh = solid_to_trimesh(base)
    assembled = trimesh_concat(base_mesh, lid_mesh)

    export_mesh(base_mesh, os.path.join(HERE, "base-v9.stl"))
    export_mesh(lid_mesh, os.path.join(HERE, "lid-v9.stl"))
    export_mesh(assembled, os.path.join(HERE, "assembled-v9-DO-NOT-PRINT.stl"))
    print("done")


def trimesh_concat(a, b):
    import trimesh
    return trimesh.util.concatenate([a, b])


if __name__ == "__main__":
    main()
