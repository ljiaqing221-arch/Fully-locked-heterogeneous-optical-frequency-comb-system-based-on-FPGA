---
name: fpga-pid-lock
description: "生成、迁移或核对参数化 FPGA 数字锁定控制器，优先复用辅助光 PZT PI²D 实现。适用于目标码与测量码闭环、搜索捕获、输出限幅、双积分抗饱和、失样保持和锁定迟滞，也可按要求裁剪为外部有符号误差输入、控制字输出的通用模块。"
---

# FPGA PI²D / PID 锁定控制

默认以 2026-11-03 最新 `aux_pzt_pi2d_fpga` 控制器为依据，不把 PI²D 简化成普通 PID：

```text
测量码 + 目标码 + 有效条件
          ↓
搜索捕获 → P + I + I² + 滤波D → 绝对限幅 → 步进限幅 → PZT/DAC控制字
          └──────── 锁定确认、失锁迟滞、故障保持、遥测 ────────┘
```

只需要旧式“外部误差输入、控制字输出”时，可裁剪接口；算法默认仍采用最新版 PI²D。仅当用户明确要求复现旧项目的“粗调 P + 细调 PID”时，才使用兼容模板 `assets/pid_error_lock.v`。

使用方式、文件清单和失效条件见 [README.md](README.md)，代码出处和公式见 [references/code-basis.md](references/code-basis.md)。

## 先选择交付层级

1. **完整 PI²D 控制器（默认）**：复制 `assets/aux_pzt_lock_controller.v`，保留测量、目标、有效条件、搜索、手动模式、状态和遥测项。
2. **外部误差简化版**：外部提供有符号 `error_in` 与 `error_valid`；保留 PI²D、输出范围/步进限幅、抗饱和和锁定迟滞。没有绝对测量码时移除搜索状态，不声称具有自动扫频捕获。
3. **旧版粗细调 PID 兼容**：仅用于复现旧接口或用户明确要求经典 PID；使用 `assets/pid_error_lock.v` 及其两个旧版 testbench。

若需求没有说明，交付完整 PI²D 控制器，并将板卡 ADC、DAC、LO、VIO/ILA 放在外层，不嵌入控制核心。

## 最新控制器接口语义

| 端口组 | 关键信号 | 语义 |
| --- | --- | --- |
| 控制 | `enable`, `polarity_reverse`, `search_request` | 使能、反馈极性、一次搜索请求 |
| 有效条件 | `reference_valid`, `comb_valid`, `beat_valid`, `auxiliary_valid`, `pzt_interface_ready`, `adc_quality` | 操作者/外层确认；不是自动光学检测 |
| 采样 | `sample_valid`, `fv_voltage_code`, `target_voltage_code` | 新平均码、测量码、非零目标码 |
| 手动 | `manual_pzt_code` | 禁用闭环时仍按范围和步进限制缓慢跟随 |
| 输出 | `aux_pzt_code` | 16 位执行器/DAC 控制字，不是锁定布尔量 |
| 诊断 | `voltage_error`, `locked`, `state`, `fault`, `saturated`, `update_pulse` | 环内状态；`locked` 不能代替独立光学验证 |
| 遥测 | `integral_q16`, `integral2_q16`, `derivative_q16` | Q16 项，便于 ILA/上位机观察 |

时钟和复位仍是基础接口。跨时钟的多位采样必须用握手、异步 FIFO 或同拍快照，不能仅做两级单比特同步。

## 必须保留的 PI²D 数值行为

以一次控制更新为离散时刻。先计算 `e = target - measurement`，再按 `polarity_reverse` 可选反号。

```text
s1[k] = clip(s1[k-1] + e[k], ±SUM_LIMIT)
s2[k] = clip(s2[k-1] + s1[k], ±SUM_LIMIT)
P      = e[k]  · KP_Q16
I      = s1[k] · KI_Q16
I²     = s2[k] · KII_Q16
Dtar   = history ? (e[k] - e[k-1]) · KD_Q16 : 0
Df[k]  = Df[k-1] + ((Dtar - Df[k-1]) >>> D_FILTER_SHIFT)
request = (bias·65536 + P + I + I² + Df) >>> 16
output  = slew_clip(range_clip(request), previous_output, STEP_MAX)
```

- 计算共八个寄存级；不要把参数 `UPDATE_CYCLES` 当作总输出间隔而忽略额外流水拍。
- 第一次有效更新的微分项为零；无效输入、目标变化或极性变化后清除历史，避免恢复时产生微分冲击。
- 当请求值与实际限幅值之差的方向和积分推进方向相同，冻结两级积分；不得只冻结一级。
- 输出绝对限幅与单次步进限幅是两种不同保护；`saturated` 只标记绝对范围限幅。
- 所有乘法、差分、反号和累加先做有符号扩展，再限幅缩位。

