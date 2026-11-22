#!/usr/bin/env python3
"""Build the DriveTrack V6 mechanical/placement PCB from the V5 board.

V6 is a 62 x 62 mm placement reference: outline, zones, retained components
and mechanical placeholders for the new power chain.  It is NOT a routed or
netlist-complete production board.

Usage: python build_v6_pcb.py
"""
from __future__ import annotations
import re
import uuid
from pathlib import Path

SRC = Path("/workspace/drivetrack-v5-optimized/DriveTrack-PCB-V5/drivetrack-pcb-v5.kicad_pcb")
OUT = Path("/workspace/drivetrack-v6-compact/DriveTrack-PCB-V6/drivetrack-pcb-v6.kicad_pcb")
BOARD = 62.0

# ref -> (x, y, rot)   board coordinates, y positive downwards
KEEP = {
    "ANT1": (13.5, 13.0, 0),
    "U2":   (13.5, 34.0, -90),
    "U3":   (7.5, 50.0, 0),
    "U4":   (3.5, 45.0, 0),
    "D1":   (26.5, 52.0, 0),
    "D2":   (29.0, 52.0, 0),
    "D3":   (31.5, 52.0, 0),
    "Q1":   (42.5, 52.0, 0),
    "Q3":   (49.5, 52.0, 0),
    "MH1":  (30.0, 3.0, 0),
    "MH2":  (54.0, 3.0, 0),
    "MH3":  (30.0, 59.0, 0),
    "MH4":  (54.0, 59.0, 0),
}
RENAME = {"U7": "LED1"}          # old SK6812 becomes the single RGB LED

# ref, value, x, y, rot, w, h, height
PLACEHOLDERS = [
    ("U1", "ESP32-S3-MINI-1U-N8R2", 45.0, 14.5, 0, 15.4, 20.5, 2.4),
    ("U5", "BQ24074", 42.0, 46.0, 0, 3.0, 3.0, 0.8),
    ("U6", "TPS63802", 48.0, 46.0, 0, 2.5, 2.0, 0.6),
    ("U7", "TPS7A2033", 36.0, 46.0, 0, 3.0, 2.9, 1.1),
    ("U8", "TPS7A0230", 36.0, 52.0, 0, 1.5, 1.5, 0.5),
    ("U9", "LIS2DW12", 39.0, 52.0, 0, 2.0, 2.0, 0.7),
    ("L1", "1uH 4x4x2", 53.0, 45.5, 0, 4.0, 4.0, 2.0),
    ("J3", "JST-SH 1.0mm 2P", 57.5, 55.0, 180, 4.2, 3.2, 2.9),
    ("Q2", "2N7002", 46.0, 52.0, 0, 2.9, 2.4, 1.0),
]


def blocks(s: str, head: str):
    """Yield (start, end) of every balanced (head ...) block, ignoring
    parentheses that appear inside quoted strings (net names such as
    "Net-(U5-BAT)" otherwise break naive counting)."""
    for m in re.finditer(r"\(" + head + r"\b", s):
        start = m.start()
        d = 0
        i = start
        inq = False
        esc = False
        while i < len(s):
            ch = s[i]
            if inq:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    inq = False
            else:
                if ch == '"':
                    inq = True
                elif ch == "(":
                    d += 1
                elif ch == ")":
                    d -= 1
                    if d == 0:
                        break
            i += 1
        yield start, i + 1


def prop(blk: str, name: str) -> str:
    m = re.search(r'\(property\s+"' + name + r'"\s+"([^"]*)"', blk)
    return m.group(1) if m else ""


