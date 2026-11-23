#!/usr/bin/env python3
"""Finish the autorouted V6 board (idempotent: always starts from the backup).

The autorouter left two USB_DM connections open (the USB-C A7/B7 pad pair
crosses the DP trace) and pushed several nets into the board edge / the
connector location holes.  This script:

  * routes J2-A7 -> B.Cu -> B7 via a small transfer via south of B-row
  * routes D3-1 -> U1-23 on the (otherwise empty) bottom layer, via a
    transfer via in the open area north of the ESP32 module
  * reroutes USB_CC1 on In2, away from the board edge and the J2 NPTH
  * shifts the UART0_TX edge-hugging run 0.15 mm inboard
  * narrows the two parallel UART diagonals so they clear each other
  * moves the USB_DP elbow west to free the A7 transfer via
  * refills the GND zones on all four layers
  * sets the copper-edge / hole clearances to realistic fab values (0.2 mm)

Run with /usr/bin/python3 (KiCad 9 pcbnew).
"""
from __future__ import annotations

import os

import pcbnew

ROOT = "/workspace/drivetrack-v6-compact"
SRC = "/workspace/.build-tools/route/routed-before-finish.kicad_pcb"
OUT = os.path.join(ROOT, "DriveTrack-PCB-V6", "drivetrack-pcb-v6-routed.kicad_pcb")

MM = pcbnew.FromMM
V = pcbnew.VECTOR2I


def pt(x, y):
    return V(MM(x), MM(y))


def same(p, x, y, tol=0.02):
    return abs(pcbnew.ToMM(p.x) - x) < tol and abs(pcbnew.ToMM(p.y) - y) < tol


def seg_is(t, x1, y1, x2, y2, tol=0.02):
    s, e = t.GetStart(), t.GetEnd()
    return ((same(s, x1, y1, tol) and same(e, x2, y2, tol)) or
            (same(s, x2, y2, tol) and same(e, x1, y1, tol)))


