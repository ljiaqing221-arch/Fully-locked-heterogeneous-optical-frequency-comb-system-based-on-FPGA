create_generated_clock -name mixer_lo_clock -source [get_ports sys_clk] -divide_by 1 [get_ports mixer_lo_out]
create_generated_clock -name mixer_lo_monitor_clock -source [get_ports sys_clk] -divide_by 1 [get_ports mixer_lo_monitor]
set_property PACKAGE_PIN U20 [get_ports mixer_lo_out]
set_property PACKAGE_PIN V20 [get_ports mixer_lo_monitor]
