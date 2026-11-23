#!/usr/bin/env python3
"""DriveTrack V6 electrical design source of truth.

Every component, its real package, and the net on every pin.
Generators (netlist CSV, KiCad schematic, KiCad PCB) import this file.

Pinouts verified against vendor datasheets / official symbol libraries:
  BQ24074     TI SLUS810N  (VQFN-16 3x3, EP 1.6x1.6)
  TPS63802    TI SLVSEU9D  (VSON-10 DLA, 3.0x2.0, 0.5 pitch, no EP)
  TPS7A2033   TI DBV SOT-23-5
  TPS7A0230   TI DQN X2SON-4 1x1, 0.65 pitch
  LIS2DW12    ST DS11811   (LGA-12 2x2, 0.5 pitch)
  ESP32-S3-MINI-1U  Espressif kicad-libraries symbol (65 pads)
  NEO-M9N / BMI088 / BMP390 / USB-C / ESD / SK6812 carry over from V5.
"""
from __future__ import annotations

from dataclasses import dataclass, field

GND = "GND"
V33 = "+3V3"


@dataclass
class Part:
    ref: str
    value: str
    fp: str
    pins: list[tuple[str, str, str]] = field(default_factory=list)  # (num, name, net)
    note: str = ""


PARTS: list[Part] = []


def P(ref, value, fp, pins, note=""):
    PARTS.append(Part(ref, value, fp, pins, note))


# ---------------------------------------------------------------- power chain
P("U5", "BQ24074", "Package_DFN_QFN:VQFN-16-1EP_3x3mm_P0.5mm_EP1.6x1.6mm", [
    ("1", "TS", "TS"),
    ("2", "BAT", "BAT"),
    ("3", "BAT", "BAT"),
    ("4", "CE", GND),
    ("5", "EN2", GND),
    ("6", "EN1", V33),
    ("7", "PGOOD", "PGOOD"),
    ("8", "VSS", GND),
    ("9", "CHG", "CHG_STAT"),
    ("10", "OUT", "VSYS"),
    ("11", "OUT", "VSYS"),
    ("12", "ILIM", "ILIM"),
    ("13", "IN", "VBUS"),
    ("14", "TMR", "TMR"),
    ("15", "SYSOFF", GND),
    ("16", "ISET", "ISET"),
    ("17", "EP", GND),
], "power-path charger, 500 mA input (EN1=1/EN2=0)")

P("U6", "TPS63802", "DriveTrack:VSON-10-3x2mm_P0.5mm_TPS63802", [
    ("1", "EN", "VLOAD"),
    ("2", "MODE", GND),
    ("3", "AGND", GND),
    ("4", "FB", "FB_3V3"),
    ("5", "PG", ""),
    ("6", "VOUT", V33),
    ("7", "L2", "SW_L2"),
    ("8", "GND", GND),
    ("9", "L1", "SW_L1"),
    ("10", "VIN", "VLOAD"),
], "3.3 V / 2 A buck-boost, 0.47 uH")

P("U7", "TPS7A2033", "Package_TO_SOT_SMD:SOT-23-5", [
    ("1", "IN", V33),
    ("2", "GND", GND),
    ("3", "EN", V33),
    ("4", "NC", ""),
    ("5", "OUT", "GPS_VCC"),
], "low-noise 3.3 V LDO for GNSS")

P("U8", "TPS7A0230", "Package_SON:Texas_X2SON-4_1x1mm_P0.65mm", [
    ("1", "OUT", "V_AON"),
    ("2", "GND", GND),
    ("3", "EN", "VSYS"),
    ("4", "IN", "VSYS"),
], "always-on 3.0 V / 25 nA for motion wake + GNSS backup")

P("U9", "LIS2DW12", "Package_LGA:LGA-12_2x2mm_P0.5mm", [
    ("1", "SCL/SPC", "BARO_SCL"),
    ("2", "CS", "V_AON"),
    ("3", "SDO/SA0", GND),
    ("4", "SDA/SDI", "BARO_SDA"),
    ("5", "NC", ""),
    ("6", "GND", GND),
    ("7", "RES", GND),
    ("8", "GND", GND),
    ("9", "VDD", "V_AON"),
    ("10", "VDD_IO", "V_AON"),
    ("11", "INT2", ""),
    ("12", "INT1", "MOTION_INT"),
], "1.6 uA motion wake; I2C address 0x18 (SA0 low)")

