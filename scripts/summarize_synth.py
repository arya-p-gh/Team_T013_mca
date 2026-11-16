#!/usr/bin/env python3
"""
Reads the raw Yosys and nextpnr reports and puts the useful numbers into one
table (synth/summary.md). It also writes synth/summary.json, which
make_figures.py uses for the plots.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REP = os.path.join(ROOT, "synth", "reports")


# pull LUT / FF / DSP counts out of the Yosys "stat" output
def xc7(tag):
    path = os.path.join(REP, tag + "_xc7_stat.txt")
    if not os.path.exists(path):
        return None
    cells = {}
    for line in open(path):
        m = re.match(r"\s+(\d+)\s+(\w+)\s*$", line)
        if m:
            cells[m.group(2)] = cells.get(m.group(2), 0) + int(m.group(1))
    lut = sum(v for k, v in cells.items() if re.fullmatch(r"LUT\d", k))
    ff = sum(v for k, v in cells.items() if re.fullmatch(r"FD[A-Z]{2}", k))
    lutram = sum(v for k, v in cells.items() if k.startswith("RAM"))
    return {"LUT": lut, "FF": ff, "DSP48E1": cells.get("DSP48E1", 0),
            "CARRY4": cells.get("CARRY4", 0), "LUTRAM_cells": lutram}


# nextpnr writes a JSON report; grab Fmax and how many logic cells were used
def ice40(tag):
    path = os.path.join(REP, tag + "_ice40_pnr.json")
    if not os.path.exists(path):
        return None
    d = json.load(open(path))
    fmax = list(d["fmax"].values())[0]["achieved"]
    u = d["utilization"]
    return {"LC": u["ICESTORM_LC"]["used"], "LC_avail": u["ICESTORM_LC"]["available"],
            "IO": u["SB_IO"]["used"], "Fmax_MHz": round(fmax, 2)}


def cycles(top, n):
    # start->done cycle counts. These formulas match what the testbench
    # measured (14 and 67 for N=4)
    return 3 * n + 2 if top == "systolic_top" else n ** 3 + 3


def main():
    rows = []
    for top in ("systolic_top", "seq_matmul"):
        for n in (2, 3, 4, 8):
            tag = "%s_N%d" % (top, n)
            r = {"design": top, "N": n, "xc7": xc7(tag), "ice40": ice40(tag),
                 "cycles": cycles(top, n)}
            rows.append(r)
    json.dump(rows, open(os.path.join(ROOT, "synth", "summary.json"), "w"), indent=2)

    out = ["# Synthesis summary", "",
           "Xilinx 7-series numbers: Yosys `synth_xilinx -family xc7` (pre-place, estimate).",
           "iCE40 numbers: Yosys `synth_ice40` + nextpnr-ice40, HX8K-CT256, post-route.", "",
           "| Design | N | LUTs | FF | DSP48E1 | CARRY4 | iCE40 LCs | iCE40 Fmax (MHz) | Latency (cyc) | Time @Fmax (ns) |",
           "|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        x, i = r["xc7"] or {}, r["ice40"]
        lc = "%d / %d" % (i["LC"], i["LC_avail"]) if i else "-"
        fm = "%.1f" % i["Fmax_MHz"] if i else "-"
        tns = "%.0f" % (r["cycles"] * 1000.0 / i["Fmax_MHz"]) if i else "-"
        out.append("| %s | %d | %s | %s | %s | %s | %s | %s | %d | %s |" % (
            r["design"], r["N"], x.get("LUT", "-"), x.get("FF", "-"), x.get("DSP48E1", "-"),
            x.get("CARRY4", "-"), lc, fm, r["cycles"], tns))
    open(os.path.join(ROOT, "synth", "summary.md"), "w").write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
