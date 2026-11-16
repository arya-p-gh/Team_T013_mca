#!/usr/bin/env bash
# Synthesis using free tools (no Vivado needed).
#   1. Yosys maps the design to a Xilinx Artix-7. This gives LUT/FF/DSP counts,
#      but no timing, since Yosys can't place and route Xilinx parts.
#   2. Yosys + nextpnr do the full place & route on a Lattice iCE40-HX8K.
#      This gives us a real max clock frequency (Fmax).
# Everything ends up in synth/reports/. For proper Artix-7 timing, run
# synth/vivado_synth.tcl in the lab.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p synth/reports synth/build
RTL="rtl/mac_unit.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v rtl/output_buffer.v rtl/systolic_controller.v rtl/systolic_top.v rtl/seq_matmul.v"

# both designs, a few sizes each. N=8 is too big for the HX8K, so it's Xilinx only
for TOP in systolic_top seq_matmul; do
  for N in 2 3 4 8; do
    tag=${TOP}_N$N
    echo ">> $tag : Xilinx 7-series"
    yosys -q -l synth/reports/${tag}_xc7.log -p "
      read_verilog $RTL; chparam -set N $N $TOP; synth_xilinx -family xc7 -top $TOP -flatten;
      tee -o synth/reports/${tag}_xc7_stat.txt stat" >/dev/null
    if [ "$N" -le 4 ]; then
      echo ">> $tag : iCE40-HX8K place & route"
      yosys -q -l synth/reports/${tag}_ice40.log -p "
        read_verilog $RTL; chparam -set N $N $TOP; synth_ice40 -top $TOP -json synth/build/${tag}.json" >/dev/null
      nextpnr-ice40 --hx8k --package ct256 --pcf-allow-unconstrained --freq 50 --seed 1 \
        --json synth/build/${tag}.json --report synth/reports/${tag}_ice40_pnr.json \
        -l synth/reports/${tag}_ice40_pnr.log >/dev/null 2>&1 || echo "   nextpnr failed for $tag"
    fi
  done
done
.venv/bin/python scripts/summarize_synth.py
