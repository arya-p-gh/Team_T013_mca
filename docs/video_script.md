# Prototype video: 5-minute outline

Target length 4:30–4:50, so you stay under the 5:00 limit. Each segment names its speaker. Every clip shown below already exists in the repo.

| Time | Speaker | What is on screen | What to say |
|---|---|---|---|
| 0:00–0:35 | Arya (then everyone) | Title slide, then team names | Project title. Each member says their own name and role. **All 5 names must be stated.** |
| 0:35–1:05 | Arya | `report/figures/block_diagram.png` | **Project idea.** Matrix multiplication dominates AI workloads. A systolic array runs N² MACs in parallel and passes data only between neighbours, which is the same idea Google's TPU uses. Our goal is a 4×4 array on an FPGA, compared against a sequential baseline. |
| 1:05–1:35 | Arya | `pe_micro.png`, then `rtl/pe.v` in the editor | PE and MAC: multiply-accumulate, `a` forwarded right, `b` forwarded down. Q4.4 fixed point with a 20-bit accumulator. |
| 1:35–2:00 | Divyansh | `dataflow_skew.png`, `rtl/input_buffer.v` | The grid and the skew: row *i* is delayed *i* cycles, so a_ik meets b_kj in PE(i,j). Zeros fill the gaps. The output buffer snapshots the results. |
| 2:00–2:25 | Rishita | `fsm.png`, `rtl/seq_matmul.v` | FSM: CLEAR → COMPUTE (3N−1 cycles) → CAPTURE → DONE. The host interface, and the single-MAC baseline we compare against. |
| 2:25–3:25 | Mohit | Terminal: `make sim` (live), then the waveform in GTKWave or `waveform_systolic_N4.png` | **Live demo.** Python model generates the tests. Show the PASS lines scrolling, the printed fixed-point result matrix, and "14 cycles vs 67 cycles". In the waveform, point out row 3 entering 3 cycles late and PE(3,3) finishing last. |
| 3:25–4:20 | Abhishek | `latency_vs_n.png`, `synth/summary.md`, report Table III | Results: 4.8× fewer cycles, 79 MHz vs 58 MHz, 6.5× faster in wall-clock time, 16 DSPs on Artix-7, 19.8× at 8×8. Also note the I/O bottleneck and the 36% PE utilization. |
| 4:20–4:45 | Abhishek | GitHub repo page | Repo tour: rtl/, tb/, model/, report/. Phase II plan: board demo, pipelined jobs, wider I/O. Thank you. |

## Recording tips
* Record the terminal at a large font size (≥ 18 pt). Clear the screen first and run `make sim`.
* To open GTKWave: `gtkwave sim/waves/tb_systolic_N4.vcd`. Add `dut.u_ctrl.state`, `dut.a_left`, `dut.b_top`, and a few `u_pe.acc` signals.
* Export at 1080p. Upload as unlisted on YouTube or Drive, then paste the link into `README.md`.
