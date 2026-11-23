#!/usr/bin/env python3
"""Autoroute and pour the V6 electrical board.

Flow: load -> set rules -> export Specctra DSN -> freerouting -> import SES
      -> add GND zones on all four copper layers -> fill -> save.

Requires: KiCad 9 python (pcbnew) and the freerouting CLI.
Output: DriveTrack-PCB-V6/drivetrack-pcb-v6-routed.kicad_pcb
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

import pcbnew

ROOT = "/workspace/drivetrack-v6-compact"
SRC = os.path.join(ROOT, "DriveTrack-PCB-V6", "drivetrack-pcb-v6-electrical.kicad_pcb")
OUT = os.path.join(ROOT, "DriveTrack-PCB-V6", "drivetrack-pcb-v6-routed.kicad_pcb")
WORK = "/workspace/.build-tools/route"
FR_JAR = "/workspace/.build-tools/fr.jar"

PASSES = sys.argv[1] if len(sys.argv) > 1 else "100"


def main():
    os.makedirs(WORK, exist_ok=True)
    dsn = os.path.join(WORK, "v6.dsn")
    ses = os.path.join(WORK, "v6.ses")

    board = pcbnew.LoadBoard(SRC)
    assert board is not None, "cannot load source board"

    ds = board.GetDesignSettings()
    nc = ds.m_NetSettings.GetDefaultNetclass()
    nc.SetTrackWidth(pcbnew.FromMM(0.25))
    nc.SetClearance(pcbnew.FromMM(0.15))
    nc.SetViaDiameter(pcbnew.FromMM(0.6))
    nc.SetViaDrill(pcbnew.FromMM(0.3))
    ds.m_TrackMinWidth = pcbnew.FromMM(0.15)
    ds.m_CopperEdgeClearance = pcbnew.FromMM(0.30)
    ds.m_HoleClearance = pcbnew.FromMM(0.20)
    ds.m_MinClearance = pcbnew.FromMM(0.15)
    ds.m_ViasMinSize = pcbnew.FromMM(0.5)
    ds.m_MinThroughDrill = pcbnew.FromMM(0.25)

    for layer in (pcbnew.F_Cu, pcbnew.In1_Cu, pcbnew.In2_Cu, pcbnew.B_Cu):
        board.SetLayerType(layer, pcbnew.LT_SIGNAL)

    pcbnew.ExportSpecctraDSN(board, dsn)
    print("dsn", os.path.getsize(dsn), "bytes")

    t0 = time.time()
    cmd = ["java", "-Xmx2g", "-Djava.awt.headless=true", "-jar", FR_JAR,
           "-de", dsn, "-do", ses, "-mp", PASSES, "-mt", "2", "-l", "en"]
    print("running", " ".join(cmd))
    log = os.path.join(WORK, "freerouting.log")
    with open(log, "w") as f:
        rc = subprocess.call(cmd, stdout=f, stderr=subprocess.STDOUT)
    print(f"freerouting rc={rc} elapsed={time.time()-t0:.0f}s")
    with open(log) as f:
        tail = f.read().splitlines()[-12:]
    print("\n".join(tail))
    assert os.path.exists(ses), "no SES produced"

    # fresh board so the import starts from the unrouted copper state
    board = pcbnew.LoadBoard(SRC)
    nc = board.GetDesignSettings().m_NetSettings.GetDefaultNetclass()
    nc.SetTrackWidth(pcbnew.FromMM(0.25))
    nc.SetClearance(pcbnew.FromMM(0.15))
    nc.SetViaDiameter(pcbnew.FromMM(0.6))
    nc.SetViaDrill(pcbnew.FromMM(0.3))
    pcbnew.ImportSpecctraSES(board, ses)

    gnd = board.FindNet("GND")
    assert gnd is not None
    x0, y0 = pcbnew.FromMM(0.6), pcbnew.FromMM(0.6)
    x1, y1 = pcbnew.FromMM(61.4), pcbnew.FromMM(61.4)
    for layer in (pcbnew.F_Cu, pcbnew.In1_Cu, pcbnew.In2_Cu, pcbnew.B_Cu):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNetCode(gnd.GetNetCode())
        z.SetLocalClearance(pcbnew.FromMM(0.3))
        z.SetMinThickness(pcbnew.FromMM(0.25))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
        z.SetThermalReliefGap(pcbnew.FromMM(0.3))
        z.SetThermalReliefSpokeWidth(pcbnew.FromMM(0.5))
        z.SetIsFilled(False)
        poly = z.Outline()
        poly.NewOutline()
        for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
            poly.Append(x, y)
        board.Add(z)
    print("zones", len(board.Zones()))

    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    pcbnew.SaveBoard(OUT, board)

    # the Espressif module embeds an antenna keep-out that forbids footprints;
    # the GPS patch is a separate part, so allow footprints and keep copper out
    text = open(OUT, encoding="utf-8").read()
    text = text.replace("(footprints not_allowed)", "(footprints allowed)")
    open(OUT, "w", encoding="utf-8").write(text)

    tracks = [t for t in board.GetTracks() if t.Type() == pcbnew.PCB_TRACE_T]
    vias = [t for t in board.GetTracks() if t.Type() == pcbnew.PCB_VIA_T]
    print(f"tracks {len(tracks)}  vias {len(vias)}  size {os.path.getsize(OUT)}")


if __name__ == "__main__":
    main()
