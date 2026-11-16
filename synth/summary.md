# Synthesis summary

Xilinx 7-series numbers: Yosys `synth_xilinx -family xc7` (pre-place, estimate).
iCE40 numbers: Yosys `synth_ice40` + nextpnr-ice40, HX8K-CT256, post-route.

| Design | N | LUTs | FF | DSP48E1 | CARRY4 | iCE40 LCs | iCE40 Fmax (MHz) | Latency (cyc) | Time @Fmax (ns) |
|---|---|---|---|---|---|---|---|---|---|
| systolic_top | 2 | 38 | 119 | 4 | 3 | 1314 / 7680 | 86.8 | 8 | 92 |
| systolic_top | 3 | 90 | 236 | 9 | 9 | 3051 / 7680 | 82.8 | 11 | 133 |
| systolic_top | 4 | 137 | 456 | 16 | 8 | 5430 / 7680 | 79.2 | 14 | 177 |
| systolic_top | 8 | 500 | 2057 | 64 | 20 | - | - | 26 | - |
| seq_matmul | 2 | 55 | 31 | 1 | 5 | 486 / 7680 | 62.1 | 11 | 177 |
| seq_matmul | 3 | 72 | 36 | 1 | 9 | 893 / 7680 | 57.2 | 30 | 524 |
| seq_matmul | 4 | 59 | 36 | 1 | 5 | 1360 / 7680 | 58.1 | 67 | 1154 |
| seq_matmul | 8 | 62 | 41 | 1 | 8 | - | - | 515 | - |
