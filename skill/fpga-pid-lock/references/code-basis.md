# 最新代码依据、公式与验证边界

## 来源

用户提供归档：`aux_pzt_pi2d_fpga.zip`

- 压缩包 SHA-256：`95b48c51c1b159aa9b34a3c85ecc9d0aacea82800aa2182296442cb0f6583ccf`
- 核心 `rtl/aux_pzt_lock_controller.v` SHA-256：`e30d4616dc747e57dcb06eb82efcb2f86a58c08f1c980ceedf796f5f4853de94`
- `sim/tb_pi2d.sv` SHA-256：`ccf7b9e185984b9bc903c46f4eccdb1e9f75f2c0df090594911e87bebcb63461`
- `sim/tb_aux_pzt_lock.sv` SHA-256：`c6475b303ef6300d6d567c6beef9820ff9c3eae2561bcab2fc783f209c3bc138`

技能中的同名最新 assets 保持源码内容，仅将行尾规范化为 LF，因此字节哈希与原始 CRLF 文件不同：

- `assets/aux_pzt_lock_controller.v`：`01c09c32b072551f2c83962b876e11eb7cb1da769f199b589a4b97794821ed9d`
- `assets/tb_pi2d.sv`：`270fbb1c30bb6dc52262c1d7de10ce5768bc7d596532224fb9f80bda8cfc127a`
- `assets/tb_aux_pzt_lock.sv`：`903b811c43bb8c3f6041bdbcfc50c8e9de8b5621e0bdb03eac54dbd6cf7adef7`

两个技能版 testbench 另补齐了上游未连接的只读诊断端口，以便在 ModelSim 下实现零编译告警；激励和判定逻辑未改变。

旧 `pump_locked` 粗细调 PID 依据已移到 [legacy-pid-basis.md](legacy-pid-basis.md)。

## PI²D 不是误差平方

源码实现 P + I + I² + 带一阶低通的 D。令 `s1` 为误差累加，`s2` 为 `s1` 的累加：

```text
e = polarity_reverse ? -(target - measured) : (target - measured)
s1' = clip(s1 + e, ±SUM_LIMIT)
s2' = clip(s2 + s1', ±SUM_LIMIT)
P  = e   * KP_Q16
I  = s1' * KI_Q16
II = s2' * KII_Q16
Dt = history ? (e - previous_error) * KD_Q16 : 0
Df = Df_previous + ((Dt - Df_previous) >>> D_FILTER_SHIFT)
raw_q16 = bias_code * 65536 + P + I + II + Df
requested = raw_q16 >>> 16
desired = clip(requested, PZT_MIN, PZT_MAX)
actual = slew_clip(desired, previous_output, STEP_MAX)
```

当 `requested > actual` 且本次积分变化为正，或 `requested < actual` 且本次积分变化为负时，`s1/s2` 和两级积分项均不更新。微分历史仍更新。该条件同时处理绝对限幅和步进限幅造成的推进饱和。

`bias_code` 在进入跟踪或搜索捕获时记录当前输出，PI²D 各项围绕该偏置生成绝对请求码，而不是每次把 PID 步长继续累加到输出上。这与旧版 `u[k]=u[k-1]+step` 不同，不能混写。

## 最新状态和安全行为

- `pzt_interface_ready=0`：保持输出、故障 4、清控制历史。
- `enable=0`：手动码仍按绝对范围和 `STEP_MAX` 跟随。
- 任一光路有效标志失败：保持最后输出、故障 1。
- ADC 质量失败：保持最后输出、故障 2。
- 样本年龄达到 `SAMPLE_TIMEOUT`：保持最后输出、故障 3。
- 目标或极性变化：重新捕获当前输出为偏置并清历史。
- 搜索：先降到下界，再只在标定单调方向且跨过目标时捕获；到上界未捕获则故障 5。
- 锁定：连续 `LOCK_CONFIRM` 次满足 `|e|≤LOCK_TOL` 且未绝对饱和。
- 失锁：连续 `UNLOCK_CONFIRM` 次满足 `|e|>UNLOCK_TOL` 或绝对饱和。

注意：搜索阶段直接更新 DAC 码；PI²D 阶段使用八级流水。源码在搜索/手动更新时也产生 `update_pulse`，因此外部若把该脉冲理解成“PI²D 计算完成”会出错。

## 顶层外围的真实范围

最新版顶层还接入：

- AD9269 采样和 256 点平均，二补码映射为单调无符号码；
- OTR、近电源轨窗口和采样超时质量判断；
- DAC8552 A 通道 PZT 码、B 通道中点停放，24 位 SPI；
- 固定 LO 输出，不随误差改变；
- VIO 人工确认与 ILA 原子遥测快照；
- Vivado CSV 到 Python 的慢速监控链路。

这些是集成层，不应硬编码进通用控制核心。VIO 有效位是人工确认，不是自动检测。ILA/JTAG/CSV 适合慢变量监控，不是连续高速 ADC 数据流。

## 现有验证证据

源包 `reports/verification_summary.json` 记录：

- 目标器件：`xc7z020clg484-2`，Vivado 2025.2；
- bitstream 完成，约束内 WNS 10.267 ns、WHS 0.057 ns；
- 精确 PI²D、热惯性对象、固定 LO、Python 解析与 Vivado 桥接软件测试通过；
- `hardware_tested=false`。

XSim 日志明确包含：

```text
PASS exact P+I+I2+filtered-D recurrence, signed Q16
PASS invalid-beat recovery without stale D history
PASS both integrators freeze at the actuator rail
PASS thermal-lag plant disturbance rejection
PASS bounded search and capture
PASS search exhaustion stops without false lock
ALL TESTS PASSED
```

这些证据只支持源码仿真和实现流程，不支持“已在真实光路锁定”“测得线宽”“长期稳定”等结论。

## 迁移时最容易犯的错误

1. 将 `I²` 写成 `e*e`。
2. 用旧版增量 PID 公式替代最新版偏置型绝对请求。
3. 丢弃 `sample_valid`/样本年龄，导致重复积分旧样本。
4. 只冻结 I，不冻结 I²。
5. 在有符号扩展之前做反号、差分或绝对值。
6. 将 `locked` 接到 DAC，或把 `aux_pzt_code` 当作布尔锁定状态。
7. 将 0.5 s 更新周期的系数直接迁移到其他周期。
8. 把固定 LO 误写成由 FPGA 根据误差扫频。

