#!/usr/bin/env python3
"""Build DriveTrack V6 PCB rev 6.1 with real footprints and full netlist.

Input : drivetrack-pcb-v6.kicad_pcb  (rev 6.0, mechanical reference board)
        mods/*.kicad_mod             (official / downloaded footprints)
        tools/v6_design.py           (netlist + placement)
Output: drivetrack-pcb-v6-electrical.kicad_pcb

Retained V5 footprints are lifted from the rev 6.0 board (real geometry),
placeholders are replaced, passives are auto-placed in free areas.
No routing, no zones: this is still a placement/netlist board.
"""
from __future__ import annotations

import math
import os
import re
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v6_design as D

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
SRC = os.path.join(ROOT, "DriveTrack-PCB-V6", "drivetrack-pcb-v6.kicad_pcb")
# J2 (USB-C) was dropped from the rev 6.0 mechanical board; lift it from V5.
SRC_V5 = "/workspace/drivetrack-v5-optimized/DriveTrack-PCB-V5/drivetrack-pcb-v5.kicad_pcb"
MODS = os.path.join(ROOT, "mods")
OUT = os.path.join(ROOT, "DriveTrack-PCB-V6", "drivetrack-pcb-v6-electrical.kicad_pcb")
NS = uuid.UUID("2c8d7d1e-6f4a-4d5e-9b3a-7c1f0e2a5b64")


def uid(*parts: str) -> str:
    return str(uuid.uuid5(NS, "/".join(parts)))


# ------------------------------------------------------------------ s-expr utils
def children(text: str) -> list[str]:
    """Top-level children of a '(keyword ...)' block string."""
    body = text.strip()[1:-1]
    out, depth, q, start = [], 0, False, None
    for i, ch in enumerate(body):
        if ch == '"':
            q = not q
        elif not q:
            if ch == '(':
                if depth == 0:
                    start = i
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0 and start is not None:
                    out.append(body[start:i + 1])
                    start = None
    return out


def head(block: str) -> str:
    m = re.match(r'\(\s*([^\s()]+)', block)
    return m.group(1) if m else ""


def balanced(text: str) -> int:
    d, q = 0, False
    for ch in text:
        if ch == '"':
            q = not q
        elif not q:
            if ch == '(':
                d += 1
            elif ch == ')':
                d -= 1
    return d


def remove_blocks(text: str, keys: tuple[str, ...]) -> str:
    """Remove every top-level child whose head is in keys."""
    return "".join(c for c in children(text) if head(c) not in keys)


def rebuild(block: str, kids: list[str]) -> str:
    h = head(block)
    return "(" + h + " " + " ".join(kids) + ")"


# ------------------------------------------------------------------ footprints
RETAIN = {"ANT1", "U2", "U3", "U4", "J2", "D1", "D2", "D3", "Q1", "Q3",
          "LED1", "MH1", "MH2", "MH3", "MH4"}


def load_mod(name: str) -> str:
    with open(os.path.join(MODS, name), encoding="utf-8") as f:
        return f.read()


def passive_mod(w: float, h: float, pad_w: float, pad_h: float, gap: float,
                name: str) -> str:
    """Two-pad passive footprint, pads left/right."""
    def pad(num, x):
        return (f'(pad "{num}" smd roundrect (at {x:.3f} 0) (size {pad_w:.3f} {pad_h:.3f}) '
                f'(layers "F.Cu" "F.Mask" "F.Paste") (roundrect_rratio 0.25) '
                f'(uuid "{uid("pad", name, num)}"))')
    silk = (f'(fp_line (start {-w / 2:.2f} {-h / 2:.2f}) (end {w / 2:.2f} {-h / 2:.2f}) '
            f'(stroke (width 0.12) (type solid)) (layer "F.SilkS") (uuid "{uid("silk", name, "1")}"))'
            f'(fp_line (start {w / 2:.2f} {h / 2:.2f}) (end {-w / 2:.2f} {h / 2:.2f}) '
            f'(stroke (width 0.12) (type solid)) (layer "F.SilkS") (uuid "{uid("silk", name, "2")}"))')
    crt = (f'(fp_rect (start {-w / 2 - 0.4:.2f} {-h / 2 - 0.4:.2f}) '
           f'(end {w / 2 + 0.4:.2f} {h / 2 + 0.4:.2f}) '
           f'(stroke (width 0.05) (type solid)) (fill none) (layer "F.CrtYd") '
           f'(uuid "{uid("crt", name)}"))')
    return (f'(footprint "{name}" (layer "F.Cu") (attr smd) '
            f'(fp_text reference "REF**" (at 0 {-h / 2 - 1.6:.2f} 0) (layer "F.SilkS") '
            f'(effects (font (size 0.7 0.7) (thickness 0.12))))'
            f'(fp_text value "VAL**" (at 0 {h / 2 + 1.6:.2f} 0) (layer "F.Fab") '
            f'(effects (font (size 0.7 0.7) (thickness 0.12))))'
            f'{silk}{crt}{pad("1", -gap / 2)}{pad("2", gap / 2)})')


