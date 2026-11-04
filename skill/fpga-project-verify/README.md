# 工程复现与黄金回归

## 适用场景
无厂商加密 IP 的可编译 Verilog/SystemVerilog 单元与小型集成仿真；工程含 Xilinx IP 时必须生成相应仿真库或采用适当 stub，不能据此声明完整工程验证。

## 调用示例
```text
使用 $fpga-project-verify，为我的 ADC→控制器→SPI 模块建立 ModelSim 回归，加入最小负误差、输出饱和、异步复位和故意失败用例。
```

## 使用方法
先建立输入/输出、复位、更新节拍和通过标志契约。为数值建立独立参考或明确黄金值，至少包含边界和异常用例；不要只证明编译成功。把源文件相对路径写入 manifest，每个测试使用独立 work 库，记录工具、日志、哈希和结果。运行失败注入，确认回归会拒绝缺少通过标志及 fatal。

scripts/run_rtl.py；assets/manifest.example.json 为最小清单；整个提交包的 examples/regression.json 和 tests/test_tools.py 给出可运行验收。

## 失效条件
scripts/run_rtl.py 只运行清单列出的可信本地源码，不执行 shell 拼接，也不自动下载工具。保留原工程并在新目录构建，单命令默认超时 60 秒，可配置。ModelSim / Icarus 语言支持不同，本次验证以 ModelSim 为准；另一个后端存在不等于已测。黄金模型不应调用待测 RTL 内部计算结果作为期望值。

## 验证效果
模块回归及数字链路集成；故意缺少 PASS / fatal 的测试必须返回失败；所有回归源码路径均相对清单解析。具体测试数见 validation/results.json。

本次整包验证记录见 `validation/results.json`。独立复制本技能时不依赖该目录；使用本项模板和测试重新验证，并保留自己的日志。未执行的工具或板卡测试不算已验证。

## 经验来源
既有项目 testbench 通过不代表旧 routed 报告满足时序，更不代表光学实物性能。PID 抽取的绝对值需覆盖通用 18 位输入最小负数，不能只测原常见误差范围。

## 常见问题
进程返回 0 但测试失败：同时查 PASS 和 fatal/error；旧 work 库污染：每个测试新建目录；相对路径漂移：以 manifest 所在目录解析；参数迁移后越界：增加极值和非整除测试；工具缺失：明确报告不可运行，不能伪造通过。

进一步说明见 [经验依据](references/experience.md)。

## 独立运行

在本技能目录执行：

```text
python scripts/run_rtl.py --manifest assets/manifest.example.json --build-dir build --sim modelsim
```

此例为自包含的计数器与 testbench。ModelSim 不在 PATH 时加 `--tool-dir` 指向其可执行程序目录；有空格的路径在命令行加引号。Icarus 后端尚未验证。

PASS 只在 runtime.log 中按输出行前缀匹配，编译、加载器消息或路径出现同名字符串不会通过。清单要求非空 tests、唯一 name、合法 top、非空 sources 和单行 pass_marker；不合格输入退出码为 2，行为失败为 1。
