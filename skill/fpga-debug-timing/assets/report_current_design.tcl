# Use only after the intended synthesized/routed design is open in Vivado.
# Does not build, program, waive checks, or modify clock constraints.
if {$argc != 1} {error "Usage: source in Vivado with argv containing one new report-directory path"}
if {[llength [get_designs -quiet]] == 0} {error "Open the intended design first"}
set report_dir [file normalize [lindex $argv 0]]
if {[file exists $report_dir]} {error "Report directory already exists; choose a new path"}
file mkdir $report_dir
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report_dir timing.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_methodology -file [file join $report_dir methodology.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
report_cdc -file [file join $report_dir cdc.rpt]
puts "Reports written to $report_dir"