PKG_MOD = {
    "C_0402": passive_mod(1.0, 0.5, 0.5, 0.6, 1.02, "C_0402_1005Metric"),
    "R_0402": passive_mod(1.0, 0.5, 0.5, 0.6, 1.02, "R_0402_1005Metric"),
    "C_0603": passive_mod(1.6, 0.8, 0.8, 0.95, 1.6, "C_0603_1608Metric"),
    "C_0805": passive_mod(2.0, 1.25, 1.0, 1.2, 1.9, "C_0805_2012Metric"),
    "SOD-323": passive_mod(1.7, 1.3, 0.6, 0.6, 2.2, "D_SOD-323"),
}


def tps63802_mod() -> str:
    pads = []
    left = [(1, -1.0), (2, -0.5), (3, 0.0), (4, 0.5), (5, 1.0)]
    right = [(6, 1.0), (7, 0.5), (8, 0.0), (9, -0.5), (10, -1.0)]
    for num, x in left:
        pads.append(f'(pad "{num}" smd roundrect (at {x:.2f} 1.05) (size 0.30 0.65) '
                    f'(layers "F.Cu" "F.Mask" "F.Paste") (roundrect_rratio 0.2) '
                    f'(uuid "{uid("pad", "U6", str(num))}"))')
    for num, x in right:
        pads.append(f'(pad "{num}" smd roundrect (at {x:.2f} -1.05) (size 0.30 0.65) '
                    f'(layers "F.Cu" "F.Mask" "F.Paste") (roundrect_rratio 0.2) '
                    f'(uuid "{uid("pad", "U6", str(num))}"))')
    return ('(footprint "VSON-10-3x2mm_P0.5mm_TPS63802" (layer "F.Cu") (attr smd) '
            '(fp_text reference "REF**" (at 0 -2.6 0) (layer "F.SilkS") '
            '(effects (font (size 0.7 0.7) (thickness 0.12))))'
            '(fp_text value "VAL**" (at 0 2.6 0) (layer "F.Fab") '
            '(effects (font (size 0.7 0.7) (thickness 0.12))))'
            f'(fp_rect (start -1.55 -1.65) (end 1.55 1.65) '
            f'(stroke (width 0.05) (type solid)) (fill none) (layer "F.CrtYd") '
            f'(uuid "{uid("crt", "U6")}"))'
            + "".join(pads) + ')')


def inductor_mod() -> str:
    return ('(footprint "L_4x4_H2" (layer "F.Cu") (attr smd) '
            '(fp_text reference "REF**" (at 0 -3.2 0) (layer "F.SilkS") '
            '(effects (font (size 0.7 0.7) (thickness 0.12))))'
            '(fp_text value "VAL**" (at 0 3.2 0) (layer "F.Fab") '
            '(effects (font (size 0.7 0.7) (thickness 0.12))))'
            f'(fp_rect (start -2.4 -2.4) (end 2.4 2.4) '
            f'(stroke (width 0.05) (type solid)) (fill none) (layer "F.CrtYd") '
            f'(uuid "{uid("crt", "L1")}"))'
            f'(pad "1" smd rect (at -1.35 0) (size 2.0 2.2) '
            f'(layers "F.Cu" "F.Mask" "F.Paste") (uuid "{uid("pad", "L1", "1")}"))'
            f'(pad "2" smd rect (at 1.35 0) (size 2.0 2.2) '
            f'(layers "F.Cu" "F.Mask" "F.Paste") (uuid "{uid("pad", "L1", "2")}"))'
            ')')


