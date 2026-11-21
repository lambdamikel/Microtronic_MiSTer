// 640x480 picture of the Microtronic console: I/O strip with output LEDs and
// input jacks, badge, carry/zero LEDs, the six-digit display, the red keys G/H
// and the keypad.  Shapes are drawn here; labels come from a text layer
// (rtl/text.hex, 80x30 cells of 8x16, made by tools/mklayout.py, whose
// column/row positions match the coordinates below).

module video
(
	input              clk,           // 50 MHz; one pixel every second clock
	input      [383:0] seg_level,     // digit on Rd (R5 = leftmost), segment b: [(d*8+b)*8 +: 8]
	input       [55:0] led_level,     // out 1-4, carry, zero, 1 Hz
	input       [23:0] keys,          // held keypad keys, bit = column*4 + row
	input        [1:0] redkeys,       // G, H held
	input        [3:0] inputs,        // levels on inputs 1-4

	output reg         ce_pix,
	output reg   [7:0] R, G, B,
	output reg         HS, VS, HBlank, VBlank
);

// ---- timing: 640x480, 800x525 total, 25 MHz pixel clock (59.5 Hz) ----
reg [9:0] h0 = 0, v0 = 0;
always @(posedge clk) ce_pix <= ~ce_pix;
initial ce_pix = 0;

always @(posedge clk) if (ce_pix) begin
	if (h0 == 799) begin h0 <= 0; v0 <= (v0 == 524) ? 10'd0 : v0 + 1'd1; end
	else h0 <= h0 + 1'd1;
end

// ---- text layer pipeline: h0 -> text cell (h1) -> glyph row (h2) -> pixel (out) ----
// A cell is {shift, colour[2:0], char[7:0]}.  A cell with the shift bit is drawn 4 pixels to
// the right, so that labels with an even number of characters can be centred exactly.  Each
// pixel looks at two cells: its own (A) and the one 4 pixels to the left (B); a shifted B wins,
// an unshifted A comes next, and otherwise the pixel is the gap left by a shifted A.
reg [11:0] text[0:4095];        // 80x30 used; padded so rows 30-32 of the blanking read spaces
reg  [7:0] font[0:4095];
initial $readmemh("rtl/text.hex", text);
initial $readmemh("rtl/font.hex", font);

