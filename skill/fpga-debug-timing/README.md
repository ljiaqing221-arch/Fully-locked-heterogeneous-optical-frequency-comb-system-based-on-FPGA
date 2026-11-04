# ILA 映射与实现报告检查

## 适用场景
JSON/XML XCI、简单 Verilog 命名端口和 Vivado 文本报告；适用其他板卡和工程。解析器是轻量静态检查，遇宏、generate、复杂表达式需使用 elaboration 或网表工具。

## 调用示例
```text
使用 $fpga-debug-timing，核对我的顶层与 ILA XCI，并检查 routed timing、utilization 和 DRC；只读取，不修改约束。
```

## 使用方法
先运行 probe_map.py 核对序号、信号和位宽，再按明确的时钟与采样步距计算 ILA 时间窗。按现象选择 OTR、有效步、状态、误差和输出的触发条件。实现问题先运行 report_health.py；关注 WNS/WHS、约束覆盖和 Critical Warning，再沿报告路径定位，不用资源占用低替代时序结论。

scripts/probe_map.py、scripts/report_health.py；assets/report_current_design.tcl 生成只读报告。

## 失效条件
探针文件、bitstream 和源码必须来自同一次构建；本脚本无法自动证明新鲜度。时钟频率及 capture stride 由调用者给定，stride 不是凭空增加的 ILA 设置。报告缺失返回 unknown，不当作 0 或通过。脚本不修改工程，不生成 false_path 或 CLOCK_DEDICATED_ROUTE FALSE 掩盖问题。Tcl 模板需在正确设计已打开时执行。

## 验证效果
当前工程 ila_1 的 16 个探针位宽及时间窗；真实历史报告负裕量及约束缺项；合成通过、失败、缺失报告，以及 XML/JSON XCI 测试。Tcl 模板未运行 Vivado，需工具现场验证。

本次整包验证记录见 `validation/results.json`。独立复制本技能时不依赖该目录；使用本项模板和测试重新验证，并保留自己的日志。未执行的工具或板卡测试不算已验证。

## 经验来源
原指南 probe9/10 描述与顶层实际连接不一致；原 ILA 1024 点、50 MHz 连续采集仅对应 20.48 μs 采样时长。旧报告 WNS=-1.266 ns、18 个输入与 6 个输出缺延迟约束，并存在 TIMING-4/6/7/27 关键警告。报告日期早于此次抽取，不据此断言新版工程状态。

## 常见问题
抓不到慢扫描：先算时间窗并使用合适的采集限定或外部记录；探针名称不符：比较 RTL 与 XCI；全布线完成但时序失败：看负裕量；时序全正却不能验收：查遗漏接口约束、CDC 与报告来源；复杂语法解析失败：停止猜测，转 elaboration。

进一步说明见 [经验依据](references/experience.md)。

## 命令示例

```text
python scripts/report_health.py --timing timing.rpt --utilization utilization.rpt --drc drc.rpt --methodology methodology.rpt --output health.json
python scripts/probe_map.py --rtl top.v --xci ila_0.xci --core ila_0 --clock-hz 50000000 --output probes.json
```

report_health 默认只提取数据，问题在 status/findings；需要退出码作为验收门槛时加 --strict，失败为 1，数据不足为 2。probe_map 有不匹配或未知项返回 1。Tcl 使用条件和官方语法依据见 [Vivado API](references/vivado-api.md)。

## 防误判复查

位宽限定在 ILA 实例所属模块，避免其他模块的同名信号覆盖。对 NaN、非正 XCI 深度、冲突的重复参数、混合设计报告、不可解析报告和 not met 提示分别处理，不能缺数据仍宣布通过。修订用例见整包 tests/test_review.py。
