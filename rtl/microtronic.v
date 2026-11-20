// Busch Microtronic 2090 board: TMS1600 + 2114 program RAM + keypad,
// six-digit display, inputs/outputs and the 1 Hz clock, wired as in the Busch
// schematic and as modelled by the browser emulator (js/tms1600.js):
//
//   2114 address  = O0..O3 | R0..R3 << 4 | R4 << 8 | R5 << 9  (cells hold inverted data)
//   2114 read     : R11 high -> K inputs = 2114 data
//   2114 write    : R13 high -> cell = ~(R7..R10), whenever O or R change
//   keypad        : columns R0..R5, rows K1..K8; inputs IN1..4 on K while R6 is high
//   display       : digit d lit while R12 and Rd are high; segments = O0..O7
//   outputs 1-4   : high (LED lit) while R7..R10 are low
//   carry / zero  : LEDs on R14 / R15

module microtronic
(
	input             clk,
	input             reset,
	input             step,          // one instruction cycle (the original runs 83 333/s)

	input      [23:0] keys,          // held keys, bit = column*4 + row (see KEYMAP)
	input       [3:0] din,           // levels on inputs 1-4 from switches and red keys
	input      [15:0] patch,         // patch cables: bit o*4+i = output o drives input i
	input       [2:0] clock_in,      // 1 Hz clock cable to input 1-4 (0 = not plugged)

	output      [3:0] dout,          // output levels 1-4 (1 = high)
	output      [3:0] inputs,        // levels on inputs 1-4, with the cables
	output            clk1hz,        // the 1 Hz clock output
	output     [15:0] r,
	output      [7:0] o,
	output            executed,      // one clock after each instruction

	// program loader (text .MIC parsed elsewhere): one 12-bit word per write
	input             ld_we,
	input       [7:0] ld_addr,
	input      [11:0] ld_word,

	// light levels, 0..255, updated every 2048 instruction cycles
	output reg [383:0] seg_level,    // digit on Rd (R5 = leftmost), segment b: [(d*8+b)*8 +: 8]
	output reg  [55:0] led_level     // out 1-4, carry, zero, 1 Hz: [i*8 +: 8]
);

wire [3:0] k;
wire       ostrobe, fetch;

tms1600 cpu
(
	.clk(clk), .reset(reset), .step(step), .k(k),
	.o(o), .r(r), .ostrobe(ostrobe), .fetch(fetch)
);

// ---- 2114: four banks of 256 nibbles, A8/A9 = R4/R5 pick the bank ----
//      bank 0 = opcode nibble, bank 2 = middle nibble, bank 1 = last nibble
reg [3:0] bank0[0:255], bank1[0:255], bank2[0:255], bank3[0:255];
integer i;
initial for (i = 0; i < 256; i = i + 1) begin
	bank0[i] = 4'hf; bank1[i] = 4'hf; bank2[i] = 4'hf; bank3[i] = 4'hf;     // reads back as 000
end

wire [7:0] sa   = {r[3], r[2], r[1], r[0], o[3:0]};
wire [1:0] sb   = {r[5], r[4]};
wire [3:0] sdin = ~{r[10], r[9], r[8], r[7]};

reg  [3:0] q0, q1, q2, q3;
always @(posedge clk) begin
	q0 <= bank0[sa]; q1 <= bank1[sa]; q2 <= bank2[sa]; q3 <= bank3[sa];
end
wire [3:0] sram_q = sb == 2'd0 ? q0 : sb == 2'd1 ? q1 : sb == 2'd2 ? q2 : q3;