reg [11:0] tq, tqb;
reg  [7:0] fq, fqb;
reg  [3:0] tcol, tcolb;
reg  [9:0] h1, v1, h2, v2;
wire [11:0] trow   = {v0[8:4], 6'd0} + {2'd0, v0[8:4], 4'd0};      // row*80
wire  [9:0] hb     = h0 - 10'd4;
wire [11:0] taddr  = trow + {5'd0, h0[9:3]};
wire [11:0] taddrb = (h0 < 4) ? 12'd4095 : trow + {5'd0, hb[9:3]};  // 4095 is padding (a space)

always @(posedge clk) if (ce_pix) begin
	tq  <= text[taddr];
	tqb <= text[taddrb];
	h1 <= h0; v1 <= v0;
	fq  <= font[{tq[7:0],  v1[3:0]}];
	fqb <= font[{tqb[7:0], v1[3:0]}];
	tcol  <= tq[11:8];
	tcolb <= tqb[11:8];
	h2 <= h1; v2 <= v1;
end

// ---- helpers ----
function [7:0] mix(input [7:0] off, input [7:0] on, input [7:0] lvl);   // off + (on-off)*lvl/256
	reg [15:0] p;
	begin p = (on - off) * lvl; mix = off + p[15:8]; end
endfunction

function [7:0] sq(input [3:0] v); sq = v * v; endfunction

// inside a circle of squared radius r2 around (cx, cy); radius at most 15
function circ(input [9:0] x, input [9:0] y, input [9:0] cx, input [9:0] cy, input [8:0] r2);
	reg [10:0] dx, dy;
	reg  [3:0] ax, ay;
	begin
		dx = {1'b0, x} - {1'b0, cx}; dy = {1'b0, y} - {1'b0, cy};
		ax = dx[10] ? -dx[3:0] : dx[3:0]; ay = dy[10] ? -dy[3:0] : dy[3:0];
		if ((dx[10] ? (-dx > 11'd15) : (dx > 11'd15)) || (dy[10] ? (-dy > 11'd15) : (dy > 11'd15))) circ = 1'b0;
		else circ = ({1'b0, sq(ax)} + {1'b0, sq(ay)}) <= r2;
	end
endfunction

function inbox(input [9:0] x, input [9:0] y, input [9:0] x0, input [9:0] y0, input [9:0] x1, input [9:0] y1);
	inbox = x >= x0 && x <= x1 && y >= y0 && y <= y1;
endfunction

// ---- the picture ----
localparam [23:0] C_BG    = 24'h262628, C_CASE  = 24'h161618, C_STRIP = 24'hc9c9c6,
                  C_SOCK  = 24'h2a2a2a, C_HOLE  = 24'h060606, C_PEG   = 24'hf2c21a,
                  C_BADGE = 24'hd8d8d4, C_FRAME = 24'h5a5a5a, C_BEZEL = 24'h38383a, C_WIN = 24'h1a0404,
                  C_PAD   = 24'hc8c8c4, C_KEY   = 24'h1c1c1e, C_KEYDN = 24'h9a2a22, C_DIV   = 24'h909090,
                  C_RKEY  = 24'hd83c3c, C_RKDN  = 24'hff8c80, C_RKFR  = 24'h401010, C_LEDRIM = 24'h3a0c0c,
                  C_KEYHI = 24'h4a4a50, C_KEYLO = 24'h060606;

// keypad columns: hex keys 0-3 from x = 356, function keys 4-5 from x = 532 (a 24-pixel gap);
// key centres are 8*col + 4 for the text columns 46 51 56 61 | 68 73 used by tools/mklayout.py
function [9:0] keyx(input [2:0] c); keyx = (c < 4) ? 10'd356 + 40*c : 10'd532 + 40*(c - 4); endfunction

// LED red: dark when off, bright when the level is 255
function [23:0] ledc(input [7:0] lvl);
	ledc = {mix(8'h48, 8'hff, lvl), mix(8'h0a, 8'h40, lvl), mix(8'h0a, 8'h30, lvl)};
endfunction

// strip: socket centres (x) at text columns 5 | 12 16 20 24 | 36 40 44 48 | 58 | 70
localparam [9:0] SY = 88, LY = 56;
function [9:0] colx(input [6:0] c); colx = {c, 3'd4}; endfunction
function [6:0] sockcol(input [3:0] i);      // GND, outputs 1-4, inputs 1-4, clock, GND
	sockcol = (i == 0) ? 7'd5 : (i < 5) ? 7'd12 + 4*(i-1) : (i < 9) ? 7'd36 + 4*(i-5) : (i == 9) ? 7'd58 : 7'd70;
endfunction

// left panel (x 16..343, between the console edge and the keypad): badge, carry/zero LEDs with
// the display, and the red keys, each centred on x = 180 (text column 22)
// display digits: x = 62 + 40*d; the slanted ink of all six (with the last dp) spans 62..298,
// 12 pixels inside the window on either side; y = 226..281
localparam [9:0] DX0 = 62, DY0 = 226;

reg [23:0] ledrgb[0:6];        // out 1-4, carry, zero, 1 Hz: colours, computed outside the pixel path
integer li;
always @(posedge clk) for (li = 0; li < 7; li = li + 1) ledrgb[li] <= ledc(led_level[li*8 +: 8]);

reg [23:0] px;
reg  [2:0] d;
reg  [9:0] lx, ly;
reg [10:0] lxs;
reg  [3:0] sg;          // segment hit: 0..7, 8 = none
reg  [7:0] lvl;
reg        tbit;
reg  [2:0] tc;
integer i, kc, kr;

always @* begin
	px = C_BG;
	// I/O strip
	if (inbox(h2, v2, 16, 16, 623, 111)) px = C_STRIP;
	// outputs: LED above, socket below
	for (i = 0; i < 4; i = i + 1) begin
		if (circ(h2, v2, colx(12 + 4*i), LY, 64)) px = C_LEDRIM;
		if (circ(h2, v2, colx(12 + 4*i), LY, 42)) px = ledrgb[i];
	end
	if (circ(h2, v2, colx(58), LY, 64)) px = C_LEDRIM;
	if (circ(h2, v2, colx(58), LY, 42)) px = ledrgb[6];
	for (i = 0; i < 11; i = i + 1) begin
		if (circ(h2, v2, colx(sockcol(i)), SY, 64)) px = C_SOCK;
		if (circ(h2, v2, colx(sockcol(i)), SY, 16)) px = C_HOLE;
	end
	for (i = 0; i < 4; i = i + 1)              // a plug in each input jack that is high
		if (inputs[i] && circ(h2, v2, colx(36 + 4*i), SY, 42))
			px = circ(h2, v2, colx(36 + 4*i) - 2, SY - 2, 4) ? 24'hfff0a0 : C_PEG;
	// console
	if (inbox(h2, v2, 16, 128, 623, 463)) px = C_CASE;
	// badge
	if (inbox(h2, v2, 100, 140, 259, 183)) px = inbox(h2, v2, 102, 142, 257, 181) ? C_BADGE : C_FRAME;
	// carry / zero LEDs (row 12, columns 14 and 25; the labels follow them)
	if (circ(h2, v2, colx(14), 200, 49)) px = C_LEDRIM;
	if (circ(h2, v2, colx(14), 200, 30)) px = ledrgb[4];
	if (circ(h2, v2, colx(25), 200, 49)) px = C_LEDRIM;
	if (circ(h2, v2, colx(25), 200, 30)) px = ledrgb[5];
	// display window
	if (inbox(h2, v2, 46, 212, 314, 295)) px = inbox(h2, v2, 50, 216, 310, 291) ? C_WIN : C_BEZEL;
	sg = 4'd8; d = 0; lx = 0; ly = 0; lxs = 0; lvl = 0;
	if (h2 >= DX0 && h2 < DX0 + 240 && v2 >= DY0 && v2 < DY0 + 56) begin
		d  = (h2 < DX0 + 40) ? 3'd0 : (h2 < DX0 + 80) ? 3'd1 : (h2 < DX0 + 120) ? 3'd2 :
		     (h2 < DX0 + 160) ? 3'd3 : (h2 < DX0 + 200) ? 3'd4 : 3'd5;
		lx = h2 - DX0 - 40 * d;
		ly = v2 - DY0;
		lxs = {1'b0, lx} - ((11'd55 - {1'b0, ly}) >> 3);          // slanted to the right, like the real display
		if (!lxs[10]) begin
			if      (ly <= 4  && lxs >= 4  && lxs <= 25) sg = 0;                  // a
			else if (ly >= 51 && lxs >= 4  && lxs <= 25) sg = 3;                  // d
			else if (ly >= 25 && ly <= 30 && lxs >= 4 && lxs <= 25) sg = 6;       // g
			else if (lxs >= 25 && lxs <= 29 && ly >= 2  && ly <= 27) sg = 1;      // b
			else if (lxs >= 25 && lxs <= 29 && ly >= 28 && ly <= 53) sg = 2;      // c
			else if (lxs <= 4  && ly >= 28 && ly <= 53) sg = 4;                   // e
			else if (lxs <= 4  && ly >= 2  && ly <= 27) sg = 5;                   // f
			else if (lxs >= 32 && lxs <= 36 && ly >= 50) sg = 7;                  // dp
		end
		if (sg != 8) begin
			lvl = seg_level[{3'd5 - d, sg[2:0], 3'd0} +: 8];          // the leftmost digit is on R5
			px = {mix(8'h3c, 8'hff, lvl), mix(8'h08, 8'h3a, lvl), mix(8'h08, 8'h28, lvl)};
		end
	end
	// red keys G (centre column 16) and H (column 28)
	if (inbox(h2, v2, 108, 336, 155, 383)) px = inbox(h2, v2, 111, 339, 152, 380) ? (redkeys[0] ? C_RKDN : C_RKEY) : C_RKFR;
	if (inbox(h2, v2, 204, 336, 251, 383)) px = inbox(h2, v2, 207, 339, 248, 380) ? (redkeys[1] ? C_RKDN : C_RKEY) : C_RKFR;
	// keypad: hex block (4 columns from KX0) and, after a wider gap with a divider, the
	// function block (2 columns from KXF); keys 32x32, 40 apart, rows 80 apart
	if (inbox(h2, v2, 344, 136, 615, 447)) px = C_PAD;
	if (inbox(h2, v2, 519, 144, 520, 439)) px = C_DIV;
	for (kr = 0; kr < 4; kr = kr + 1)
		for (kc = 0; kc < 6; kc = kc + 1)
			if (inbox(h2, v2, keyx(kc), 164 + 80*kr, keyx(kc) + 31, 195 + 80*kr))
				px = keys[kc*4 + 3 - kr] ? C_KEYDN :
				     (v2 <= 165 + 80*kr || h2 <= keyx(kc) + 1) ? C_KEYHI :          // bevel: lit top/left,
				     (v2 >= 193 + 80*kr || h2 >= keyx(kc) + 29) ? C_KEYLO : C_KEY;  // dark bottom/right
	// text on top
	if (tcolb[3])      begin tbit = fqb[~(h2[2:0] ^ 3'd4)]; tc = tcolb[2:0]; end
	else if (!tcol[3]) begin tbit = fq[~h2[2:0]];           tc = tcol[2:0];  end
	else               begin tbit = 1'b0;                   tc = 3'd0;       end
	if (tbit && v2 < 480 && h2 < 640) case (tc)
		4'd0: px = 24'h141414;
		4'd1: px = 24'hd8d8d8;
		4'd2: px = 24'h8a8a8e;
		4'd3: px = 24'hffffff;
		default: px = 24'hf2c21a;
	endcase
end

always @(posedge clk) if (ce_pix) begin
	{R, G, B} <= (h2 < 640 && v2 < 480) ? px : 24'h000000;
	HBlank <= h2 >= 640;
	VBlank <= v2 >= 480;
	HS <= h2 >= 656 && h2 < 752;
	VS <= v2 >= 490 && v2 < 492;
end

endmodule
