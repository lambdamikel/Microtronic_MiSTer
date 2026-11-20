// Lint-only stand-ins for the MiSTer framework modules used by Microtronic.sv.
module hps_io #(parameter CONF_STR = "", WIDE = 0) (
	input clk_sys, inout [45:0] HPS_BUS, inout [35:0] EXT_BUS, inout [21:0] gamma_bus,
	output forced_scandoubler, output [1:0] buttons, output [127:0] status, input [15:0] status_menumask,
	output ioctl_download, output [15:0] ioctl_index, output ioctl_wr, output [26:0] ioctl_addr,
	output [7:0] ioctl_dout, input ioctl_wait, output [10:0] ps2_key);
endmodule
module pll(input refclk, input rst, output outclk_0);
endmodule