P("L1", "0.47uH", "DriveTrack:L_4x4_H2", [
    ("1", "1", "SW_L1"),
    ("2", "2", "SW_L2"),
], "buck-boost inductor 4x4x2")

P("Q1", "AO3401", "Package_TO_SOT_SMD:SOT-23", [
    ("1", "G", "LATCH_G"),
    ("2", "S", "VSYS"),
    ("3", "D", "VLOAD"),
], "P-MOS high-side latch, source to VSYS")

P("Q2", "BSS138", "Package_TO_SOT_SMD:SOT-23", [
    ("1", "G", "WAKE_G"),
    ("2", "S", GND),
    ("3", "D", "LATCH_G"),
], "wake OR gate: USB present or motion")

P("Q3", "BSS138", "Package_TO_SOT_SMD:SOT-23", [
    ("1", "G", "PWR_HOLD"),
    ("2", "S", GND),
    ("3", "D", "LATCH_G"),
], "firmware hold, 100k pulldown keeps it off during boot")

P("D4", "1N4148W", "Diode_SMD:D_SOD-323", [
    ("1", "A", "WAKE_USB"),
    ("2", "K", "WAKE_G"),
], "diode-OR from USB detect")

P("D5", "1N4148W", "Diode_SMD:D_SOD-323", [
    ("1", "A", "MOTION_INT"),
    ("2", "K", "WAKE_G"),
], "diode-OR from motion interrupt")

# ---------------------------------------------------------------- MCU / RF
_esp = []
_esp += [("1", "GND", GND), ("2", "GND", GND), ("3", "3V3", V33)]
_esp += [("4", "GPIO0", "BOOT"), ("5", "GPIO1", "VBAT_DIV"),
         ("6", "GPIO2", ""), ("7", "GPIO3", ""), ("8", "GPIO4", "GPS_PPS"),
         ("9", "GPIO5", "IMU_INT1"), ("10", "GPIO6", "IMU_INT3"),
         ("11", "GPIO7", "CHG_STAT"), ("12", "GPIO8", "BARO_SDA"),
         ("13", "GPIO9", "BARO_SCL"), ("14", "GPIO10", "IMU_CS1"),
         ("15", "GPIO11", "IMU_CS2"), ("16", "GPIO12", ""),
         ("17", "GPIO13", ""), ("18", "GPIO14", "IMU_SCK"),
         ("19", "GPIO15", "IMU_MOSI"), ("20", "GPIO16", "IMU_MISO"),
         ("21", "GPIO17", "GPS_TX"), ("22", "GPIO18", "GPS_RX"),
         ("23", "GPIO19", "USB_DM"), ("24", "GPIO20", "USB_DP"),
         ("25", "GPIO21", "PGOOD"), ("26", "GPIO26", ""),
         ("27", "GPIO47", ""), ("28", "GPIO33", ""), ("29", "GPIO34", ""),
         ("30", "GPIO48", "RGB_DIN"), ("31", "GPIO35", ""), ("32", "GPIO36", ""),
         ("33", "GPIO37", ""), ("34", "GPIO38", ""), ("35", "GPIO39", ""),
         ("36", "GPIO40", ""), ("37", "GPIO41", "PWR_HOLD"), ("38", "GPIO42", "WAKE_USB"),
         ("39", "GPIO43", "UART0_TX"), ("40", "GPIO44", "UART0_RX"),
         ("41", "GPIO45", ""), ("42", "GND", GND), ("43", "GND", GND),
         ("44", "GPIO46", ""), ("45", "EN", "EN")]
_esp += [(str(n), "GND", GND) for n in range(46, 66)]
P("U1", "ESP32-S3-MINI-1U-N8R2", "Espressif:ESP32-S3-MINI-1", _esp,
  "module, 65 pads; GPIO26-37 reserved for in-package flash/PSRAM")

P("J4", "Factory pogo 6P", "DriveTrack:Pogo_6_1.5mm", [
    ("1", "3V3", V33), ("2", "GND", GND), ("3", "EN", "EN"),
    ("4", "BOOT", "BOOT"), ("5", "TX", "UART0_TX"), ("6", "RX", "UART0_RX"),
], "1.5 mm pads, no connector; factory flashing only")

