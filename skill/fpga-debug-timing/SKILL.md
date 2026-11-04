---
name: fpga-debug-timing
description: "核对 FPGA ILA 探针连接、XCI 配置、捕获时间窗，并从 Vivado 时序、资源、DRC 和 methodology 报告提取问题。用于只读定位调试映射或时序瓶颈。"
---

# ILA 映射与实现报告检查

## 使用范围
JSON/XML XCI、简单 Verilog 命名端口和 Vivado 文本报告；适用其他板卡和工程。解析器是轻量静态检查，遇宏、generate、复杂表达式需使用 elaboration 或网表工具。

## 处理方式
先运行 probe_map.py 核对序号、信号和位宽，再按明确的时钟与采样步距计算 ILA 时间窗。按现象选择 OTR、有效步、状态、误差和输出的触发条件。实现问题先运行 report_health.py；关注 WNS/WHS、约束覆盖和 Critical Warning，再沿报告路径定位，不用资源占用低替代时序结论。

先读 [使用与失效说明](README.md) 中与当前任务相关的内容。按用户需要生成代码、检查结果或说明，不强制每次重建整套工程。

## 关键约定
探针文件、bitstream 和源码必须来自同一次构建；本脚本无法自动证明新鲜度。时钟频率及 capture stride 由调用者给定，stride 不是凭空增加的 ILA 设置。报告缺失返回 unknown，不当作 0 或通过。脚本不修改工程，不生成 false_path 或 CLOCK_DEDICATED_ROUTE FALSE 掩盖问题。Tcl 模板需在正确设计已打开时执行。

## 配套资源
scripts/probe_map.py、scripts/report_health.py；assets/report_current_design.tcl 生成只读报告。

代码依据、观察和排查方法见 [经验依据](references/experience.md)。只加载当前任务需要的文件。案例默认值可改，保留位宽、数据有效、复位及事务语义；不要把光学名称或原板管脚带入其他项目。

## 验证与交付
用本技能的案例验证改动，必要时扩展边界用例。当前工程 ila_1 的 16 个探针位宽及时间窗；真实历史报告负裕量及约束缺项；合成通过、失败、缺失报告，以及 XML/JSON XCI 测试。Tcl 模板未运行 Vivado，需工具现场验证。

区分已运行的仿真、已有报告提取与实物测量。保留原文件，在新文件或副本上操作；交付可复用资源、调用方式和影响结果的实际限制。

## 检查边界

探针位宽只在实例所属模块中解析；XCI 同一参数值冲突则停止。NaN / 无穷时钟、非正深度、不可解析报告不得作为通过。报告提取核对设计名称，混用不同设计时列出 mixed_design_reports；即使数值为正，原文明确 not met 仍判为失败。源码轻量扫描仍不替代 elaboration。