def pogo_mod() -> str:
    pads = []
    for i in range(6):
        x = -5.0 + i * 2.0
        pads.append(f'(pad "{i + 1}" smd circle (at {x:.2f} 0) (size 1.5 1.5) '
                    f'(layers "F.Cu" "F.Mask" "F.Paste") '
                    f'(uuid "{uid("pad", "J4", str(i + 1))}"))')
    return ('(footprint "Pogo_6_1.5mm" (layer "F.Cu") (attr smd) '
            '(fp_text reference "REF**" (at 0 -2.4 0) (layer "F.SilkS") '
            '(effects (font (size 0.7 0.7) (thickness 0.12))))'
            '(fp_text value "VAL**" (at 0 2.4 0) (layer "F.Fab") '
            '(effects (font (size 0.7 0.7) (thickness 0.12))))'
            f'(fp_rect (start -6.0 -1.6) (end 6.0 1.6) '
            f'(stroke (width 0.05) (type solid)) (fill none) (layer "F.CrtYd") '
            f'(uuid "{uid("crt", "J4")}"))'
            + "".join(pads) + ')')


MOD_BY_FP = {
    "Package_DFN_QFN:VQFN-16-1EP_3x3mm_P0.5mm_EP1.6x1.6mm":
        lambda: load_mod("VQFN-16-1EP_3x3mm_P0.5mm_EP1.6x1.6mm.kicad_mod"),
    "Package_TO_SOT_SMD:SOT-23-5": lambda: load_mod("SOT-23-5.kicad_mod"),
    "Package_TO_SOT_SMD:SOT-23": lambda: load_mod("SOT-23.kicad_mod"),
    "Package_SON:Texas_X2SON-4_1x1mm_P0.65mm":
        lambda: load_mod("Texas_X2SON-4_1x1mm_P0.65mm.kicad_mod"),
    "Package_LGA:LGA-12_2x2mm_P0.5mm": lambda: load_mod("LGA-12_2x2mm_P0.5mm.kicad_mod"),
    "Espressif:ESP32-S3-MINI-1": lambda: load_mod("ESP32-S3-MINI-1.kicad_mod"),
    "Connector_JST:JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal":
        lambda: load_mod("JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.kicad_mod"),
    "DriveTrack:VSON-10-3x2mm_P0.5mm_TPS63802": tps63802_mod,
    "DriveTrack:L_4x4_H2": inductor_mod,
    "DriveTrack:Pogo_6_1.5mm": pogo_mod,
    "Capacitor_SMD:C_0402_1005Metric": lambda: PKG_MOD["C_0402"],
    "Resistor_SMD:R_0402_1005Metric": lambda: PKG_MOD["R_0402"],
    "Capacitor_SMD:C_0603_1608Metric": lambda: PKG_MOD["C_0603"],
    "Capacitor_SMD:C_0805_2012Metric": lambda: PKG_MOD["C_0805"],
    "Diode_SMD:D_SOD-323": lambda: PKG_MOD["SOD-323"],
}


# ------------------------------------------------------------------ nets
def net_table():
    names = list(D.nets().keys())
    names.sort(key=lambda n: (n != "GND", n))
    return {n: i + 1 for i, n in enumerate(names)}


NETNO = net_table()
PINNET = {}
for _p in D.PARTS:
    for _num, _nm, _net in _p.pins:
        if _net:
            PINNET[(_p.ref, _num)] = _net


def strip_net(pad: str) -> str:
    pad = re.sub(r'\s*\(net\s+\d+\s+"[^"]*"\)', "", pad)
    return pad


def inject(pad: str, ref: str) -> str:
    num = re.match(r'\(pad "([^"]*)"', pad).group(1)
    net = PINNET.get((ref, num))
    has_cu = '"F.Cu"' in pad
    pad = strip_net(pad)
    if net and has_cu and num:
        m = re.search(r'\(layers\s+"[^"]*"(?:\s+"[^"]*")*\)', pad)
        ins = f' (net {NETNO[net]} "{net}")'
        if m:
            pad = pad[:m.end()] + ins + pad[m.end():]
        else:
            pad = pad[:-1] + ins + ")"
    if "(uuid" not in pad:
        pad = pad[:-1] + f' (uuid "{uid("pad", ref, num or "x")}"))'
    return pad