P("U2", "NEO-M9N", "RF_GPS:ublox_NEO", [
    ("1", "SAFEBOOT_N", "M9N_SAFEBOOT"),
    ("2", "D_SEL", ""),
    ("3", "TIMEPULSE", "GPS_PPS"),
    ("4", "EXTINT", ""),
    ("5", "USB_DM", ""),
    ("6", "USB_DP", ""),
    ("7", "VDD_USB", GND),
    ("8", "RESET_N", "M9N_RESET"),
    ("9", "VCC_RF", "VCC_RF"),
    ("10", "GND", GND),
    ("11", "RF_IN", "GPS_RF"),
    ("12", "GND", GND),
    ("13", "GND", GND),
    ("14", "LNA_EN", ""),
    ("15", "RESERVED", ""),
    ("16", "RESERVED", ""),
    ("17", "RESERVED", ""),
    ("18", "SDA", ""),
    ("19", "SCL", ""),
    ("20", "TXD", "GPS_TX"),
    ("21", "RXD", "GPS_RX"),
    ("22", "V_BCKP", "V_AON"),
    ("23", "VCC", "GPS_VCC"),
    ("24", "GND", GND),
], "V_BCKP moved to always-on 3.0 V rail")

P("ANT1", "25x25 patch", "DriveTrack:GPS_Patch_25x25", [
    ("1", "FEED", "GPS_RF"),
], "single feed pin; patch ground bonded to the ground plane")

# ---------------------------------------------------------------- sensors
P("U3", "BMI088", "DriveTrack:BMI088_LGA-16_3.0x4.5mm", [
    ("1", "INT2", ""), ("2", "NC", ""), ("3", "VDD", V33), ("4", "GND", GND),
    ("5", "CSB2", "IMU_CS2"), ("6", "GND", GND), ("7", "GND", GND),
    ("8", "SCK", "IMU_SCK"), ("9", "SDI", "IMU_MOSI"), ("10", "SDO", "IMU_MISO"),
    ("11", "VDDIO", V33), ("12", "INT3", "IMU_INT3"), ("13", "INT4", ""),
    ("14", "CSB1", "IMU_CS1"), ("15", "SDO2", "IMU_MISO"), ("16", "INT1", "IMU_INT1"),
])

P("U4", "BMP390", "DriveTrack:BMP390_LGA-10_2.0x2.0mm", [
    ("1", "VDD", V33), ("2", "SCL", "BARO_SCL"), ("3", "GND", GND),
    ("4", "SDA", "BARO_SDA"), ("5", "VDDIO", V33), ("6", "VDD2", V33),
    ("7", "INT", ""), ("8", "GND", GND), ("9", "GND", GND), ("10", "VDDIO2", V33),
])

# ---------------------------------------------------------------- USB / UI
P("J2", "USB-C 16P", "Connector_USB:USB_C_Receptacle_Amphenol_12401610E4-2A", [
    ("A1", "GND", GND), ("A4", "VBUS", "VBUS"), ("A5", "CC1", "USB_CC1"),
    ("A6", "DP1", "USB_DP"), ("A7", "DN1", "USB_DM"), ("A8", "SBU1", ""),
    ("A9", "VBUS", "VBUS"), ("A12", "GND", GND),
    ("B1", "GND", GND), ("B4", "VBUS", "VBUS"), ("B5", "CC2", "USB_CC2"),
    ("B6", "DP2", "USB_DP"), ("B7", "DN2", "USB_DM"), ("B8", "SBU2", ""),
    ("B9", "VBUS", "VBUS"), ("B12", "GND", GND), ("S1", "SHIELD", "USB_SHIELD"),
], "mid-mount; CC resistors 5.1k")

P("D1", "ESD9B5.0ST5G", "Diode_SMD:D_SOD-923", [("1", "C", "VBUS"), ("2", "A", GND)])
P("D2", "ESD9B3.3ST5G", "Diode_SMD:D_SOD-923", [("1", "C", "USB_DP"), ("2", "A", GND)])
P("D3", "ESD9B3.3ST5G", "Diode_SMD:D_SOD-923", [("1", "C", "USB_DM"), ("2", "A", GND)])

P("LED1", "SK6812MINI", "LED_SMD:LED_SK6812MINI_PLCC4_3.5x3.5mm_P1.75mm", [
    ("1", "DOUT", ""), ("2", "VSS", GND), ("3", "DIN", "LED_DIN"), ("4", "VDD", "VLOAD"),
], "powered from switched VLOAD, 3.4-4.2 V")

