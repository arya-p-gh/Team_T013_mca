# Vivado script for the lab machines (we don't have Vivado on our laptops).
# Gives the real Artix-7 numbers: utilization, timing and Fmax.
#
# Run it like:
#   vivado -mode batch -source synth/vivado_synth.tcl -tclargs systolic_top 4
#   vivado -mode batch -source synth/vivado_synth.tcl -tclargs seq_matmul   4
#
# "out of context" mode means Vivado doesn't need a pin file, so there's no
# board setup. We ask for 100 MHz (10 ns clock), and Fmax is worked out from
# how much slack is left over. Reports end up in synth/vivado_<top>_N<N>/.
set top  [expr {[llength $argv] > 0 ? [lindex $argv 0] : "systolic_top"}]
set n    [expr {[llength $argv] > 1 ? [lindex $argv 1] : 4}]
set part xc7a35tcpg236-1
set root [file normalize [file dirname [info script]]/..]
set out  $root/synth/vivado_${top}_N${n}
file mkdir $out

read_verilog [glob $root/rtl/*.v]
synth_design -top $top -part $part -mode out_of_context -generic N=$n
create_clock -name clk -period 10.000 [get_ports clk]
opt_design
place_design
route_design

report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing_summary.rpt
report_power          -file $out/power.rpt
# WNS = worst slack. Positive means we beat 10 ns, and Fmax = 1 / (10 - WNS)
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set fmax [expr {1000.0 / (10.0 - $wns)}]
puts "RESULT top=$top N=$n WNS=$wns ns  Fmax=[format %.1f $fmax] MHz"
set fh [open $out/fmax.txt w]; puts $fh "WNS=$wns Fmax_MHz=[format %.1f $fmax]"; close $fh