def to_board(mod: str, ref: str, value: str, fp_lib: str, x: float, y: float, rot: float) -> str:
    kids = children(mod)
    keep = []
    for k in kids:
        h = head(k)
        if h in ("version", "generator", "model", "layer"):
            continue
        if h == "fp_text":
            m = re.search(r'\(fp_text (\w+) "([^"]*)"', k)
            if m and m.group(1) == "reference":
                k = k.replace(f'"{m.group(2)}"', f'"{ref}"', 1)
            elif m and m.group(1) == "value":
                k = k.replace(f'"{m.group(2)}"', f'"{value}"', 1)
        elif h == "property":
            m = re.match(r'\(property "(\w+)" "([^"]*)"', k)
            if m and m.group(1) == "Reference":
                k = k.replace(f'"{m.group(2)}"', f'"{ref}"', 1)
            elif m and m.group(1) == "Value":
                k = k.replace(f'"{m.group(2)}"', f'"{value}"', 1)
        elif h == "pad":
            k = inject(k, ref)
        keep.append(k)
    # ensure reference/value exist (simple passives do)
    return (f'(footprint "{fp_lib}" (layer "F.Cu") (uuid "{uid("fp", ref)}") '
            f'(at {x:.4f} {-y:.4f} {rot:g}) ' + " ".join(keep) + ")")

# ------------------------------------------------------------------ placement
GRID = 0.5
NX, NY = 124, 124   # 0..62
occ = [[False] * NY for _ in range(NX)]


def mark(x0, y0, x1, y1):
    for ix in range(max(0, int(x0 / GRID)), min(NX, int(math.ceil(x1 / GRID)))):
        for iy in range(max(0, int(y0 / GRID)), min(NY, int(math.ceil(y1 / GRID)))):
            occ[ix][iy] = True


def free(x0, y0, x1, y1):
    if x0 < 1.2 or y0 < 1.2 or x1 > 60.8 or y1 > 60.8:
        return False
    for ix in range(max(0, int(x0 / GRID)), min(NX, int(math.ceil(x1 / GRID)))):
        for iy in range(max(0, int(y0 / GRID)), min(NY, int(math.ceil(y1 / GRID)))):
            if occ[ix][iy]:
                return False
    return True


SIZE = dict(D.SIZE)
SIZE.update({
    "C_0402": (1.6, 1.0), "R_0402": (1.6, 1.0), "C_0603": (2.2, 1.4),
    "C_0805": (2.8, 1.9), "SOD-323": (2.6, 1.8),
    "VQFN16": (3.6, 3.6), "SOT23-5": (3.4, 3.0), "X2SON4": (1.8, 1.8),
    "LGA12": (2.8, 2.8), "ESP32": (16.2, 16.2), "JSTSH": (6.0, 7.0),
    "POGO": (13.0, 3.4), "L4": (5.2, 5.2), "VSON10": (3.6, 2.8),
})

FP_SIZE = {
    "Espressif:ESP32-S3-MINI-1": "ESP32",
    "Package_DFN_QFN:VQFN-16-1EP_3x3mm_P0.5mm_EP1.6x1.6mm": "VQFN16",
    "Package_TO_SOT_SMD:SOT-23-5": "SOT23-5",
    "Package_SON:Texas_X2SON-4_1x1mm_P0.65mm": "X2SON4",
    "Package_LGA:LGA-12_2x2mm_P0.5mm": "LGA12",
    "Connector_JST:JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal": "JSTSH",
    "DriveTrack:VSON-10-3x2mm_P0.5mm_TPS63802": "VSON10",
    "DriveTrack:L_4x4_H2": "L4",
    "DriveTrack:Pogo_6_1.5mm": "POGO",
    "Capacitor_SMD:C_0402_1005Metric": "C_0402",
    "Resistor_SMD:R_0402_1005Metric": "R_0402",
    "Capacitor_SMD:C_0603_1608Metric": "C_0603",
    "Capacitor_SMD:C_0805_2012Metric": "C_0805",
    "Diode_SMD:D_SOD-323": "SOD-323",
}


def size_of(part: D.Part):
    key = FP_SIZE.get(part.fp)
    if key:
        return SIZE[key]
    return SIZE.get(part.ref, (4.0, 4.0))