P("J3", "JST-SH 2P", "Connector_JST:JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal", [
    ("1", "BAT+", "BAT"), ("2", "BAT-", GND),
], "opening south, cable notch at board edge")

# ---------------------------------------------------------------- decoupling
P("C1", "10u", "Capacitor_SMD:C_0805_2012Metric", [("1", "1", "VBUS"), ("2", "2", GND)])
P("C2", "1u", "Capacitor_SMD:C_0603_1608Metric", [("1", "1", "VBUS"), ("2", "2", GND)])
P("C3", "4.7u", "Capacitor_SMD:C_0805_2012Metric", [("1", "1", "BAT"), ("2", "2", GND)])
P("C4", "10u", "Capacitor_SMD:C_0805_2012Metric", [("1", "1", "VSYS"), ("2", "2", GND)])
P("C5", "22u", "Capacitor_SMD:C_0805_2012Metric", [("1", "1", "VLOAD"), ("2", "2", GND)])
P("C6", "22u", "Capacitor_SMD:C_0805_2012Metric", [("1", "1", V33), ("2", "2", GND)])
P("C7", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", V33), ("2", "2", GND)])
P("C8", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "VCC_RF"), ("2", "2", GND)])
P("C9", "1u", "Capacitor_SMD:C_0603_1608Metric", [("1", "1", "GPS_VCC"), ("2", "2", GND)])
P("C10", "1u", "Capacitor_SMD:C_0603_1608Metric", [("1", "1", V33), ("2", "2", GND)])
P("C11", "1u", "Capacitor_SMD:C_0603_1608Metric", [("1", "1", "V_AON"), ("2", "2", GND)])
P("C12", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "V_AON"), ("2", "2", GND)])
P("C13", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", V33), ("2", "2", GND)])
P("C14", "10u", "Capacitor_SMD:C_0805_2012Metric", [("1", "1", V33), ("2", "2", GND)])
P("C15", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "GPS_VCC"), ("2", "2", GND)])
P("C16", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", V33), ("2", "2", GND)])
P("C17", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", V33), ("2", "2", GND)])
P("C18", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "V_AON"), ("2", "2", GND)])
P("C19", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "VLOAD"), ("2", "2", GND)])
P("C20", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "VSYS"), ("2", "2", GND)])
P("C21", "1u", "Capacitor_SMD:C_0603_1608Metric", [("1", "1", "EN"), ("2", "2", GND)])
P("C22", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "WAKE_USB"), ("2", "2", GND)])
P("C23", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "VBAT_DIV"), ("2", "2", GND)])
P("C24", "100n", "Capacitor_SMD:C_0402_1005Metric", [("1", "1", "USB_SHIELD"), ("2", "2", GND)])

