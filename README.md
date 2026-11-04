# Fully-locked-heterogeneous-optical-frequency-comb-system-based-on-FPGA
本项目设计基于 Zynq-7000 FPGA 的异构全锁光频梳数字反馈系统。以 Menlo 超稳光纤梳为参考，利用两点频率约束检测微腔光梳重频偏差；通过光电拍频、固定本振下变频及频压转换完成信号采集。FPGA 集成 ADC 采样、PI²D 定点伺服、自动搜索捕获状态机、DAC 受限输出与遥测监测，驱动 NKT 辅助激光 PZT 调节腔内热状态。系统突出 FPGA 并行处理、确定性低时延和可重构优势，工程已完成 Vivado 综合、布局布线及配置文件生成。