## 状态机与故障

状态编码保持源码定义：

| 值 | 状态 | 行为 |
| --- | --- | --- |
| 0 | DISABLED | 闭环关闭；手动码仍受范围和步进限制 |
| 1 | WAIT_VALID | 条件无效或样本超时；保持最后输出并清历史 |
| 2 | TRACK | PI²D 跟踪 |
| 3 | LOCKED | 达到连续确认条件 |
| 4 | SEARCH | 从下界向上扫描并检查单调目标交叉 |
| 5 | SEARCH_FAILED | 到达上界仍未捕获，停止并报错 |
| 6 | SEARCH_PREP | 先受限速地下行至搜索起点 |

故障：0 无故障；1 光路/拍频条件无效；2 ADC 质量失败；3 样本超时；4 PZT 接口未确认；5 搜索耗尽。

`pzt_interface_ready=0` 时任何手动或闭环运动都必须停止。丢拍频、丢样或 ADC 质量失败时保持最后输出，不能把缺失样本当零误差继续积分。搜索只能在已标定的单调拍频支路上使用；没有支路方向、PZT 安全范围和梳保持验证时不要自动启动。

## 参数迁移

最新版工程顶层配置的参考默认值：

| 参数 | 默认值 |
| --- | --- |
| `PZT_INIT / MIN / MAX` | `0x8000 / 0x7800 / 0x8800` |
| `UPDATE_CYCLES` | 25,000,000（50 MHz 下约 0.5 s，另加流水拍） |
| `SAMPLE_TIMEOUT` | 5,000,000 |
| `KP_Q16 / KI_Q16 / KII_Q16 / KD_Q16` | 4096 / 256 / 1 / 128 |
| `D_FILTER_SHIFT` | 2 |
| `SUM_LIMIT` | 16,777,216 |
| `STEP_MAX / SCAN_STEP` | 64 / 64 |
| `LOCK_TOL / UNLOCK_TOL` | 64 / 256 |
| `LOCK_CONFIRM / UNLOCK_CONFIRM` | 8 / 3 |

这些数值是代码默认和安全调试起点，不是新硬件的实测最优参数。改变控制更新周期后必须重调 I、I²、D。迁移前核对：

- `MIN ≤ INIT ≤ MAX`，且目标码位于已标定的 F/V 单调有效区。
- `UPDATE_CYCLES`、超时、确认计数、步进均为正数；`D_FILTER_SHIFT` 为合理非负移位。
- Q16 乘积、双积分和偏置和式不会越过所选中间位宽。
- 反馈极性先用小步进开环确认；不要依靠“应该是负反馈”猜方向。
- ADC 码制、F/V 标定、DAC 电压范围和后级增益全部来自实物测量。

## 资源与验证

- 最新核心：[assets/aux_pzt_lock_controller.v](assets/aux_pzt_lock_controller.v)
- 最新完整回归：[assets/tb_aux_pzt_lock.sv](assets/tb_aux_pzt_lock.sv)
- 精确 PI²D 递推与快照回归：[assets/tb_pi2d.sv](assets/tb_pi2d.sv)
- 回归依赖：[assets/fv_adc_average.v](assets/fv_adc_average.v)、[assets/aux_pzt_dac.v](assets/aux_pzt_dac.v)、[assets/telemetry_snapshot.v](assets/telemetry_snapshot.v)
- 顶层参考配置：[assets/aux_pzt_config.vh](assets/aux_pzt_config.vh)
- 旧版兼容：`assets/pid_error_lock.v`、`assets/tb_pid_error_lock.sv`、`assets/tb_pid_parameter_edges.sv`

修改 PI²D 算法、位宽、状态机、节拍或保护条件后，至少重新运行两个最新 testbench。检查日志中的 PASS 文本，不以模拟器退出码单独判定成功。仿真通过只能表述为 RTL 行为验证通过；最新版交付报告明确标记 `hardware_tested=false`，不能写成已经完成实物闭环、线宽或稳定度验证。

## 交付规则

生成新文件并保留用户工程。简短说明接口、参数、反馈方向、状态/故障编码、验证结果和硬件未验证项。用户只要框图时，以测量/目标、PI²D 核心、DAC/PZT、被控对象和反馈路径为主；ADC 平均、固定 LO、VIO/ILA、JTAG/CSV 属于可选外围，不虚构 PS、AXI DMA、TCP 或自动光学传感器。

