if {[info exists ::env(AUX_PZT_BUILD_ROOT)]} {set root $::env(AUX_PZT_BUILD_ROOT)} else {set root [file dirname [file dirname [file dirname [file normalize [info script]]]]]}
set_param general.maxThreads 1
read_verilog [file join $root src rtl aux_pzt_lock_controller.v]
synth_design -top aux_pzt_lock_controller -part xc7z020clg484-2 -mode out_of_context
create_clock -period 20 [get_ports clk]
report_utilization -file [file join $root build reports controller_utilization.txt]
report_timing_summary -file [file join $root build reports controller_timing.txt]
write_checkpoint -force [file join $root build reports controller_synth.dcp]
puts "CONTROLLER_SYNTHESIS_PASSED"
