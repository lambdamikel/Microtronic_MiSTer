// Simulation top: board + loader + video, as wired in Microtronic.sv (no MiSTer framework).
module sim_top
(
	input         clk, reset, step,
	input  [23:0] keys,
	input   [3:0] din,
	input  [15:0] patch,
	input   [2:0] clock_in,
	input   [1:0] redkeys,
	input         dl, wr,
	input   [7:0] dbyte,
	output  [7:0] R, G, B,
	output        HS, VS, HBlank, VBlank, ce_pix, executed
);
wire        ld_we;
wire  [7:0] ld_addr;
wire [11:0] ld_word;
mic_loader loader(.clk(clk), .download(dl), .wr(wr), .din(dbyte), .we(ld_we), .addr(ld_addr), .word(ld_word));
wire [383:0] seg_level;
wire  [55:0] led_level;
wire   [3:0] dout, inputs;
microtronic board(.clk(clk), .reset(reset), .step(step), .keys(keys), .din(din), .patch(patch), .clock_in(clock_in),
	.dout(dout), .inputs(inputs), .clk1hz(), .r(), .o(), .executed(executed),
	.ld_we(ld_we), .ld_addr(ld_addr), .ld_word(ld_word), .seg_level(seg_level), .led_level(led_level));
video video(.clk(clk), .seg_level(seg_level), .led_level(led_level), .keys(keys), .redkeys(redkeys), .inputs(inputs),
	.ce_pix(ce_pix), .R(R), .G(G), .B(B), .HS(HS), .VS(VS), .HBlank(HBlank), .VBlank(VBlank));
endmodule
