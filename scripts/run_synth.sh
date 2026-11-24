#!/usr/bin/env bash
# Synthesis using free tools (no Vivado needed).
#   1. Yosys maps each design to a Xilinx Artix-7. This gives LUT/FF/DSP counts,
#      but no timing, since Yosys can't place and route Xilinx parts.
#   2. Yosys + nextpnr do the full place & route on a Lattice iCE40-HX8K.
#      This gives us a real max clock frequency (Fmax). The HX8K has no hard
#      multipliers, so multipliers turn into plain logic there.
# Everything ends up in synth/reports/, and the numbers are collected into
# synth/summary.md at the end. For real Artix-7 timing, run
# synth/vivado_synth.tcl or synth/vivado_board.tcl in the lab.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p synth/reports synth/build
PY=${PY:-python3}
[ -x .venv/bin/python ] && PY=.venv/bin/python

RTL="rtl/mac_unit.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v rtl/output_buffer.v
     rtl/systolic_controller.v rtl/systolic_top.v rtl/seq_matmul.v
     rtl/input_buffer_v2.v rtl/output_buffer_v2.v rtl/systolic_controller_v2.v rtl/systolic_top_v2.v
     rtl/tiled_matmul.v rtl/uart_rx.v rtl/uart_tx.v rtl/uart_bridge.v rtl/basys3_top.v"
RTL=$(echo $RTL)

# tag | top module | parameters | also place & route on iCE40?
# (tiled_M8 needs ~123% of the HX8K: no hard multipliers there, and the big
#  matrices end up in logic cells, so it's Artix-7 only)
DESIGNS="
v1_N2|systolic_top|-set N 2|yes
v1_N3|systolic_top|-set N 3|yes
v1_N4|systolic_top|-set N 4|yes
v1_N8|systolic_top|-set N 8|no
seq_N2|seq_matmul|-set N 2|yes
seq_N3|seq_matmul|-set N 3|yes
seq_N4|seq_matmul|-set N 4|yes
seq_N8|seq_matmul|-set N 8|no
v2_N4_nopipe|systolic_top_v2|-set N 4 -set PIPE 0|yes
v2_N4|systolic_top_v2|-set N 4 -set PIPE 1|yes
v2_N8|systolic_top_v2|-set N 8 -set PIPE 1|no
tiled_M8|tiled_matmul|-set M 8 -set N 4|no
board|basys3_top||no
"

echo "$DESIGNS" | while IFS='|' read -r tag top params pnr; do
  [ -z "$tag" ] && continue
  chp=""
  [ -n "$params" ] && chp="chparam $params $top;"
  echo ">> $tag ($top $params): Xilinx 7-series"
  yosys -q -l synth/reports/${tag}_xc7.log -p "
    read_verilog $RTL; $chp synth_xilinx -family xc7 -top $top -flatten;
    tee -o synth/reports/${tag}_xc7_stat.txt stat" >/dev/null || echo "   yosys failed for $tag"
  if [ "$pnr" = yes ]; then
    echo ">> $tag: iCE40-HX8K place & route"
    yosys -q -l synth/reports/${tag}_ice40.log -p "
      read_verilog $RTL; $chp synth_ice40 -top $top -json synth/build/${tag}.json" >/dev/null
    nextpnr-ice40 --hx8k --package ct256 --pcf-allow-unconstrained --freq 50 --seed 1 \
      --json synth/build/${tag}.json --report synth/reports/${tag}_ice40_pnr.json \
      -l synth/reports/${tag}_ice40_pnr.log >/dev/null 2>&1 || echo "   nextpnr failed for $tag (doesn't fit / no route)"
  fi
done

# collect everything into one table
$PY - <<'EOF'
import json, os, re
order = ["v1_N2", "v1_N3", "v1_N4", "v1_N8", "seq_N2", "seq_N3", "seq_N4", "seq_N8",
         "v2_N4_nopipe", "v2_N4", "v2_N8", "tiled_M8", "board"]
rows = []
for tag in order:
    stat = "synth/reports/%s_xc7_stat.txt" % tag
    if not os.path.exists(stat):
        continue
    cells = {}
    for line in open(stat):
        m = re.match(r"\s+(\d+)\s+(\w+)\s*$", line)
        if m:
            cells[m.group(2)] = cells.get(m.group(2), 0) + int(m.group(1))
    lut = sum(v for k, v in cells.items() if re.fullmatch(r"LUT\d", k))
    ff = sum(v for k, v in cells.items() if re.fullmatch(r"FD[A-Z]{2}", k))
    ram = sum(v for k, v in cells.items() if k.startswith("RAM"))
    bram = sum(v for k, v in cells.items() if k.startswith("RAMB"))
    lc = fmax = "-"
    pj = "synth/reports/%s_ice40_pnr.json" % tag
    if os.path.exists(pj):
        d = json.load(open(pj))
        lc = "%d / %d" % (d["utilization"]["ICESTORM_LC"]["used"], d["utilization"]["ICESTORM_LC"]["available"])
        fmax = "%.1f" % list(d["fmax"].values())[0]["achieved"]
    rows.append((tag, lut, ff, cells.get("DSP48E1", 0), ram - bram, bram, lc, fmax))
out = ["# Synthesis summary", "",
       "Artix-7: Yosys `synth_xilinx` (before placement, estimate).",
       "iCE40: Yosys + nextpnr on an HX8K, after place & route (real Fmax).", "",
       "| Design | LUTs | FFs | DSP48E1 | LUTRAM | BRAM | iCE40 LCs | iCE40 Fmax (MHz) |",
       "|---|---|---|---|---|---|---|---|"]
for r in rows:
    out.append("| %s | %d | %d | %d | %d | %d | %s | %s |" % r)
out += ["", "v1 = Phase I design, seq = sequential baseline, v2 = Phase II design (row I/O, double",
        "buffering, pipelined MAC unless _nopipe), tiled_M8 = 8x8 matrices on the 4x4 v2 array,",
        "board = basys3_top (v1 4x4 array + UART bridge)."]
open("synth/summary.md", "w").write("\n".join(out) + "\n")
print("\n".join(out))
EOF
