// niao.sdc —— 50 MHz 输入时钟约束
// 板载晶振 50 MHz（引脚 6），周期 20 ns，占空比 50%。
// 若本文件导致 PnR 报错，可在工程中取消勾选该文件，不影响功能。

create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
