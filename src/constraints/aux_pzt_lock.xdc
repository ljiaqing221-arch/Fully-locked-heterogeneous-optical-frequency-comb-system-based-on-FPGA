set_property PACKAGE_PIN Y18 [get_ports {adc_data[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[0]}]
set_property PACKAGE_PIN AA18 [get_ports {adc_data[14]}]
set_property PACKAGE_PIN AB14 [get_ports {adc_data[13]}]
set_property PACKAGE_PIN AB15 [get_ports {adc_data[12]}]
set_property PACKAGE_PIN Y13 [get_ports {adc_data[11]}]
set_property PACKAGE_PIN AA13 [get_ports {adc_data[10]}]
set_property PACKAGE_PIN V13 [get_ports {adc_data[9]}]
set_property PACKAGE_PIN W13 [get_ports {adc_data[8]}]
set_property PACKAGE_PIN W18 [get_ports {adc_data[7]}]
set_property PACKAGE_PIN W17 [get_ports {adc_data[6]}]
set_property PACKAGE_PIN AA17 [get_ports {adc_data[5]}]
set_property PACKAGE_PIN AB17 [get_ports {adc_data[4]}]
set_property PACKAGE_PIN W16 [get_ports {adc_data[3]}]
set_property PACKAGE_PIN Y16 [get_ports {adc_data[2]}]
set_property PACKAGE_PIN Y14 [get_ports {adc_data[1]}]
set_property PACKAGE_PIN AA14 [get_ports {adc_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports adc_clk]
set_property IOSTANDARD LVCMOS33 [get_ports adc_csb]
set_property IOSTANDARD LVCMOS33 [get_ports adc_dco]
set_property IOSTANDARD LVCMOS33 [get_ports adc_oeb]
set_property IOSTANDARD LVCMOS33 [get_ports adc_otr]
set_property IOSTANDARD LVCMOS33 [get_ports adc_pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports adc_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports adc_sdio]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property PACKAGE_PIN V14 [get_ports adc_clk]
set_property PACKAGE_PIN AA19 [get_ports adc_csb]
set_property PACKAGE_PIN V15 [get_ports adc_dco]
set_property PACKAGE_PIN Y19 [get_ports adc_oeb]
set_property PACKAGE_PIN AA16 [get_ports adc_otr]
set_property PACKAGE_PIN J20 [get_ports reset_n]
set_property PACKAGE_PIN AB16 [get_ports adc_pwdn]
set_property PACKAGE_PIN AB20 [get_ports adc_sclk]
set_property PACKAGE_PIN AB19 [get_ports adc_sdio]
set_property PACKAGE_PIN M19 [get_ports sys_clk]


create_clock -period 20.000 -name DCO_CLK [get_ports adc_dco]
# Root clock for the board's 50 MHz system domain in the project flow.
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -of_objects [get_ports adc_dco]]

set_property PACKAGE_PIN V22 [get_ports pzt_dac_sync]
set_property IOSTANDARD LVCMOS33 [get_ports pzt_dac_sync]
set_property PACKAGE_PIN W22 [get_ports pzt_dac_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports pzt_dac_sclk]
set_property PACKAGE_PIN U22 [get_ports pzt_dac_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports pzt_dac_mosi]

# Original board pin map only. Add measured source-synchronous input/output
# delays before hardware timing sign-off. Do not mask unconstrained ADC data.

# ADC_READY is a stable single-bit SYS_CLK -> DCO crossing through two flops.
# Only the FIRST synchronizer D pin is asynchronous; keep stage0 -> stage1 timed.
set ready_first [get_cells -hierarchical -regexp {.*ready_sync_reg\[0\]}]
set_false_path -to [get_pins -of_objects $ready_first -filter {REF_PIN_NAME == D}]

# User-authorized adjacent PACKAGE BALL assignment. Board connector routing still
# needs checking against the actual board schematic before programming.
# U20/V20 are bonded, unused general-purpose I/O in bank33 (Vivado pin database).
# Both are independent LVCMOS33 same-frequency outputs, NOT an LVDS pair or ground.
set_property PACKAGE_PIN U20 [get_ports mixer_lo_out]
set_property PACKAGE_PIN V20 [get_ports mixer_lo_monitor]
set_property IOSTANDARD LVCMOS33 [get_ports {mixer_lo_out mixer_lo_monitor}]
set_property DRIVE 8 [get_ports {mixer_lo_out mixer_lo_monitor}]
set_property SLEW SLOW [get_ports {mixer_lo_out mixer_lo_monitor}]
# Clock constraints are generated from LO_DIVIDE by create_project.tcl.
# VIO and the controller share adc_dco; LO readiness is not an asynchronous crossing.
