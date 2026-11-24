# Vivado script for the Basys-3 board build (lab machine).
# Builds basys3_top with the real pin constraints, all the way to a bitstream.
#
# Run it from the repo folder:
#   vivado -mode batch -source synth/vivado_board.tcl
#
# Output (in synth/vivado_board/):
#   basys3_top.bit          program this onto the board (Hardware Manager)
#   utilization.rpt         LUT / FF / DSP / BRAM use on the real chip
#   timing_summary.rpt      did we meet 100 MHz? (look for WNS >= 0)
#   power.rpt               estimated power
#
# Then: Open Hardware Manager -> Open Target -> Auto Connect -> Program Device
# -> pick basys3_top.bit. Press btnC once, then run host/uart_host.py.
set part xc7a35tcpg236-1
set root [file normalize [file dirname [info script]]/..]
set out  $root/synth/vivado_board
file mkdir $out

read_verilog [list \
    $root/rtl/mac_unit.v $root/rtl/pe.v $root/rtl/systolic_array.v \
    $root/rtl/input_buffer.v $root/rtl/output_buffer.v $root/rtl/systolic_controller.v \
    $root/rtl/systolic_top.v $root/rtl/uart_rx.v $root/rtl/uart_tx.v \
    $root/rtl/uart_bridge.v $root/rtl/basys3_top.v]
read_xdc $root/constraints/basys3.xdc

synth_design -top basys3_top -part $part
opt_design
place_design
route_design

report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing_summary.rpt
report_power          -file $out/power.rpt
write_bitstream -force $out/basys3_top.bit

set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "RESULT basys3_top WNS=$wns ns (positive = timing met at 100 MHz)"
