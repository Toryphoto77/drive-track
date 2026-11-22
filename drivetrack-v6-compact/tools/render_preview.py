#!/usr/bin/env python3
"""Render a top-view placement preview of the V6 electrical board.

Draws the real courtyards and pads from drivetrack-pcb-v6-electrical.kicad_pcb.
This is a placement reference only: no routing, no DRC.

Usage: python3 render_preview.py
"""
from __future__ import annotations

import math
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_v6_pcb_real as B

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
PCB = os.path.join(ROOT, "DriveTrack-PCB-V6", "drivetrack-pcb-v6-electrical.kicad_pcb")
OUT = os.path.join(ROOT, "DriveTrack-PCB-V6", "previews", "placement-v6")

FIXED = {"U1", "U2", "U3", "U4", "U5", "U6", "U7", "U8", "U9", "L1"}
CONN = {"J2", "J3", "J4", "ANT1", "LED1", "MH1", "MH2", "MH3", "MH4"}
POWER = {"Q1", "Q2", "Q3", "D4", "D5"}


def rot(x, y, deg):
    a = math.radians(deg)
    return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)


def shapes(block, layer):
    """Return list of local polygons for a layer from fp_rect / fp_line / fp_poly."""
    out = []
    for k in B.children(block):
        h = B.head(k)
        if layer not in k:
            continue
        if h in ("fp_rect",):
            m1 = re.search(r'\(start\s+([-\d.]+)\s+([-\d.]+)\)', k)
            m2 = re.search(r'\(end\s+([-\d.]+)\s+([-\d.]+)\)', k)
            if m1 and m2:
                x0, y0 = float(m1.group(1)), float(m1.group(2))
                x1, y1 = float(m2.group(1)), float(m2.group(2))
                out.append([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
        elif h in ("fp_line",):
            m1 = re.search(r'\(start\s+([-\d.]+)\s+([-\d.]+)\)', k)
            m2 = re.search(r'\(end\s+([-\d.]+)\s+([-\d.]+)\)', k)
            if m1 and m2:
                out.append([(float(m1.group(1)), float(m1.group(2))),
                            (float(m2.group(1)), float(m2.group(2)))])
        elif h in ("fp_poly",):
            pts = re.findall(r'\(xy\s+([-\d.]+)\s+([-\d.]+)\)', k)
            if pts:
                out.append([(float(a), float(b)) for a, b in pts])
    return out


def pads(block):
    out = []
    for k in B.children(block):
        if B.head(k) != "pad" or '"F.Cu"' not in k and '"*.Cu"' not in k:
            continue
        num = re.match(r'\(pad "([^"]*)"', k).group(1)
        at = re.search(r'\(at\s+([-\d.]+)\s+([-\d.]+)', k)
        sz = re.search(r'\(size\s+([-\d.]+)\s+([-\d.]+)\)', k)
        if not (at and sz):
            continue
        px, py = float(at.group(1)), float(at.group(2))
        w, h = float(sz.group(1)), float(sz.group(2))
        net = re.search(r'\(net\s+\d+\s+"([^"]*)"\)', k)
        out.append((px, py, w, h, net.group(1) if net else "", num))
    return out


def main():
    s = open(PCB, encoding="utf-8").read()
    fig, ax = plt.subplots(figsize=(9, 9), dpi=160)
    ax.set_facecolor("#0e1218")
    fig.patch.set_facecolor("#0e1218")

    # board outline (rounded rect approximated with plain rect)
    ax.add_patch(Polygon([(0, 0), (62, 0), (62, 62), (0, 62)], closed=True,
                         fill=True, facecolor="#151b23", edgecolor="#7ee0a1",
                         linewidth=1.6, zorder=0))

    # keepout zones
    for (x0, y0, x1, y1, label) in [
        (0.8, -26.3, 26.3, -0.8, "GNSS / patch"),
        (37.0, -27.6, 53.0, -6.4, "ESP32 antenna"),
    ]:
        ax.add_patch(Polygon([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], closed=True,
                             fill=True, facecolor="#1d2a33", edgecolor="#3d6b7a",
                             linewidth=0.8, linestyle=(0, (4, 3)), zorder=1))
        ax.text((x0 + x1) / 2, y1 - 1.0, label, color="#5d8e9e", fontsize=5.5,
                ha="center", va="top", zorder=6)

    refs = []
    for block in B.children(s):
        if B.head(block) != "footprint":
            continue
        ref = re.search(r'(?:\(property "Reference"|\(fp_text reference) "([^"]+)"',
                        block).group(1)
        val = re.search(r'(?:\(property "Value"|\(fp_text value) "([^"]*)"', block)
        val = val.group(1) if val else ""
        at = re.search(r'\(at\s+([-\d.]+)\s+([-\d.]+)(?:\s+([-\d.]+))?\)', block)
        cx, cy, r = float(at.group(1)), float(at.group(2)), float(at.group(3) or 0)

        if ref in FIXED:
            color, z = "#4da3ff", 2
        elif ref in POWER:
            color, z = "#ff9f43", 2
        elif ref in CONN:
            color, z = "#68d391", 2
        else:
            color, z = "#8b98a8", 2

        for poly in shapes(block, "F.CrtYd"):
            pts = []
            for x, y in poly:
                rx, ry = rot(x, y, r)
                pts.append((cx + rx, cy + ry))
            ax.add_patch(Polygon(pts, closed=len(pts) > 2, fill=len(pts) > 2,
                                 facecolor=color, alpha=0.10 if len(pts) > 2 else 1.0,
                                 edgecolor=color, linewidth=0.55, zorder=z))

        for px, py, w, h, net, num in pads(block):
            rx, ry = rot(px, py, r)
            x, y = cx + rx, cy + ry
            pcol = "#ffd166" if net else "#4a5568"
            ax.add_patch(Polygon([(x - w / 2, y - h / 2), (x + w / 2, y - h / 2),
                                  (x + w / 2, y + h / 2), (x - w / 2, y + h / 2)],
                                 closed=True, facecolor=pcol, edgecolor="none",
                                 alpha=0.9, zorder=3))
        refs.append((ref, val, cx, cy, color))

    for ref, val, x, y, color in refs:
        if ref.startswith("MH"):
            continue
        short = val if len(val) <= 12 else val[:11] + "."
        ax.text(x, y, f"{ref}\n{short}", color=color, fontsize=3.4,
                ha="center", va="center", zorder=7, linespacing=0.95)

    # frame
    ax.set_xlim(-1.5, 63.5)
    ax.set_ylim(-63.5, 1.5)
    ax.set_aspect("equal")
    ax.set_xticks(range(0, 63, 10))
    ax.set_yticks(range(0, -63, -10))
    ax.tick_params(colors="#65727f", labelsize=6)
    for sp in ax.spines.values():
        sp.set_color("#2a3440")
    ax.grid(color="#1e2733", linewidth=0.4)
    ax.set_title("DriveTrack V6 rev 6.1 — 62 × 62 mm, real footprints, placement only (no routing / no DRC)",
                 color="#d7e2ee", fontsize=8, pad=10)
    ax.text(61.5, -59.0, "GND pour not shown", color="#65727f", fontsize=5, ha="right")
    ax.text(61.5, -60.4, "USB-C overhangs south edge", color="#68d391", fontsize=5, ha="right")
    ax.text(22.0, -60.4, "MH3 moved west of USB-C", color="#68d391", fontsize=5, ha="left")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    fig.savefig(OUT + ".png", bbox_inches="tight", facecolor=fig.get_facecolor())
    fig.savefig(OUT + ".svg", bbox_inches="tight", facecolor=fig.get_facecolor())
    print("wrote", OUT + ".png/.svg")


if __name__ == "__main__":
    main()
