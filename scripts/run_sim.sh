#!/usr/bin/env bash
# Runs all our simulations in one go.
#   - makes fresh test vectors with the Python model
#   - runs the MAC and PE unit tests
#   - runs the full matrix test for N = 3, 4, 8, on both the systolic
#     array and the sequential baseline
# Logs go to sim/logs/, waveforms (.vcd, open them in GTKWave) go to sim/waves/
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build sim/logs sim/waves
PY=${PY:-python3}
[ -x .venv/bin/python ] && PY=.venv/bin/python

$PY model/gen_vectors.py 3 4 8
# how many tests the generator made (each test has 16 results for N=4)
NT=$(($(wc -l < sim/vectors/N4_c.hex) / 16))

RTL="rtl/mac_unit.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v rtl/output_buffer.v rtl/systolic_controller.v rtl/systolic_top.v rtl/seq_matmul.v"

# compile one testbench and run it. usage: run <name> <top module> [extra iverilog flags]
run () {
  local name=$1 top=$2; shift 2
  iverilog -g2012 -Wall -Wno-timescale -s "$top" -o "sim/build/$name.vvp" "$@" $RTL "tb/$top.v"
  vvp -n "sim/build/$name.vvp" | tee "sim/logs/$name.log"
}

run mac      tb_mac_unit
run pe       tb_pe
# -DSEQ switches the matrix testbench over to the baseline design
for N in 3 4 8; do
  run systolic_N$N tb_matmul -P tb_matmul.N=$N -P tb_matmul.NUM_TESTS=$NT
  run seq_N$N      tb_matmul -P tb_matmul.N=$N -P tb_matmul.NUM_TESTS=$NT -DSEQ
done

echo; echo "==== Summary ===="
grep -hE "ALL PASSED|FAILED" sim/logs/*.log