// one write port per bank: the loader, or the CPU while R13 is high (after O or R changed)
wire       cpu_we = ostrobe && r[13];
wire [7:0] wa     = ld_we ? ld_addr : sa;
wire       we0    = ld_we || (cpu_we && sb == 2'd0);
wire       we1    = ld_we || (cpu_we && sb == 2'd1);
wire       we2    = ld_we || (cpu_we && sb == 2'd2);
wire       we3    = !ld_we && cpu_we && sb == 2'd3;
wire [3:0] wd0    = ld_we ? ~ld_word[11:8] : sdin;
wire [3:0] wd1    = ld_we ? ~ld_word[3:0]  : sdin;
wire [3:0] wd2    = ld_we ? ~ld_word[7:4]  : sdin;
always @(posedge clk) begin
	if (we0) bank0[wa] <= wd0;
	if (we1) bank1[wa] <= wd1;
	if (we2) bank2[wa] <= wd2;
	if (we3) bank3[wa] <= sdin;
end

// ---- 1 Hz clock: toggles every 41 666 2/3 instruction cycles, i.e. 1 Hz at the original speed ----
reg [16:0] cacc;
reg        cbit;
reg        ex1, ex;
always @(posedge clk) begin
	ex1 <= fetch; ex <= ex1;              // fetch is high in FETCH; ex in the clock after EXEC
	if (reset) ;                          // a reset keeps the clock running, like the emulator
	else if (fetch) begin                 // count the instruction before it executes (cycles++ first)
		if (cacc + 17'd3 >= 17'd125000) begin cacc <= cacc + 17'd3 - 17'd125000; cbit <= ~cbit; end
		else cacc <= cacc + 17'd3;
	end
end
initial begin cacc = 0; cbit = 0; end
assign clk1hz   = cbit;
assign executed = ex;

// ---- K inputs ----
assign dout = ~{r[10], r[9], r[8], r[7]};

reg [3:0] dpatch;
integer pi;
always @* begin
	dpatch = din;
	for (pi = 0; pi < 16; pi = pi + 1)
		if (patch[pi] && dout[pi / 4]) dpatch[pi % 4] = 1'b1;
	if (clock_in != 0 && cbit) dpatch[clock_in - 1'd1] = 1'b1;
end

assign inputs = dpatch;

reg [3:0] kmux;
integer c;
always @* begin
	kmux = 4'd0;
	for (c = 0; c < 6; c = c + 1) if (r[c]) kmux = kmux | keys[c*4 +: 4];
	if (r[6]) kmux = kmux | dpatch;
end
assign k = r[11] ? sram_q : kmux;

// ---- light integration ----
reg [11:0] wcnt;                 // window: 2048 instruction cycles
reg [10:0] scnt[0:47];
reg [10:0] lcnt[0:6];
integer d, b;

function [7:0] level(input [10:0] n);        // duty x 6, saturated: a multiplexed digit (1/6) is full
	reg [12:0] v;
	begin v = {2'b0, n} * 13'd3 >> 2; level = v > 255 ? 8'd255 : v[7:0]; end
endfunction

always @(posedge clk) if (executed) begin
	if (wcnt == 12'd2047) begin
		wcnt <= 0;
		for (i = 0; i < 48; i = i + 1) begin seg_level[i*8 +: 8] <= level(scnt[i]); scnt[i] <= 0; end
		for (i = 0; i < 7;  i = i + 1) begin led_level[i*8 +: 8] <= level(lcnt[i]); lcnt[i] <= 0; end
	end else begin
		wcnt <= wcnt + 1'd1;
		for (d = 0; d < 6; d = d + 1) for (b = 0; b < 8; b = b + 1)
			if (r[12] && r[d] && o[b]) scnt[d*8+b] <= scnt[d*8+b] + 1'd1;
		for (i = 0; i < 4; i = i + 1) if (dout[i]) lcnt[i] <= lcnt[i] + 1'd1;
		if (r[14]) lcnt[4] <= lcnt[4] + 1'd1;
		if (r[15]) lcnt[5] <= lcnt[5] + 1'd1;
		if (cbit)  lcnt[6] <= lcnt[6] + 1'd1;
	end
end
initial begin
	wcnt = 0; seg_level = 0; led_level = 0;
	for (i = 0; i < 48; i = i + 1) scnt[i] = 0;
	for (i = 0; i < 7;  i = i + 1) lcnt[i] = 0;
end

endmodule