def build_occupancy(fixed):
    # board edge
    mark(0, 0, 62, 1.2)
    mark(0, 60.8, 62, 62)
    mark(0, 0, 1.2, 62)
    mark(60.8, 0, 62, 62)
    # GNSS patch keepout (no passives, no parts other than antenna)
    mark(0, 0, 27.0, 27.0)
    # battery cable notch
    mark(59.0, 54.0, 62.0, 60.0)
    for ref, (x, y, rot) in fixed.items():
        w, h = SIZE.get(ref, (4, 4))
        if abs(rot) in (90, 270):
            w, h = h, w
        mark(x - w / 2 - 0.6, y - h / 2 - 0.6, x + w / 2 + 0.6, y + h / 2 + 0.6)
    # ESP32-S3-MINI-1 courtyard is not symmetric: antenna end sticks out
    # 5.6 mm north of the body centre (local -13.1..+8.0).
    mark(37.0, 24.9, 53.0, 27.7)


def anchor_for(part: D.Part, fixed):
    """Pick the fixed part this component should sit next to.

    Votes are weighted by 1/nodes so a dedicated 2-node net (e.g. ISET)
    beats a rail shared by a dozen capacitors, and GND never dominates.
    Ties are broken by a fixed priority so the result is deterministic.
    """
    votes = {}
    allnets = D.nets()
    for _num, _nm, net in part.pins:
        if not net or net == "GND":
            continue
        nodes = allnets.get(net, [])
        refs = {r for r, _p in nodes if r != part.ref and r in fixed}
        w = 1.0 / max(1, len(refs))
        for r in refs:
            votes[r] = votes.get(r, 0.0) + w
    if votes:
        prio = {r: i for i, r in enumerate(
            ["U5", "U6", "U7", "U8", "U9", "U1", "U2", "U3", "U4",
             "J2", "J3", "J4", "Q1", "Q2", "Q3", "D4", "D5"])}
        return min(votes, key=lambda r: (-votes[r], prio.get(r, 99)))
    # GND-only or NC-only parts: fall back to the first fixed part on a net
    for _num, _nm, net in part.pins:
        for r, p in allnets.get(net, []):
            if r in fixed:
                return r
    return "U5"


def autoplace():
    fixed = {r: D.PLACE[r] for r in D.PLACE}
    build_occupancy(fixed)
    placed = dict(fixed)
    movable = [p for p in D.PARTS if p.ref not in D.PLACE]
    for p in movable:
        w, h = size_of(p)
        ax, ay = D.PLACE[anchor_for(p, fixed)][:2]
        best = None
        for step in range(1, 46):
            radius = step * 1.0
            for k in range(0, 72):
                ang = 2 * math.pi * k / 72
                cx = ax + radius * math.cos(ang)
                cy = ay + radius * math.sin(ang)
                for ww, hh in ((w, h), (h, w)):
                    x0, y0 = cx - ww / 2, cy - hh / 2
                    if free(x0, y0, x0 + ww, y0 + hh):
                        best = (round(cx * 2) / 2, round(cy * 2) / 2, 0 if (ww, hh) == (w, h) else 90)
                        break
                if best:
                    break
            if best:
                break
        if not best:
            raise RuntimeError(f"no free area for {p.ref}")
        cx, cy, rot = best
        placed[p.ref] = (cx, cy, rot)
        ww, hh = (h, w) if rot == 90 else (w, h)
        mark(cx - ww / 2 - 0.35, cy - hh / 2 - 0.35,
             cx + ww / 2 + 0.35, cy + hh / 2 + 0.35)
    return placed


