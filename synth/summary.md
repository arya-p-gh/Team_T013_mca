# Synthesis summary

Artix-7: Yosys `synth_xilinx` (before placement, estimate).
iCE40: Yosys + nextpnr on an HX8K, after place & route (real Fmax).

| Design | LUTs | FFs | DSP48E1 | LUTRAM | BRAM | iCE40 LCs | iCE40 Fmax (MHz) |
|---|---|---|---|---|---|---|---|
| v1_N2 | 38 | 119 | 4 | 8 | 0 | 1312 / 7680 | 87.8 |
| v1_N3 | 90 | 236 | 9 | 8 | 0 | 3051 / 7680 | 82.8 |
| v1_N4 | 137 | 456 | 16 | 16 | 0 | 5425 / 7680 | 83.9 |
| v1_N8 | 500 | 2057 | 64 | 48 | 0 | - | - |
| seq_N2 | 55 | 31 | 1 | 24 | 0 | 486 / 7680 | 62.8 |
| seq_N3 | 72 | 36 | 1 | 24 | 0 | 893 / 7680 | 57.2 |
| seq_N4 | 59 | 36 | 1 | 24 | 0 | 1360 / 7680 | 58.1 |
| seq_N8 | 62 | 41 | 1 | 26 | 0 | - | - |
| v2_N4_nopipe | 253 | 458 | 16 | 32 | 0 | 5885 / 7680 | 84.7 |
| v2_N4 | 272 | 459 | 16 | 32 | 0 | 5124 / 7680 | 98.3 |
| v2_N8 | 1294 | 2060 | 64 | 128 | 0 | - | - |
| tiled_M8 | 859 | 1795 | 16 | 56 | 0 | - | - |
| board | 317 | 560 | 16 | 16 | 0 | - | - |

v1 = Phase I design, seq = sequential baseline, v2 = Phase II design (row I/O, double
buffering, pipelined MAC unless _nopipe), tiled_M8 = 8x8 matrices on the 4x4 v2 array,
board = basys3_top (v1 4x4 array + UART bridge).