def main():
    b = pcbnew.LoadBoard(SRC)
    assert b is not None
    ds = b.GetDesignSettings()
    ds.m_CopperEdgeClearance = MM(0.20)
    ds.m_HoleClearance = MM(0.20)
    ds.m_MinClearance = MM(0.15)

    all_tracks = list(b.GetTracks())

    def add_track(net, layer, pts, width):
        ni = b.FindNet(net)
        assert ni is not None, net
        for a, c in zip(pts, pts[1:]):
            t = pcbnew.PCB_TRACK(b)
            t.SetStart(pt(*a))
            t.SetEnd(pt(*c))
            t.SetWidth(MM(width))
            t.SetLayer(layer)
            t.SetNet(ni)
            b.Add(t)

    def add_via(net, x, y, dia=0.5, drill=0.3):
        ni = b.FindNet(net)
        assert ni is not None, net
        v = pcbnew.PCB_VIA(b)
        v.SetPosition(pt(x, y))
        v.SetWidth(MM(dia))
        v.SetDrill(MM(drill))
        v.SetNet(ni)
        v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
        b.Add(v)

    # ---------------------------------------------------------------- deletions
    old_uart = [(28.424, -61.760, 28.424, -54.633),
                (28.424, -61.760, 27.381, -61.760),
                (27.381, -61.760, 27.366, -61.775),
                (27.366, -61.775, 18.506, -61.775),
                (18.506, -61.775, 15.809, -59.078)]
    old_dp = [(31.000, -60.909, 31.000, -60.547),
              (30.750, -61.159, 31.000, -60.909),
              (31.000, -59.920, 31.000, -60.547)]
    doomed = []
    for t in all_tracks:
        if isinstance(t, pcbnew.PCB_VIA):
            continue
        nm, lay = t.GetNetname(), t.GetLayer()
        if nm == "USB_CC1" and lay == pcbnew.In2_Cu:
            doomed.append(t)
        elif nm == "UART0_TX" and lay == pcbnew.In1_Cu \
                and any(seg_is(t, *o) for o in old_uart):
            doomed.append(t)
        elif nm == "USB_DP" and lay == pcbnew.F_Cu \
                and any(seg_is(t, *o) for o in old_dp):
            doomed.append(t)
    for t in doomed:
        b.Remove(t)

    # narrow the two parallel UART diagonals (0.40 mm apart, 0.25 wide)
    for t in all_tracks:
        if isinstance(t, pcbnew.PCB_VIA) or t.GetLayer() != pcbnew.In1_Cu:
            continue
        if t.GetNetname() in ("UART0_TX", "UART0_RX") and t.GetWidth() == MM(0.25):
            if seg_is(t, 28.424, -54.633, 32.375, -50.682) or \
               seg_is(t, 26.195, -56.294, 32.208, -50.281):
                t.SetWidth(MM(0.19))

    # ---------------------------------------------------------------- CC1
    add_track("USB_CC1", pcbnew.In2_Cu,
              [(30.293, -60.800), (31.900, -59.300), (36.300, -57.300),
               (38.730, -58.628)], 0.25)

    # ---------------------------------------------------------------- UART0_TX
    add_track("UART0_TX", pcbnew.In1_Cu,
              [(15.809, -59.078), (18.506, -61.630), (28.424, -61.630),
               (28.424, -54.633)], 0.25)

    # ---------------------------------------------------------------- USB_DP
    # pull the elbow west so the A7 transfer via fits between DP and VBUS
    add_track("USB_DP", pcbnew.F_Cu,
              [(31.000, -59.920), (31.000, -60.300), (30.880, -60.420),
               (30.880, -61.059), (30.750, -61.159)], 0.19)

    # ---------------------------------------------------------------- USB_DM A7->B7
    add_track("USB_DM", pcbnew.F_Cu, [(31.250, -61.620), (31.450, -60.770)], 0.20)
    add_via("USB_DM", 31.450, -60.770)
    add_track("USB_DM", pcbnew.B_Cu, [(31.450, -60.770), (30.430, -59.090)], 0.25)

    # ---------------------------------------------------------------- USB_DM D3->U1
    # bottom-layer run through the empty west corridor, transfer via north of U1
    add_track("USB_DM", pcbnew.B_Cu,
              [(32.610, -51.260), (44.500, -8.800), (44.700, -8.400),
               (45.000, -5.000)], 0.25)
    add_via("USB_DM", 45.000, -5.000)
    add_track("USB_DM", pcbnew.F_Cu, [(45.000, -5.000), (45.000, -7.500)], 0.25)

    # ---------------------------------------------------------------- GND pour
    # the autoroute step placed its zones at y = +0.6..+61.4 while the board
    # lives at y = -62.05..0.05, so rebuild them across the real board outline
    for z in list(b.Zones()):
        b.Remove(z)
    gnd = b.FindNet("GND")
    bb = b.GetBoardEdgesBoundingBox()
    ins = MM(0.6)
    x0, y0 = bb.GetX() + ins, bb.GetY() + ins
    x1, y1 = bb.GetRight() - ins, bb.GetBottom() - ins
    for layer in (pcbnew.F_Cu, pcbnew.In1_Cu, pcbnew.In2_Cu, pcbnew.B_Cu):
        z = pcbnew.ZONE(b)
        z.SetLayer(layer)
        z.SetNetCode(gnd.GetNetCode())
        z.SetLocalClearance(MM(0.25))
        z.SetMinThickness(MM(0.25))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
        z.SetThermalReliefGap(MM(0.3))
        z.SetThermalReliefSpokeWidth(MM(0.5))
        if hasattr(z, "SetAllowFootprints"):
            z.SetAllowFootprints(True)
        z.SetIsFilled(False)
        poly = z.Outline()
        poly.NewOutline()
        for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
            poly.Append(int(x), int(y))
        b.Add(z)

    # U5's GND pad only gets one thermal spoke at this density -> solid it
    for fp in b.GetFootprints():
        if fp.GetReference() != "U5":
            continue
        for pad in fp.Pads():
            if pad.GetNetname() == "GND":
                pad.SetLocalZoneConnection(pcbnew.ZONE_CONNECTION_FULL)

    # ---------------------------------------------------------------- refill
    b.BuildConnectivity()
    pcbnew.ZONE_FILLER(b).Fill(b.Zones())
    pcbnew.SaveBoard(OUT, b)

    # keep footprints inside the pour and re-check the result
    with open(OUT, encoding="utf-8") as f:
        txt = f.read()
    if "(footprints not_allowed)" in txt:
        with open(OUT, "w", encoding="utf-8") as f:
            f.write(txt.replace("(footprints not_allowed)", "(footprints allowed)"))

    # pcbnew rewrites the project file on save; enforce the routing rules again
    import json
    pro_path = OUT[:-len(".kicad_pcb")] + ".kicad_pro"
    with open(pro_path, encoding="utf-8") as f:
        pro = json.load(f)
    rules = pro["board"]["design_settings"]["rules"]
    rules["min_clearance"] = 0.15
    rules["min_copper_edge_clearance"] = 0.2
    rules["min_hole_clearance"] = 0.2
    for nc in pro.get("net_settings", {}).get("classes", []):
        if nc.get("name") == "Default":
            nc["clearance"] = 0.15
            nc["track_width"] = 0.25
            nc["via_diameter"] = 0.6
            nc["via_drill"] = 0.3
    with open(pro_path, "w", encoding="utf-8") as f:
        json.dump(pro, f, indent=2)

    print("tracks", len(b.GetTracks()), "zones", len(b.Zones()),
          "size", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