# ------------------------------------------------------------------ main
def main():
    src = open(SRC, encoding="utf-8").read()
    top = children(src)
    layers = next(b for b in top if head(b) == "layers")
    setup = next(b for b in top if head(b) == "setup")
    edge = [b for b in top if head(b) in ("gr_line", "gr_arc", "gr_rect", "gr_circle")
            and "Edge.Cuts" in b]
    src_fps = {}
    for b in top:
        if head(b) != "footprint":
            continue
        ref = re.search(r'\(property "Reference" "([^"]+)"', b)
        if ref:
            src_fps[ref.group(1)] = b
    # fallback: V5 board for footprints the mechanical board no longer carries
    if os.path.exists(SRC_V5):
        for b in children(open(SRC_V5, encoding="utf-8").read()):
            if head(b) != "footprint":
                continue
            ref = re.search(r'\(property "Reference" "([^"]+)"', b)
            if ref and ref.group(1) in RETAIN and ref.group(1) not in src_fps:
                src_fps[ref.group(1)] = b
    missing_src = sorted(RETAIN - set(src_fps))
    assert not missing_src, f"retained footprints not found: {missing_src}"

    placed = autoplace()

    fps = []
    for p in D.PARTS:
        x, y, rot = placed[p.ref]
        if p.ref in RETAIN:
            block = src_fps[p.ref]
            kids = children(block)
            out_kids = []
            for k in kids:
                h = head(k)
                if h in ("model", "layer", "uuid", "at", "tstamp"):
                    continue
                if h == "property":
                    m = re.search(r'\(property "(\w+)" "([^"]*)"', k)
                    if m and m.group(1) == "Value":
                        k = re.sub(r'\(property "Value" "[^"]*"',
                                   f'(property "Value" "{p.value}"', k, count=1)
                elif h == "pad":
                    k = inject(k, p.ref)
                out_kids.append(k)
            fps.append(f'(footprint "{p.fp}" (layer "F.Cu") (uuid "{uid("fp", p.ref)}") '
                       f'(at {x:.4f} {-y:.4f} {rot:g}) ' + " ".join(out_kids) + ")")
        else:
            mod = MOD_BY_FP[p.fp]()
            fps.append(to_board(mod, p.ref, p.value, p.fp, x, y, rot))

    nets = ["(net 0 \"\")"] + [f'(net {n} "{name}")' for name, n in
                              sorted(NETNO.items(), key=lambda kv: kv[1])]
    text = "\n".join([
        "(kicad_pcb",
        "(version 20241229)",
        '(generator "pcbnew")',
        '(generator_version "9.0")',
        '(general (thickness 1.6) (legacy_teardrops no))',
        '(paper "A4")',
        '(title_block (title "DriveTrack V6 electrical layout") (date "2026-11-23") '
        '(rev "6.1") (comment 1 "62 x 62 mm, 4-layer, real footprints, full netlist, unrouted") '
        '(comment 2 "BQ24074 + TPS63802 + TPS7A0230 soft latch, no buttons"))',
        layers,
        setup,
        *nets,
        *edge,
        *fps,
        ")",
        "",
    ])
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)

    # ---- placement.csv (all 75 parts, real board coordinates)
    import csv
    zone = {}
    for p in D.PARTS:
        r = p.ref
        zone[r] = ("GNSS_ANTENNA" if r in ("ANT1", "U2") else
                   "IMU_STRESS_FREE" if r == "U3" else
                   "PRESSURE_VENT" if r == "U4" else
                   "DIGITAL_RF" if r == "U1" else
                   "LED_STRIP" if r == "LED1" else
                   "POWER_EDGE" if r in ("J2", "D1", "D2", "D3") else
                   "BATTERY_CONNECTOR" if r == "J3" else
                   "MECHANICAL" if r.startswith("MH") else
                   "POWER_HOT" if r in ("U5", "U6", "U7", "U8", "U9", "L1",
                                        "Q1", "Q2", "Q3", "D4", "D5") else
                   "DECOUPLING")
    csv_path = os.path.join(ROOT, "placement.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Ref", "Value", "Package", "X_mm", "Y_mm", "Rotation_deg",
                    "Side", "Keepout_Zone", "Notes"])
        for p in sorted(D.PARTS, key=lambda q: q.ref):
            x, y, rot = placed[p.ref]
            w.writerow([p.ref, p.value, p.fp, f"{x:.2f}", f"{y:.2f}", rot,
                        "top", zone[p.ref], p.note])
    print("wrote", csv_path)

    # ---- checks
    print("written", OUT)
    print("balance", balanced(text), "footprints", len(fps), "nets", len(NETNO))
    # every design pad with a net must be present in its footprint
    from collections import defaultdict
    pads = defaultdict(list)
    for p in D.PARTS:
        if not any(n for _, _, n in p.pins):
            continue
        block = next(b for b in fps
                     if re.search(rf'\(property "Reference" "{p.ref}"', b)
                     or re.search(rf'\(fp_text reference "{p.ref}"', b))
        for m in re.finditer(r'\(pad "([^"]*)"', block):
            pads[p.ref].append(m.group(1))
    missing = []
    for p in D.PARTS:
        for num, _nm, net in p.pins:
            if net and num not in pads[p.ref]:
                missing.append(f"{p.ref}.{num}")
    print("missing pads:", missing if missing else "none")
    for ref, (x, y, rot) in sorted(placed.items()):
        print(f"  {ref:5s} {x:6.2f} {y:6.2f} rot {rot}")


if __name__ == "__main__":
    main()
