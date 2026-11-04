# 代码依据与参数

## 原始材料

用户提供的 `pump_locked.zip` 中 `pump_locked.srcs/sources_1/new/pid_lock_controller.v`。

本包保留原文件快照：`original_pid_lock_controller.v`。

SHA-256：`0987da9c7a2b0e89bd7fc5bfedad04ffdb18d2cb655f409ef4d3febff55ed00f`。

此哈希对应制作技能时读取的源码；用户后来提交新版代码时，以新版为准，先核对差异。

定位原始快照：

| 行号 | 内容 |
| --- | --- |
| 4～56 | DAC 范围、控制节拍、增益移位、限幅和锁定参数 |
| 176～181 | 等待、扫描、捕获、粗调、细调、锁定状态编码 |
| 300～309 | `raw_error = target_adc − filtered`，可反向 |
| 750～813 | 控制更新、粗细调、锁定判据、积分及输出限幅 |

源代码输入为 ADC 样本，先滤波、扫描和获取目标值，再内部计算误差。本技能默认抽取其后半段，使误差从外部输入。不是直接改变原顶层端口，也不表示扫描选点功能可以仅凭误差完成。

## 控制公式

令 `e[k]` 为本次 PID 更新时刻的误差，`A[k−1]` 为此前的积分累积值。模板可选反号。

粗调 `abs(e[k]) > 1024`：

```text
step[k] = clip(e[k] >>> 3, −512, +512)
A[k] = 0
```

细调：

```text
P[k] = e[k] >>> 5
I[k] = A[k−1] >>> 10
D[k] = (e[k] − e[k−1]) >>> 4
step[k] = clip(P[k] + I[k] + D[k], −32, +32)
A[k] = clip(A[k−1] + e[k], −262143, +262143)
```

输出：

```text
u[k] = clip(u[k−1] + step[k], 0x6000, 0xA000)
```

`>>>` 是二进制补码算术右移，对负数并不等同于向零取整。保留该运算行为。

## 默认配置

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `DAC_INIT` | `16'h8000` | 初始控制字 |
| `DAC_MIN` / `DAC_MAX` | `16'h6000` / `16'hA000` | 控制字下限、上限 |
| `PID_DIV` | 5000 | PID 更新间隔，以时钟周期计 |
| `FINE_THRESHOLD` | 1024 | 粗细调分界，等于边界时进入细调 |
| `KP_COARSE_SHIFT` | 3 | 粗调比例右移位数 |
| `KP_FINE_SHIFT` / `KI_FINE_SHIFT` / `KD_FINE_SHIFT` | 5 / 10 / 4 | 细调各项右移位数 |
| `COARSE_MAX_STEP` / `FINE_MAX_STEP` | 512 / 32 | 每次控制更新的最大步长 |
| `INTEGRAL_LIMIT` | 262143 | 原源码内固定常量，模板改为参数 |
| `LOCK_CONFIRM` | 64 | 连续满足锁定误差窗的 PID 更新次数 |
| `UNLOCK_THRESHOLD` | 512 | 已锁定时的退出阈值，严格大于才撤销 |
| `ERROR_REVERSE` | 0 | 反转输入误差的控制方向 |

锁定进入阈值由 `FINE_THRESHOLD >> 2` 推导，默认 256。未锁定时，落在 256～512 区间也会清零确认计数；已锁定时该区间维持状态。

更新率 `f_update = f_clk / PID_DIV`。例如控制时钟确为 50 MHz 时，默认间隔对应 10 kHz；不能在未知时钟频率时直接写 10 kHz。

## 输出与实现边界

- `lock_out[15:0]` 对应原 `ut`，属于 DAC 控制字，不是电压测量值，也不是锁定布尔值。电压换算需知道 DAC 量程、参考和后级增益。
- `locked` 是内部误差窗口计数结果。它能作为锁定指示，但仅靠该标志不能证明光学相干性、带宽、线宽或长期稳定性。
- 模板 `error_in` 为有符号 18 位；误差扩到 32 位，积分候选值与 PID 求和扩到 64 位，修正原代码只用 `raw_error[15:0]` 求绝对值而不能覆盖通用 18 位输入范围的问题。默认项目误差标度仍沿用原码值。
- 模板仅清空积分或将积分累积值钳位，未增加基于输出饱和方向的条件积分 / 回算抗饱和算法。后续要求抗积分饱和时，应明确这是新增行为。
- 原源码锁定分支超阈值会清除 `locked` 并继续粗调 / 细调；它没有在此处把 `lock_mode` 清零。因此不能声称失锁自动回到扫描。
- 模板默认误差在控制时钟域连续有效。时钟 / 复位以外只保留一个业务输入和一个业务输出。需要使能、有效握手或锁定状态端口时，按实际接入要求增加。

## 模板验证

制作本技能时，模板与自检 testbench 已在 ModelSim SE-64 2020.4 中编译、仿真通过。覆盖正负极限误差、反馈反向、控制节拍、粗细调边界、PID 历史项、积分限幅、DAC 限幅和锁定滞回；没有实物测量或光学闭环性能结论。

可在独立临时目录运行，下面的 `SKILL_DIR` 替换为技能实际路径：

```text
vlib work
vlog -sv -work work SKILL_DIR/assets/pid_error_lock.v SKILL_DIR/assets/tb_pid_error_lock.sv
vsim -c work.tb_pid_error_lock -do "run -all; quit -f"
```

核对日志中的 `PASS: PID arithmetic, cadence, signed extremes, limits and lock hysteresis`，并检查不存在 fatal / error。不能仅凭模拟器进程退出码宣布通过。testbench 为验证加速将 `PID_DIV`、`LOCK_CONFIRM` 分别覆盖为 2、4，不代表硬件默认值已修改。

## 通用参数下的溢出对照

复查用 `INTEGRAL_LIMIT=2147483600`、细调误差 65535 和 1 周期更新。在旧模板上，32 位相加先溢出，随后限幅无法恢复正确方向；在修订版上，64 位中间运算保留真实符号并正确钳位。该测试是纯 RTL 参数边界验证，不是硬件性能测量。


