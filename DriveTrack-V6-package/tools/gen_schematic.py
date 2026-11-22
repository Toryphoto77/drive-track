#!/usr/bin/env python3
"""Export the V6 design as CSV netlist / BOM and a KiCad 7-format schematic.

The schematic is netlist-style: every component is a rectangular symbol with
real pin names, and each pin carries a global label. It is electrically
complete (same net names as the PCB) but not drawn as pretty blocks.
"""
from __future__ import annotations

import csv
import math
import os
import re
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v6_design as D

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "DriveTrack-PCB-V6"))
NS = uuid.UUID("6f1c7d2e-4a52-4b8b-9a63-2f5c1e0d9a71")


def uid(*parts: str) -> str:
    return str(uuid.uuid5(NS, "/".join(parts)))


def sym_name(ref: str) -> str:
    return "SYM_" + ref


def write_netlist_csv():
    path = os.path.join(OUT, "netlist-v6.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["ref", "value", "footprint", "pin", "pin_name", "net"])
        for p in D.PARTS:
            for num, name, net in p.pins:
                w.writerow([p.ref, p.value, p.fp, num, name, net])
    return path


def write_nets_csv():
    path = os.path.join(OUT, "nets-v6.csv")
    nets = D.nets()
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["net", "nodes", "connections"])
        for name, nodes in sorted(nets.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            w.writerow([name, len(nodes), " ".join(f"{r}.{p}" for r, p in nodes)])
    return path


def write_bom_csv():
    path = os.path.join(OUT, "bom-v6.csv")
    groups: dict[tuple[str, str], list[str]] = {}
    for p in D.PARTS:
        if p.ref.startswith("MH"):
            key = ("M2 NPTH mounting hole", p.fp)
        else:
            key = (p.value, p.fp)
        groups.setdefault(key, []).append(p.ref)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["value", "footprint", "qty", "refs", "note"])
        for (value, fp), refs in sorted(groups.items()):
            note = D.part(refs[0]).note
            w.writerow([value, fp, len(refs), " ".join(sorted(refs)), note])
    return path


# --------------------------------------------------------------------------- schematic
PAPER_W, PAPER_H = 594.0, 420.0   # A2 landscape
COLS = [80.0, 195.0, 310.0, 425.0, 540.0]
TOP = 40.0
BOTTOM = 400.0
HALF_W = 30.0
PIN_LEN = 3.81
PITCH = 2.54

ORDER = (
    ["U5", "U6", "U7", "U8", "U9", "L1", "Q1", "Q2", "Q3", "D4", "D5",
     "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10",
     "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R9", "R10", "R11",
     "R12", "R13", "R14", "R22", "R23", "R24", "R25", "C22", "C23", "C24",
     "U1", "J4", "U2", "ANT1", "U3", "U4",
     "J2", "D1", "D2", "D3", "LED1", "J3",
     "C11", "C12", "C13", "C14", "C15", "C16", "C17", "C18", "C19", "C20", "C21",
     "R15", "R16", "R17", "R18", "R19", "R20", "R21"]
)


def split_pins(pins):
    left, right = [], []
    for i, pin in enumerate(pins):
        (left if i % 2 == 0 else right).append(pin)
    return left, right


def symbol_height(npins_max: int) -> float:
    return max(14.0, npins_max * PITCH + 8.0)


def esc(s: str) -> str:
    return s.replace('"', '\\"')


def lib_symbol(part: D.Part) -> str:
    left, right = split_pins(part.pins)
    h = symbol_height(max(len(left), len(right)))
    hw = HALF_W
    top = (len(left) - 1) * PITCH / 2.0
    top_r = (len(right) - 1) * PITCH / 2.0
    out = []
    out.append(f'  (symbol "DriveTrack:{sym_name(part.ref)}" (pin_names (offset 1.016)) '
               f'(in_bom yes) (on_board yes)')
    out.append(f'    (property "Reference" "{part.ref[0]}" (at {hw + 4:.2f} {h / 2:.2f} 0) '
               f'(effects (font (size 1.27 1.27)) (justify left)))')
    out.append(f'    (property "Value" "{esc(part.value)}" (at {hw + 4:.2f} {h / 2 - 2.54:.2f} 0) '
               f'(effects (font (size 1.27 1.27)) (justify left)))')
    out.append(f'    (property "Footprint" "{esc(part.fp)}" (at 0 0 0) '
               f'(effects (font (size 1.27 1.27)) hide))')
    out.append(f'    (property "Datasheet" "" (at 0 0 0) '
               f'(effects (font (size 1.27 1.27)) hide))')
    out.append(f'    (symbol "{sym_name(part.ref)}_0_1"')
    out.append(f'      (rectangle (start {-hw:.2f} {-h / 2:.2f}) (end {hw:.2f} {h / 2:.2f})')
    out.append('        (stroke (width 0.254) (type default)) (fill (type background)))')
    out.append('    )')
    out.append(f'    (symbol "{sym_name(part.ref)}_1_1"')
    for i, (num, name, _net) in enumerate(left):
        y = top - i * PITCH
        out.append(f'      (pin passive line (at {-(hw + PIN_LEN):.2f} {y:.2f} 0) '
                   f'(length {PIN_LEN:g})')
        out.append(f'        (name "{esc(name)}" (effects (font (size 1.27 1.27))))')
        out.append(f'        (number "{num}" (effects (font (size 1.27 1.27)))))')
    for i, (num, name, _net) in enumerate(right):
        y = top_r - i * PITCH
        out.append(f'      (pin passive line (at {(hw + PIN_LEN):.2f} {y:.2f} 180) '
                   f'(length {PIN_LEN:g})')
        out.append(f'        (name "{esc(name)}" (effects (font (size 1.27 1.27))))')
        out.append(f'        (number "{num}" (effects (font (size 1.27 1.27)))))')
    out.append('    )')
    out.append('  )')
    return "\n".join(out)


