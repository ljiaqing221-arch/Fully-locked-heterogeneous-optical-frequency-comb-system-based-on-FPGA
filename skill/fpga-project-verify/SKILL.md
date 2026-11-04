---
name: fpga-project-verify
description: "为 FPGA RTL 建立可复现的仿真清单、黄金行为对照、失败注入和源文件证据。支持 ModelSim 与 Icarus 的轻量回归运行器，适用于模块迁移及技能包验收。"
---

# 工程复现与黄金回归

## 使用范围
无厂商加密 IP 的可编译 Verilog/SystemVerilog 单元与小型集成仿真；工程含 Xilinx IP 时必须生成相应仿真库或采用适当 stub，不能据此声明完整工程验证。

## 处理方式
先建立输入/输出、复位、更新节拍和通过标志契约。为数值建立独立参考或明确黄金值，至少包含边界和异常用例；不要只证明编译成功。把源文件相对路径写入 manifest，每个测试使用独立 work 库，记录工具、日志、哈希和结果。运行失败注入，确认回归会拒绝缺少通过标志及 fatal。

先读 [使用与失效说明](README.md) 中与当前任务相关的内容。按用户需要生成代码、检查结果或说明，不强制每次重建整套工程。

## 关键约定
scripts/run_rtl.py 只运行清单列出的可信本地源码，不执行 shell 拼接，也不自动下载工具。保留原工程并在新目录构建，单命令默认超时 60 秒，可配置。ModelSim / Icarus 语言支持不同，本次验证以 ModelSim 为准；另一个后端存在不等于已测。黄金模型不应调用待测 RTL 内部计算结果作为期望值。

## 配套资源
scripts/run_rtl.py；assets/manifest.example.json 为最小清单；整个提交包的 examples/regression.json 和 tests/test_tools.py 给出可运行验收。

代码依据、观察和排查方法见 [经验依据](references/experience.md)。只加载当前任务需要的文件。案例默认值可改，保留位宽、数据有效、复位及事务语义；不要把光学名称或原板管脚带入其他项目。

## 验证与交付
用本技能的案例验证改动，必要时扩展边界用例。模块回归及数字链路集成；故意缺少 PASS / fatal 的测试必须返回失败；所有回归源码路径均相对清单解析。具体测试数见 validation/results.json。

区分已运行的仿真、已有报告提取与实物测量。保留原文件，在新文件或副本上操作；交付可复用资源、调用方式和影响结果的实际限制。

## 防止误报

PASS 只能来自模拟器运行输出，不能来自编译日志。run_rtl.py 分别保存 combined.log 与 runtime.log，并检查非空通过标志、唯一测试名称、合法源清单和正有限超时。清单格式见 [manifest schema](references/manifest.schema.json)。

独立用法：在本技能目录执行 `python scripts/run_rtl.py --manifest assets/manifest.example.json --build-dir build --sim modelsim`。最小例完全位于本目录，不依赖其他 Skill。整包可用 tools/verify_bundle.py 联合检查；仅软件模式会明确标注 RTL 跳过。