def placeholder(ref, val, x, y, rot, w, h, hz):
    u = lambda: str(uuid.uuid4())
    return f'''  (footprint "DriveTrackV6:PLACEHOLDER_{ref}" (layer "F.Cu") (uuid "{u()}") (at {x:.4f} {-y:.4f} {rot:.4f}) (descr "V6 mechanical placeholder {val}, {w}x{h}mm, approx {hz}mm tall, no pads") (tags "v6 placeholder mechanical")
    (property "Reference" "{ref}" (at 0 {-h/2-0.8:.4f} 0) (layer "F.SilkS") (uuid "{u()}") (effects (font (size 0.8 0.8) (thickness 0.12))))
    (property "Value" "{val}" (at 0 {h/2+0.8:.4f} 0) (layer "F.Fab") (uuid "{u()}") (effects (font (size 0.6 0.6) (thickness 0.1))))
    (property "Datasheet" "" (at 0 0 0) (layer "F.Fab") (hide yes) (uuid "{u()}") (effects (font (size 1.27 1.27) (thickness 0.15))))
    (property "Description" "" (at 0 0 0) (layer "F.Fab") (hide yes) (uuid "{u()}") (effects (font (size 1.27 1.27) (thickness 0.15))))
    (attr smd exclude_from_pos_files exclude_from_bom)
    (fp_rect (start {-w/2:.3f} {-h/2:.3f}) (end {w/2:.3f} {h/2:.3f}) (stroke (width 0.05) (type solid)) (fill none) (layer "F.CrtYd") (uuid "{u()}"))
    (fp_rect (start {-w/2:.3f} {-h/2:.3f}) (end {w/2:.3f} {h/2:.3f}) (stroke (width 0.1) (type solid)) (fill none) (layer "F.Fab") (uuid "{u()}"))
    (fp_line (start {-w/2:.3f} {-h/2:.3f}) (end {w/2:.3f} {-h/2:.3f}) (stroke (width 0.1) (type solid)) (layer "F.SilkS") (uuid "{u()}"))
    (fp_line (start {-w/2:.3f} {h/2:.3f}) (end {w/2:.3f} {h/2:.3f}) (stroke (width 0.1) (type solid)) (layer "F.SilkS") (uuid "{u()}"))
    (embedded_fonts no)
  )
'''


