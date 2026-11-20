//============================================================================
//  Busch Microtronic 2090 for MiSTer
//
//  The 1981 educational computer, running its original TMS1600 firmware ROM.
//  CPU and board are a port of the browser emulator (lambdamikel/microtronic-emulator)
//  and are checked against it in lockstep (sim/).
//
//  Made with Claude Opus 5.5 (Claude Code), together with Michael Wessel.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.  The firmware ROM (rtl/microtronic_rom.hex) remains
//  (c) Busch and is not covered by this licence.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

wire         clk_sys;
wire [127:0] status;

wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

// Status bits:
//  0      reset
//  1-2    speed
//  3-5    1 Hz clock cable
//  6-8    red key G wiring
//  9-11   red key H wiring
//  12-14  piezo buzzer
//  15-17  patch cable from output
//  18-19  patch cable to input

`include "build_id.v"
localparam CONF_STR = {
	"Microtronic;;",
	"-;",
	"F1,MIC,Load program;",
	"-;",
	"O[2:1],Speed,Original,4x,16x,1/4x;",
	"-;",
	"O[5:3],1 Hz clock cable to,Not plugged,Input 1,Input 2,Input 3,Input 4;",
	"O[8:6],Red key G wired to,Input 1,Input 2,Input 3,Input 4,Not wired;",
	"O[11:9],Red key H wired to,Input 2,Input 3,Input 4,Input 1,Not wired;",
	"O[14:12],Piezo buzzer on,Not wired,Output 1,Output 2,Output 3,Output 4;",
	"O[17:15],Patch cable from,Not plugged,Output 1,Output 2,Output 3,Output 4;",
	"O[19:18],Patch cable to,Input 1,Input 2,Input 3,Input 4;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"R[0],Reset;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire   [1:0] buttons;
wire  [10:0] ps2_key;

wire         ioctl_download;
wire  [15:0] ioctl_index;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(1'b0),

	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_sys)        // 50 MHz
);

///////////////////////   KEYBOARD   /////////////////////////////

wire executed;                 // one clock after each instruction cycle

// PC keys as in the browser emulator: 0-9 A-F digits, H HALT, N/Enter/Space NEXT,
// R RUN, S/T STEP, K BKP, G REG, P PGM, Backspace/Delete/X C/CE, Esc reset,
// comma/period the red keys G/H, F1-F4 toggle inputs 1-4.
reg  [23:0] keys = 0;          // held keypad keys, bit = column*4 + row
reg  [23:0] pend = 0;          // releases waiting for the minimum hold time
reg  [15:0] held = 0;          // instruction cycles since the last key press
reg   [1:0] redkeys = 0;       // G, H
reg   [3:0] sw = 0;            // input switches
reg         kbd_reset = 0;
reg         old_stb = 0;

wire        pressed = ps2_key[9];
wire        ext     = ps2_key[8];
wire  [7:0] code    = ps2_key[7:0];

reg   [4:0] kidx;              // keypad key, 24 = none
always @* begin
	kidx = 5'd24;
	if (!ext) case (code)
		8'h45, 8'h70: kidx = 0;            // 0
		8'h16, 8'h69: kidx = 4;            // 1
		8'h1e, 8'h72: kidx = 8;            // 2
		8'h26, 8'h7a: kidx = 12;           // 3
		8'h25, 8'h6b: kidx = 1;            // 4
		8'h2e, 8'h73: kidx = 5;            // 5
		8'h36, 8'h74: kidx = 9;            // 6
		8'h3d, 8'h6c: kidx = 13;           // 7
		8'h3e, 8'h75: kidx = 2;            // 8
		8'h46, 8'h7d: kidx = 6;            // 9
		8'h1c: kidx = 10;                  // A
		8'h32: kidx = 14;                  // B
		8'h21: kidx = 3;                   // C
		8'h23: kidx = 7;                   // D
		8'h24: kidx = 11;                  // E
		8'h2b: kidx = 15;                  // F
		8'h31, 8'h5a, 8'h29: kidx = 19;    // NEXT: N, Enter, Space
		8'h34: kidx = 23;                  // REG: G
		8'h42: kidx = 18;                  // BKP: K
		8'h1b, 8'h2c: kidx = 22;           // STEP: S, T
		8'h2d: kidx = 17;                  // RUN: R
		8'h33: kidx = 21;                  // HALT: H
		8'h4d: kidx = 20;                  // PGM: P
		8'h66, 8'h22: kidx = 16;           // C/CE: Backspace, X
		default: ;
	endcase
	else case (code)
		8'h5a: kidx = 19;                  // keypad Enter: NEXT
		8'h71: kidx = 16;                  // Delete: C/CE
		default: ;
	endcase
end

always @(posedge clk_sys) begin
	kbd_reset <= 1'b0;
	old_stb <= ps2_key[10];
	if (executed && held != 16'hffff) held <= held + 1'd1;
	if (held >= 16'd5000 && pend != 0) begin keys <= keys & ~pend; pend <= 0; end   // hold at least ~60 ms so the firmware's scan sees it
	if (old_stb != ps2_key[10]) begin
		if (kidx != 24) begin
			if (pressed) begin keys[kidx] <= 1'b1; pend[kidx] <= 1'b0; held <= 0; end
			else if (held >= 16'd5000) keys[kidx] <= 1'b0;
			else pend[kidx] <= 1'b1;
		end
		if (!ext) case (code)
			8'h76: if (pressed) kbd_reset <= 1'b1;        // Esc
			8'h41: redkeys[0] <= pressed;                 // , = red key G
			8'h49: redkeys[1] <= pressed;                 // . = red key H
			8'h05: if (pressed) sw[0] <= ~sw[0];          // F1-F4: input switches
			8'h06: if (pressed) sw[1] <= ~sw[1];
			8'h04: if (pressed) sw[2] <= ~sw[2];
			8'h0c: if (pressed) sw[3] <= ~sw[3];
			default: ;
		endcase
	end
end

///////////////////////   MACHINE   //////////////////////////////

wire reset = RESET | status[0] | buttons[1] | kbd_reset;

// instruction cycles: 83 333/s at the original speed = one every 600 clocks
// (accumulate 4 per clock against 2400: 1, 4, 16 or 1/4 times that rate)
reg [11:0] sacc = 0;
reg        step = 0;
wire [6:0] sinc = status[2:1] == 2'd0 ? 7'd4 : status[2:1] == 2'd1 ? 7'd16 : status[2:1] == 2'd2 ? 7'd64 : 7'd1;
always @(posedge clk_sys) begin
	step <= 1'b0;
	if (sacc + sinc >= 12'd2400) begin sacc <= sacc + sinc - 12'd2400; step <= 1'b1; end
	else sacc <= sacc + sinc;
end

// red keys and switches on the inputs (the keys pull their input high through the 4.7 kOhm resistor)
wire [2:0] gsel = status[8:6];
wire [2:0] hsel = status[11:9] == 3'd4 ? 3'd4 : status[11:9] == 3'd3 ? 3'd0 : status[11:9] + 1'd1;
reg  [3:0] din;
always @* begin
	din = sw;
	if (redkeys[0] && gsel < 4) din[gsel[1:0]] = 1'b1;
	if (redkeys[1] && hsel < 4) din[hsel[1:0]] = 1'b1;
end

wire [15:0] patch = status[17:15] == 0 ? 16'd0 : 16'd1 << ((status[17:15] - 1'd1) * 4 + status[19:18]);

wire         ld_we;
wire   [7:0] ld_addr;
wire  [11:0] ld_word;

mic_loader loader
(
	.clk(clk_sys),
	.download(ioctl_download && ioctl_index[5:0] == 6'd1),
	.wr(ioctl_wr),
	.din(ioctl_dout),
	.we(ld_we), .addr(ld_addr), .word(ld_word)
);

wire   [3:0] dout, inputs;
wire         clk1hz;
wire [383:0] seg_level;
wire  [55:0] led_level;

microtronic board
(
	.clk(clk_sys),
	.reset(reset),
	.step(step),
	.keys(keys),
	.din(din),
	.patch(patch),
	.clock_in(status[5:3] > 3'd4 ? 3'd0 : status[5:3]),
	.dout(dout),
	.inputs(inputs),
	.clk1hz(clk1hz),
	.r(), .o(),
	.executed(executed),
	.ld_we(ld_we), .ld_addr(ld_addr), .ld_word(ld_word),
	.seg_level(seg_level),
	.led_level(led_level)
);

///////////////////////   VIDEO   ////////////////////////////////

wire ce_pix, HBlank, VBlank, HSync, VSync;
wire [7:0] r, g, b;

video video
(
	.clk(clk_sys),
	.seg_level(seg_level),
	.led_level(led_level),
	.keys(keys),
	.redkeys(redkeys),
	.inputs(inputs),
	.ce_pix(ce_pix),
	.R(r), .G(g), .B(b),
	.HS(HSync), .VS(VSync), .HBlank(HBlank), .VBlank(VBlank)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_DE    = ~(HBlank | VBlank);
assign VGA_HS    = HSync;
assign VGA_VS    = VSync;
assign VGA_R     = r;
assign VGA_G     = g;
assign VGA_B     = b;

///////////////////////   SOUND   ////////////////////////////////

// piezo buzzer: a fixed 2.4 kHz tone while its output is high
reg [13:0] bdiv = 0;
reg        bsq = 0;
always @(posedge clk_sys) begin
	if (bdiv == 14'd10416) begin bdiv <= 0; bsq <= ~bsq; end
	else bdiv <= bdiv + 1'd1;
end
wire [2:0] psel = status[14:12];
wire       buzz = psel != 0 && psel <= 4 && dout[psel[1:0] - 1'd1];
wire [15:0] snd = buzz ? (bsq ? 16'h1000 : 16'hf000) : 16'h0000;

assign AUDIO_S   = 1;
assign AUDIO_L   = snd;
assign AUDIO_R   = snd;
assign AUDIO_MIX = 0;

assign LED_USER  = clk1hz;

endmodule