def place() -> dict[str, tuple[float, float]]:
    """Pack blocks into columns."""
    pos = {}
    col = 0
    y = TOP
    for ref in ORDER:
        p = D.part(ref)
        left, right = split_pins(p.pins)
        h = symbol_height(max(len(left), len(right)))
        if y + h > BOTTOM:
            col += 1
            y = TOP
            if col >= len(COLS):
                raise RuntimeError("schematic page overflow")
        cx = COLS[col]
        cy = y + h / 2.0
        pos[ref] = (cx, cy)
        y += h + 6.0
    return pos


def schematic() -> str:
    pos = place()
    root = uid("root")
    out = []
    out.append('(kicad_sch (version 20230121) (generator eeschema)')
    out.append(f'  (uuid "{root}")')
    out.append('  (paper "A2")')
    out.append('  (title_block')
    out.append('    (title "DriveTrack V6 — power, wake and sensor board")')
    out.append('    (date "2026-11-23")')
    out.append('    (rev "6.1")')
    out.append('    (company "DriveTrack")')
    out.append('    (comment 1 "62 x 62 mm, 4-layer. Netlist-style schematic: every pin carries a global label.")')
    out.append('    (comment 2 "No-connect pins are left without a label on purpose.")')
    out.append('  )')
    out.append('  (lib_symbols')
    for ref in ORDER:
        out.append(lib_symbol(D.part(ref)))
    out.append('  )')

    for ref in ORDER:
        p = D.part(ref)
        cx, cy = pos[ref]
        left, right = split_pins(p.pins)
        h = symbol_height(max(len(left), len(right)))
        out.append(f'  (symbol (lib_id "DriveTrack:{sym_name(ref)}") (at {cx:.2f} {cy:.2f} 0) '
                   f'(unit 1) (in_bom yes) (on_board yes) (dnp no)')
        out.append(f'    (uuid "{uid("sym", ref)}")')
        out.append(f'    (property "Reference" "{ref}" (at {cx:.2f} {cy - h / 2 - 2.54:.2f} 0) '
                   f'(effects (font (size 1.27 1.27))))')
        out.append(f'    (property "Value" "{esc(p.value)}" (at {cx:.2f} {cy + h / 2 + 2.54:.2f} 0) '
                   f'(effects (font (size 1.27 1.27))))')
        out.append(f'    (property "Footprint" "{esc(p.fp)}" (at {cx:.2f} {cy:.2f} 0) '
                   f'(effects (font (size 1.27 1.27)) hide))')
        for num, _name, _net in p.pins:
            out.append(f'    (pin "{num}" (uuid "{uid("pin", ref, num)}"))')
        out.append(f'    (instances (project "drivetrack-pcb-v6" '
                   f'(path "/{root}" (reference "{ref}") (unit 1))))')
        out.append('  )')

    # global labels at every pin end
    for ref in ORDER:
        p = D.part(ref)
        cx, cy = pos[ref]
        left, right = split_pins(p.pins)
        h = symbol_height(max(len(left), len(right)))
        top_l = (len(left) - 1) * PITCH / 2.0
        top_r = (len(right) - 1) * PITCH / 2.0
        for i, (num, _name, net) in enumerate(left):
            sy = top_l - i * PITCH
            x = cx - (HALF_W + PIN_LEN)
            y = cy - sy
            if not net:
                out.append(f'  (no_connect (at {x:.2f} {y:.2f}) '
                           f'(uuid "{uid("nc", ref, num)}"))')
                continue
            out.append(f'  (global_label "{esc(net)}" (shape passive) (at {x:.2f} {y:.2f} 180) '
                       f'(effects (font (size 1.27 1.27)) (justify right)) '
                       f'(uuid "{uid("gl", ref, num)}"))')
        for i, (num, _name, net) in enumerate(right):
            sy = top_r - i * PITCH
            x = cx + (HALF_W + PIN_LEN)
            y = cy - sy
            if not net:
                out.append(f'  (no_connect (at {x:.2f} {y:.2f}) '
                           f'(uuid "{uid("nc", ref, num)}"))')
                continue
            out.append(f'  (global_label "{esc(net)}" (shape passive) (at {x:.2f} {y:.2f} 0) '
                       f'(effects (font (size 1.27 1.27)) (justify left)) '
                       f'(uuid "{uid("gl", ref, num)}"))')

    out.append('  (sheet_instances (path "/" (page "1")))')
    out.append(')')
    return "\n".join(out) + "\n"


def main():
    os.makedirs(OUT, exist_ok=True)
    for fn in (write_netlist_csv(), write_nets_csv(), write_bom_csv()):
        print("wrote", fn)
    text = schematic()
    path = os.path.join(OUT, "drivetrack-v6.kicad_sch")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    # quote-aware balance check
    d = 0
    q = False
    for ch in text:
        if ch == '"':
            q = not q
        elif not q:
            if ch == '(':
                d += 1
            elif ch == ')':
                d -= 1
    print("wrote", path, "balance", d, "bytes", len(text))


if __name__ == "__main__":
    main()
