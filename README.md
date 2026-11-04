# 基于FPGA的异构全锁光梳系统

本工程面向光频梳辅助光的 PZT 调节，使用 Zynq-7000 PL 完成 F/V 信号采集、PI²D 运算、搜索捕获和 DAC 输出，通过 VIO 设置控制参数，通过 ILA/JTAG 读取状态与遥测。参赛类别为自主命题初级组，目标器件为 `xc7z020clg484-2`，现有构建使用 Vivado 2025.2。

## 控制链路

```text
F/V 信号 → AD9269 → 采样平均 → PI²D / 搜索控制 → DAC → PZT
                              ↓
                       原子遥测快照 → ILA/JTAG → CSV → Python
VIO → 使能、目标码、手动码、极性、搜索请求及外部状态确认
50 MHz 系统时钟 → 固定频率 LO 输出及监测
```

控制器包含比例、积分、二次积分和滤波微分，采用 Q16 系数与 64 位积分状态。I² 表示对积分结果再次积分。输出同时受码值范围和单步变化量约束；饱和时冻结双积分。状态机处理搜索、目标捕获、失样保持、锁定迟滞及故障状态。外部参考、拍频、辅助光和接口有效性由 VIO 输入确认。

默认参数位于 `src/rtl/aux_pzt_config.vh`：PZT 初值为 `0x8000`，范围为 `0x7800～0x8800`，目标 F/V 码为 `0x8000`，控制更新周期为 25000000 拍，最大步进为 64 码，遥测快照周期为 5000000 拍。在 50 MHz 控制时钟下分别对应 0.5 s 更新和 10 Hz 快照。LO 默认转发 50 MHz，`LO_DIVIDE` 支持 1 或不小于 2 的偶数。模拟增益、偏置、极性和控制系数按实际光路标定。

## 目录

| 目录 | 内容 |
| --- | --- |
| `src/rtl/` | 顶层、采集、PI²D、DAC、LO 与遥测源码 |
| `src/constraints/` | 管脚与时钟约束 |
| `sim/` | 控制器、精确递推和 LO 测试平台 |
| `build/scripts/` | 建工程、综合和实现入口 |
| `build/reports/` | 综合、实现、仿真和软件验证记录 |
| `vivado_project/` | Vivado 工程及生成文件 |
| `bitstream/` | 配套 BIT 与 LTX |
| `host/` | JTAG 采集桥接与 CSV 解析程序 |
| `skill/` | 七项可复用技能、模板、回归与经验依据 |
| `report/` | 设计报告 |

## 构建与复现

安装 Vivado 2025.2、对应器件支持和 Python 3.10 及以上版本，将 `vivado` 加入 PATH。在项目根目录执行：

```powershell
vivado -mode batch -source build/scripts/create_project.tcl
```

脚本创建 `vivado_project/aux_pzt_pi2d_lock.xpr`，生成 Clocking Wizard、VIO 和 ILA，并加入设计、约束与测试平台。创建工程会重建该位置的工程；需要保留当前交互修改时，先另存工程。

从源码完成综合、实现及比特流导出：

```powershell
vivado -mode batch -source build/scripts/create_project.tcl -tclargs -implement
```

综合与实现报告写入 `build/reports/`，BIT 和 LTX 写入 `bitstream/`。仅做综合时使用 `-tclargs -synth`。对现有工程重新实现可运行 `build/scripts/build_bitstream.tcl`。

在 Vivado 中打开工程后，于 Simulation Sources 将 `tb_aux_pzt_lock`、`tb_pi2d`、`tb_fixed_lo` 依次设为仿真顶层，分别运行行为仿真至结束，检查各自通过输出及错误信息。原始运行记录为 `build/reports/simulation.log`、`pi2d_simulation.log`、`pi2d_plant_simulation.log` 和 `lo_simulation.log`；技能包提供独立于厂商 IP 的 ModelSim 回归入口。

在项目根目录运行软件检查：

```powershell
python -m unittest discover -s host -p "test_*.py" -v
python skill/tools/verify_bundle.py --build-dir build/skill_check --software-only
```

完整技能回归的命令和工具要求见 [技能包说明](skill/README.md)。

## 上板与遥测

核对板卡连接、ADC 接口时序、U20/V20 引出位置、Bank 电压、LO 驱动和 DAC 到 PZT 的增益及偏置，确定执行器允许的码值范围后，在 Hardware Manager 下载 `bitstream/aux_pzt_pi2d_lock.bit` 并关联同目录 LTX。VIO 初始闭环使能为关闭状态；先检查手动输出和反馈极性，再设置目标码、外部状态确认与闭环使能。

连接目标 FPGA 后，在 Vivado Tcl Console 执行以下命令；将路径替换为本项目实际位置：

```tcl
source {C:/path/to/project/host/capture_vivado.tcl}
```

采集脚本约每 2 s 更新 `host/live/latest.csv`。在项目根目录读取最新快照：

```powershell
python host/read_telemetry.py --once
```

持续读取时去掉 `--once`。解析器输出目标码、反馈码、误差、PZT 码、状态、积分项、序号及 FPGA 时间等字段；`stale` 表示相邻读取的快照序号相同。停止 Vivado 采集使用 `set ::aux_telemetry_stop 1`。

## 现有验证结果

`build/reports/verification_summary.json` 记录工程的构建与验证结果。资源占用为 LUT 4230（7.95%）、寄存器 6139（5.77%）、BRAM36 11（7.86%）、DSP 0；已约束路径 WNS 为 10.267 ns，WHS 为 0.057 ns，TNS、THS 均为 0。

现有仿真覆盖精确 PI²D 递推、双积分抗饱和、热惯性对象、正负极性、非零目标、有效性门控、失样、搜索、手动输出、DAC 帧及原子快照。板级验证状态为 `hardware_tested=false`；待完成项为 ADC I/O 延迟约束、DCO 非专用时钟路由核查、模拟链路标定及真实 JTAG 与光学闭环测试。

技能包的历史验证记录为 41 项软件测试、12 组正常 RTL 回归、6 组非法参数拒绝测试及 1 组已知失败注入，详见 `skill/validation/results.json`。各项技能的适用条件、迁移步骤、失效条件和经验来源集中列于 [skill/README.md](skill/README.md)。
