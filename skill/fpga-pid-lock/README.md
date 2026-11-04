# FPGA PI²D / PID 锁定技能

本技能已按 `aux_pzt_pi2d_fpga.zip`（2026-11-03）更新。默认生成最新版辅助光 PZT PI²D 控制器：P、I、I²、滤波 D、双积分抗饱和、执行器范围/步进限制、搜索捕获、失样保持、锁定迟滞和故障状态均保留。

调用示例：

```text
使用 $fpga-pid-lock，按最新辅助 PZT 代码生成完整 PI²D 锁定控制器，并给出端口、状态码和仿真。
```

```text
使用 $fpga-pid-lock，把最新版 PI²D 裁剪为 signed error_in + error_valid 输入、16 位 control_out 输出；没有测量绝对值，因此不要保留搜索状态。
```

## 两种主用法

- **完整 PI²D（推荐）**：复制 `assets/aux_pzt_lock_controller.v`，外围按项目接 ADC 平均、DAC、VIO/ILA 或遥测。
- **外部误差简化版**：保留 PI²D 递推、抗饱和、限幅、有效握手和锁定迟滞；去掉依赖绝对测量/目标交叉的搜索。
- **旧版 PID 兼容**：只有明确要求“粗调 P + 细调 PID”时才使用 `assets/pid_error_lock.v`。

`aux_pzt_code/control_out` 是发往执行器的控制字；`locked` 是状态位，两者不能互换。

## 验证

最新版源工程的 XSim 回归已覆盖：

- 精确 Q16 PI²D 递推和首次微分抑制；
- 双积分在执行器饱和时冻结；
- 正负斜率、非零目标、热惯性扰动；
- 拍频/辅助光/ADC 无效保持与恢复；
- 失样超时、PZT 接口门控、搜索捕获与搜索耗尽；
- 手动模式范围/步进限制；
- ADC 码制、DAC 24 位 SPI 帧和原子遥测快照。

技能内保留相同控制器和回归源码。实际工程报告显示 Vivado 2025.2 实现完成且约束内 WNS 为正，但明确 `hardware_tested=false`；仍需板级 ADC 时序、LO 驱动、模拟增益/偏置、PZT 安全范围、真实 JTAG 数据与光学锁定验证。

在 Windows 上可直接运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_regression.ps1
```

脚本从 PATH 查找 ModelSim；未加入 PATH 时用 `-ModelSimBin` 显式指定可执行文件目录。结果写到独立临时目录，不修改用户工程。

## 常见失效

- 把 PI²D 写成普通 PID，或将 I² 当成 `error²`；这里 I² 是“积分的再次积分”。
- 改更新周期却沿用原 I、I²、D 系数。
- 失样时把误差置零而继续积分。
- 只做输出范围限幅，没有步进限幅和双积分抗饱和。
- 用 `locked` 证明光学相干、线宽或长期稳定度。
- 没有绝对测量码却声称可以搜索目标交叉。
- 多位 ADC/遥测跨时钟只串两级触发器，没有数据一致性机制。

详细公式、默认值、来源哈希和验证边界见 [references/code-basis.md](references/code-basis.md)。旧版依据已归档到 [references/legacy-pid-basis.md](references/legacy-pid-basis.md)。

