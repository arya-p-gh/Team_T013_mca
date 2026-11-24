#!/usr/bin/env bash
# Runs all our simulations in one go (the full regression).
#
#   Phase I  - MAC and PE unit tests
#            - full matrix test for N = 3, 4, 8 on the v1 systolic array
#              and on the sequential baseline
#   Phase II - MAC and PE unit tests again with the pipelined MAC (PIPE=1)
#            - input_buffer_v2 unit test (row writes, two banks, skew)
#            - systolic_top_v2 for N = 3, 4, 8: single jobs, streaming
#              (load + compute + read overlapped) and accumulate mode
#            - 200 extra random "stress" tests on v2 for N = 4 and 8
#            - tiled 8x8 and 12x12 multiplies on the 4x4 array
#            - the UART board path, end to end
#
# Logs go to sim/logs/, waveforms (.vcd, open in GTKWave or Surfer) go to
# sim/waves/. At the end it prints one line per test run and exits with an
# error if anything failed.
#
# Quick mode (skips the stress and UART runs, about 4x faster):
#   QUICK=1 ./scripts/run_sim.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build sim/logs sim/waves
rm -f sim/logs/*.log
PY=${PY:-python3}
[ -x .venv/bin/python ] && PY=.venv/bin/python
QUICK=${QUICK:-0}

# fresh vectors: normal sets for every size we use, stress sets for 4 and 8
$PY model/gen_vectors.py 3 4 8 12
[ "$QUICK" = 1 ] || $PY model/gen_vectors.py 4 8 --stress 200
# how many tests the generator made (each test has 16 results for N=4)
NT=$(($(wc -l < sim/vectors/N4_c.hex) / 16))
NS=200

CORE="rtl/mac_unit.v rtl/pe.v rtl/systolic_array.v"
V1="$CORE rtl/input_buffer.v rtl/output_buffer.v rtl/systolic_controller.v rtl/systolic_top.v rtl/seq_matmul.v"
V2="$CORE rtl/input_buffer_v2.v rtl/output_buffer_v2.v rtl/systolic_controller_v2.v rtl/systolic_top_v2.v rtl/tiled_matmul.v"
UART="$V1 rtl/uart_rx.v rtl/uart_tx.v rtl/uart_bridge.v"

# compile one testbench and run it.
# usage: run <log name> <top module> "<rtl files>" [extra iverilog flags / +plusargs after --]
run () {
  local name=$1 top=$2 files=$3; shift 3
  local flags=() plus=()
  while [ $# -gt 0 ]; do
    if [ "$1" = "--" ]; then shift; plus=("$@"); break; fi
    flags+=("$1"); shift
  done
  iverilog -g2012 -Wall -Wno-timescale -Wno-sensitivity-entire-array -s "$top" \
    -o "sim/build/$name.vvp" ${flags[@]+"${flags[@]}"} $files "tb/$top.v"
  vvp -n "sim/build/$name.vvp" ${plus[@]+"${plus[@]}"} | tee "sim/logs/$name.log"
}

echo "################ Phase I ################"
run mac      tb_mac_unit "rtl/mac_unit.v"
run pe       tb_pe       "rtl/mac_unit.v rtl/pe.v"
# -DSEQ switches the matrix testbench over to the baseline design
for N in 3 4 8; do
  run systolic_N$N tb_matmul "$V1" -P tb_matmul.N=$N -P tb_matmul.NUM_TESTS=$NT
  run seq_N$N      tb_matmul "$V1" -P tb_matmul.N=$N -P tb_matmul.NUM_TESTS=$NT -DSEQ
done

echo "################ Phase II ################"
run mac_pipe tb_mac_unit "rtl/mac_unit.v" -P tb_mac_unit.PIPE=1
run pe_pipe  tb_pe       "rtl/mac_unit.v rtl/pe.v" -P tb_pe.PIPE=1
run input_buffer_v2 tb_input_buffer_v2 "rtl/input_buffer_v2.v"
for N in 3 4 8; do
  run v2_N$N tb_matmul_v2 "$V2" -P tb_matmul_v2.N=$N -P tb_matmul_v2.NUM_TESTS=$NT
done
# v2 also has to work with the pipeline switched off
run v2_N4_nopipe tb_matmul_v2 "$V2" -P tb_matmul_v2.N=4 -P tb_matmul_v2.NUM_TESTS=$NT -P tb_matmul_v2.PIPE=0
for M in 8 12; do
  run tiled_M$M tb_tiled "$V2" -P tb_tiled.M=$M -P tb_tiled.NUM_TESTS=$NT
done
if [ "$QUICK" != 1 ]; then
  for N in 4 8; do
    run v2_N${N}_stress tb_matmul_v2 "$V2" -P tb_matmul_v2.N=$N -P tb_matmul_v2.NUM_TESTS=$NS -- +SET=_stress
  done
  run uart tb_uart "$UART" -P tb_uart.NUM_TESTS=$NT
fi

echo; echo "==== Summary ===="
grep -hE "ALL PASSED|FAILED|TIMEOUT" sim/logs/*.log
if grep -qE "FAILED|TIMEOUT|MISMATCH" sim/logs/*.log; then
  echo "!!! something failed, check the logs above"; exit 1
fi
echo "all $(ls sim/logs/*.log | wc -l | tr -d ' ') runs passed"