# ---------------------------------------------------------------- resistors
P("R1", "3.09k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "ILIM"), ("2", "2", GND)])
P("R2", "1.78k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "ISET"), ("2", "2", GND)])
P("R3", "10k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "TS"), ("2", "2", GND)])
P("R4", "47k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "TMR"), ("2", "2", GND)])
P("R5", "100k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "PGOOD"), ("2", "2", V33)])
P("R6", "10k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "CHG_STAT"), ("2", "2", V33)])
P("R7", "100k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "VSYS"), ("2", "2", "LATCH_G")])
P("R9", "100k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "PWR_HOLD"), ("2", "2", GND)])
P("R10", "100k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "FB_3V3"), ("2", "2", GND)])
P("R11", "560k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", V33), ("2", "2", "FB_3V3")])
P("R12", "100k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "VBUS"), ("2", "2", "WAKE_USB")])
P("R13", "150k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "WAKE_USB"), ("2", "2", GND)])
P("R14", "100k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "WAKE_G"), ("2", "2", GND)])
P("R15", "4.7k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", V33), ("2", "2", "BARO_SCL")])
P("R16", "4.7k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", V33), ("2", "2", "BARO_SDA")])
P("R17", "10k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", V33), ("2", "2", "EN")])
P("R18", "10k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", V33), ("2", "2", "BOOT")])
P("R19", "1M", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "BAT"), ("2", "2", "VBAT_DIV")])
P("R20", "1M", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "VBAT_DIV"), ("2", "2", GND)])
P("R21", "330R", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "RGB_DIN"), ("2", "2", "LED_DIN")])
P("R22", "5.1k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "USB_CC1"), ("2", "2", GND)])
P("R23", "5.1k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "USB_CC2"), ("2", "2", GND)])
P("R24", "10k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "GPS_VCC"), ("2", "2", "M9N_RESET")])
P("R25", "10k", "Resistor_SMD:R_0402_1005Metric", [("1", "1", "GPS_VCC"), ("2", "2", "M9N_SAFEBOOT")])

# ---------------------------------------------------------------- mechanical
for i, (x, y) in enumerate([(30, 3), (54, 3), (30, 59), (54, 59)], start=1):
    P(f"MH{i}", "M2 NPTH", "MountingHole:MountingHole_2.2mm", [], "no pads")

# ---------------------------------------------------------------- placement
# Board coordinates, Y positive downwards, origin top-left (same as V6 board).
PLACE = {
    "U1": (45.0, 14.5, 0), "U2": (13.5, 34.0, -90), "U3": (7.5, 50.0, 0),
    "U4": (3.5, 45.0, 0), "U5": (42.0, 46.0, 0), "U6": (48.0, 46.0, 0),
    "U7": (36.0, 46.0, 0), "U8": (36.5, 48.6, 0), "U9": (40.0, 51.5, 0),
    "L1": (53.0, 45.5, 0), "Q1": (44.2, 51.5, 0), "Q2": (48.4, 51.5, 0),
    "Q3": (52.6, 51.5, 0), "D4": (45.0, 55.0, 0), "D5": (48.0, 55.0, 0),
    "LED1": (56.0, 8.0, 0), "J2": (31.0, 56.6, 0), "J3": (58.5, 49.0, 180),
    "J4": (12.0, 60.0, 0), "ANT1": (13.5, 13.0, 0),
    "D1": (26.5, 49.5, 0), "D2": (29.0, 49.5, 0), "D3": (31.5, 49.5, 0),
    "MH1": (30.0, 3.0, 0), "MH2": (54.0, 3.0, 0), "MH3": (21.5, 59.0, 0),
    "MH4": (54.0, 59.0, 0),
}

# bounding box (w, h) in mm used by the auto-placer for the fixed parts.
# Values are the real courtyard extents measured from the placed footprints,
# not the package body, so neighbours never collide.
SIZE = {
    "U1": (16.0, 21.1), "U2": (14.3, 16.5), "U3": (5.0, 3.5), "U4": (2.5, 2.5),
    "U5": (4.3, 4.3), "U6": (3.1, 3.3), "U7": (4.1, 3.4), "U8": (1.8, 1.5),
    "U9": (2.5, 2.5), "L1": (4.8, 4.8), "Q1": (3.9, 3.4), "Q2": (3.9, 3.4),
    "Q3": (3.9, 3.4), "D4": (2.5, 2.1), "D5": (2.5, 2.1),
    "LED1": (5.6, 4.0), "J2": (10.8, 11.6), "J3": (5.8, 6.6), "J4": (12.0, 3.2),
    "ANT1": (25.6, 25.6), "D1": (1.5, 0.9), "D2": (1.5, 0.9), "D3": (1.5, 0.9),
    "MH1": (4.6, 4.6), "MH2": (4.6, 4.6), "MH3": (4.6, 4.6), "MH4": (4.6, 4.6),
}


def part(ref):
    for p in PARTS:
        if p.ref == ref:
            return p
    raise KeyError(ref)


def nets():
    """net name -> [(ref, pin)]"""
    out: dict[str, list[tuple[str, str]]] = {}
    for p in PARTS:
        for num, _name, net in p.pins:
            if net:
                out.setdefault(net, []).append((p.ref, num))
    return out


def check() -> list[str]:
    issues = []
    for name, nodes in nets().items():
        if len(nodes) < 2 and not name.startswith("unconnected"):
            issues.append(f"single-node net {name}: {nodes}")
    refs = [p.ref for p in PARTS]
    if len(refs) != len(set(refs)):
        issues.append("duplicate reference")
    for p in PARTS:
        nums = [n for n, _, _ in p.pins]
        if len(nums) != len(set(nums)):
            issues.append(f"{p.ref}: duplicate pin number")
    return issues


if __name__ == "__main__":
    print(f"parts: {len(PARTS)}  nets: {len(nets())}")
    for msg in check():
        print("ISSUE:", msg)
    for name, nodes in sorted(nets().items(), key=lambda kv: -len(kv[1])):
        print(f"{name:16s} {len(nodes):3d}  " + " ".join(f"{r}.{p}" for r, p in nodes))
