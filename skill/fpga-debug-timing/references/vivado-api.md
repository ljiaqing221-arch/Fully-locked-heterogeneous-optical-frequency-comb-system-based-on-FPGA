# Vivado Tcl 依据

模板命令按 AMD 官方 UG835 核对。语法核对不等于已在 Vivado 执行。

- [get_designs](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/get_designs)：取得已打开设计列表。
- [report_timing_summary](https://docs.amd.com/r/2023.1-English/ug835-vivado-tcl-commands/report_timing_summary)：支持 min_max 和 report_unconstrained。

在已打开正确设计的 Tcl 控制台中，将 argv 设为一个新目录路径，argc 设为 1，再 source assets/report_current_design.tcl。不要在用户正在操作的其他设计上直接运行。