def main():
    s = SRC.read_text()
    original_len = len(s)

    # --- collect footprints -------------------------------------------------
    fps = []
    for a, b in blocks(s, "footprint"):
        blk = s[a:b]
        ref = prop(blk, "Reference")
        if ref:
            fps.append((ref, a, b, blk))
    print(f"source footprints: {len(fps)}")

    delete = []          # character ranges to remove
    replaced = {}        # (a,b) -> new block
    seen = set()
    for ref, a, b, blk in fps:
        newref = RENAME.get(ref, ref)
        if ref in KEEP or ref in RENAME:
            if ref in KEEP:
                x, y, rot = KEEP[ref]
            else:
                x, y, rot = 56.0, 8.0, 0.0
            nb = re.sub(r"\(\s*at\s+[-\d.]+\s+[-\d.]+(?:\s+[-\d.]+)?\s*\)",
                        f"(at {x:.4f} {-y:.4f} {rot:.4f})", blk, count=1)
            if ref in RENAME:
                nb = nb.replace(f'(property "Reference" "{ref}"', f'(property "Reference" "{newref}"')
                nb = re.sub(r'\(property "Value"\s+"[^"]*"', '(property "Value" "SK6812MINI RGB"', nb, count=1)
            if ref == "Q1":
                nb = re.sub(r'\(property "Value"\s+"[^"]*"', '(property "Value" "AO3401"', nb, count=1)
            replaced[(a, b)] = nb
            seen.add(newref)
        else:
            delete.append((a, b))

    assert "ANT1" in seen and "U2" in seen and "MH4" in seen, seen

    # --- apply replacements and deletions in one pass ----------------------
    ops = [(a, b, nb) for (a, b), nb in replaced.items()] + [(a, b, "") for a, b in delete]
    ops.sort()
    out = []
    cur = 0
    for a, b, nb in ops:
        assert a >= cur, "overlapping ranges"
        out.append(s[cur:a])
        out.append(nb)
        cur = b
    out.append(s[cur:])
    s = "".join(out)
    print(f"kept blocks: {len(replaced)}  deleted blocks: {len(delete)}")

    # --- edge cuts ---------------------------------------------------------
    lines = s.splitlines(keepends=True)
    cut = [i for i, ln in enumerate(lines) if '(layer "Edge.Cuts")' in ln]
    assert cut, "no edge cuts found"
    new_cut = [
        '  (gr_line (start 2 0) (end 60 0) (stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid "%s"))\n' % uuid.uuid4(),
        '  (gr_line (start 62 -2) (end 62 -60) (stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid "%s"))\n' % uuid.uuid4(),
        '  (gr_line (start 60 -62) (end 2 -62) (stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid "%s"))\n' % uuid.uuid4(),
        '  (gr_line (start 0 -60) (end 0 -2) (stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid "%s"))\n' % uuid.uuid4(),
        '  (gr_arc (start 2 0) (mid 0.586 -0.586) (end 0 -2) (stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid "%s"))\n' % uuid.uuid4(),
        '  (gr_arc (start 62 -2) (mid 61.414 -0.586) (end 60 0) (stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid "%s"))\n' % uuid.uuid4(),
        '  (gr_arc (start 60 -62) (mid 61.414 -61.414) (end 62 -60) (stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid "%s"))\n' % uuid.uuid4(),
        '  (gr_arc (start 0 -60) (mid 0.586 -61.414) (end 2 -62) (stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid "%s"))\n' % uuid.uuid4(),
    ]
    first = cut[0]
    lines = [ln for i, ln in enumerate(lines) if i not in set(cut)]
    lines[first:first] = new_cut
    s = "".join(lines)

    # --- remove routing and zones (balanced blocks, root close survives) ---
    rout = []
    for head in ("segment", "via", "zone"):
        rout.extend(blocks(s, head))
    rout.sort()
    out = []
    cur = 0
    for a, b in rout:
        assert a >= cur
        out.append(s[cur:a])
        cur = b
    out.append(s[cur:])
    s = "".join(out)
    print(f"removed routing/zone blocks: {len(rout)}")

    # --- title block -------------------------------------------------------
    s = re.sub(r'\(title\s+"[^"]*"\)', '(title "DriveTrack Custom PCB V6 mechanical layout")', s, count=1)
    s = re.sub(r'\(rev\s+"[^"]*"\)', '(rev "6.0")', s, count=1)
    s = re.sub(r'\(comment 1\s+"[^"]*"\)',
               '(comment 1 "62 x 62 mm, 4-layer, 103450 cell under right side, placement reference only")', s, count=1)

    # --- placeholders ------------------------------------------------------
    newfps = "".join(placeholder(*p) for p in PLACEHOLDERS)
    end = s.rstrip().rfind(")")
    s = s[:end] + newfps + s[end:]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(s)

    # --- validation --------------------------------------------------------
    def balanced(text: str) -> bool:
        d = 0
        inq = False
        esc = False
        for ch in text:
            if inq:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    inq = False
            elif ch == '"':
                inq = True
            elif ch == "(":
                d += 1
            elif ch == ")":
                d -= 1
                if d < 0:
                    return False
        return d == 0 and not inq

    assert balanced(s), "unbalanced parentheses outside strings"
    refs = re.findall(r'\(property\s+"Reference"\s+"([^"]+)"', s)
    print(f"output footprints: {len(refs)}")
    print("refs:", " ".join(refs))
    print(f"paren: {s.count('(')}/{s.count(')')}  size {len(s)} (was {original_len})")
    print("outline: 0..62 x 0..-62, R2")
    assert len(refs) == len(set(refs)), "duplicate refs"
    assert OUT.stat().st_size > 50000, "file looks truncated"


if __name__ == "__main__":
    main()
