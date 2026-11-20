// Keyboard path test: PS/2 events -> keypad bits, minimum hold, red keys, F-key switches, Esc reset.
module hps_io #(parameter CONF_STR = "", WIDE = 0) (
	input clk_sys, inout [45:0] HPS_BUS, inout [35:0] EXT_BUS, inout [21:0] gamma_bus,
	output forced_scandoubler, output [1:0] buttons, output reg [127:0] status = 0, input [15:0] status_menumask,
	output ioctl_download, output [15:0] ioctl_index, output ioctl_wr, output [26:0] ioctl_addr,
	output [7:0] ioctl_dout, input ioctl_wait, output reg [10:0] ps2_key = 0);
	assign buttons = 0; assign forced_scandoubler = 0;
	assign ioctl_download = 0; assign ioctl_index = 0; assign ioctl_wr = 0; assign ioctl_addr = 0; assign ioctl_dout = 0;
endmodule
module pll(input refclk, input rst, output outclk_0); assign outclk_0 = refclk; endmodule

module tb;
	reg clk = 0; always #10 clk = ~clk;
	wire [45:0] hps; wire [12:0] sa; wire [15:0] sdq;
	emu dut(.CLK_50M(clk), .RESET(1'b0), .HPS_BUS(hps));
	task key(input [7:0] code, input ext, input press);
		begin @(posedge clk); dut.hps_io.ps2_key <= {~dut.hps_io.ps2_key[10], press, ext, code}; @(posedge clk); end
	endtask
	task waitsteps(input integer n); integer i; begin for (i = 0; i < n; i = i + 1) @(posedge dut.executed); end endtask
	initial begin
		dut.hps_io.status[2:1] = 2'd2;                       // 16x
		waitsteps(100);
		key(8'h16, 0, 1); waitsteps(10);                     // '1' down
		$display("1 down: keys=%h (bit 4 expected)", dut.keys);
		key(8'h16, 0, 0); waitsteps(10);                     // quick release: still held
		$display("1 quick up: keys=%h pend=%h (still held)", dut.keys, dut.pend);
		waitsteps(5000);
		$display("after 5000 steps: keys=%h pend=%h (released)", dut.keys, dut.pend);
		key(8'h33, 0, 1); key(8'h5a, 1, 1); waitsteps(10);   // HALT + keypad Enter
		$display("HALT+KPEnter: keys=%h (bits 21,19)", dut.keys);
		waitsteps(6000); key(8'h33, 0, 0); key(8'h5a, 1, 0); waitsteps(2);
		$display("released: keys=%h", dut.keys);
		key(8'h75, 1, 1); waitsteps(2);                      // Up arrow (E0 75) must not be 8
		$display("up arrow: keys=%h (0)", dut.keys);
		key(8'h05, 0, 1); key(8'h05, 0, 0); key(8'h0c, 0, 1); waitsteps(2);
		$display("F1, F4: sw=%b din=%b inputs=%b (1001)", dut.sw, dut.din, dut.inputs);
		key(8'h41, 0, 1); key(8'h49, 0, 1); waitsteps(2);    // red G (In 1), H (In 2)
		$display("red G+H: redkeys=%b din=%b (1011)", dut.redkeys, dut.din);
		key(8'h41, 0, 0); key(8'h49, 0, 0);
		key(8'h76, 0, 1); @(posedge clk); @(posedge clk);
		$display("Esc: kbd_reset pulse seen=%b", dut.reset);
		$finish;
	end
	initial #50_000_000 begin $display("timeout"); $finish; end
endmodule
