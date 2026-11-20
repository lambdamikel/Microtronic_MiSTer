// TMS1600 CPU core for the Busch Microtronic 2090.
//
// Runs the original mask ROM, one instruction per `step` pulse.  The
// semantics are a line-by-line port of the browser emulator's core
// (microtronic-emulator, js/tms1600.js), which follows Jason T. Jacques'
// TMS1000-family emulator; the two are checked against each other in
// lockstep (sim/).
//
// An instruction takes three clocks: IDLE (wait for step) -> FETCH (the ROM
// reads {chapter, page, pc}) -> EXEC.  `ostrobe` pulses in the clock after an
// instruction that changed O or an R line, so the board can write the 2114.

module tms1600
(
	input             clk,
	input             reset,      // synchronous; keeps the RAM (like the CPU's INIT pin)
	input             step,       // execute one instruction
	input       [3:0] k,          // K inputs, sampled in EXEC
	output reg  [7:0] o,          // O outputs (through the output PLA)
	output reg [15:0] r,          // R outputs
	output reg        ostrobe,    // O or R changed in the instruction just executed
	output reg        fetch       // high in the FETCH clock of each instruction
);

// ---- ROM: 4096 x 8, address {chapter[1:0], page[3:0], pc[5:0]} ----
reg [7:0] rom[0:4095];
initial $readmemh("rtl/microtronic_rom.hex", rom);

// ---- RAM: 8 files x 16 nibbles ----
reg [3:0] ram[0:127];
integer i;
initial for (i = 0; i < 128; i = i + 1) ram[i] = 4'd0;

// ---- registers ----
reg  [5:0] pc;            // LFSR program counter
reg  [3:0] pa, pb;        // page address / page buffer
reg  [1:0] ca, cb;        // chapter address / chapter buffer
reg  [2:0] x;
reg  [3:0] y, a;
reg        s, sl;         // status, status latch
reg  [5:0] sr0, sr1, sr2; // 3-level subroutine stack
reg  [3:0] psr0, psr1, psr2;
reg  [1:0] csr0, csr1, csr2;
reg        cl0, cl1, cl2; // call latches

localparam IDLE = 2'd0, FETCH = 2'd1, EXEC = 2'd2;
reg  [1:0] st;
reg  [7:0] inst;

always @(posedge clk) inst <= rom[{ca, pa, pc}];

// next value of the 6-bit LFSR
wire       fb  = (pc == 6'h1f) ? 1'b1 : (pc == 6'h3f) ? 1'b0 : (pc[5] == pc[4]);
wire [5:0] pcn = {pc[4:0], fb};

function [3:0] rev4(input [3:0] b); rev4 = {b[0], b[1], b[2], b[3]}; endfunction
function [2:0] rev3(input [2:0] b); rev3 = {b[0], b[1], b[2]}; endfunction
function [1:0] rev2(input [1:0] b); rev2 = {b[0], b[1]}; endfunction

// output PLA: SL=0 raw nibble, SL=1 seven-segment glyph (O0=a .. O6=g, O7=dp)
function [7:0] opla(input sel, input [3:0] v);
	if (!sel) opla = {4'd0, v};
	else case (v)
		4'h0: opla = 8'h3f; 4'h1: opla = 8'h06; 4'h2: opla = 8'h5b; 4'h3: opla = 8'h4f;
		4'h4: opla = 8'h66; 4'h5: opla = 8'h6d; 4'h6: opla = 8'h7d; 4'h7: opla = 8'h07;
		4'h8: opla = 8'h7f; 4'h9: opla = 8'h6f; 4'ha: opla = 8'h77; 4'hb: opla = 8'hfc;
		4'hc: opla = 8'h39; 4'hd: opla = 8'h5e; 4'he: opla = 8'h79; default: opla = 8'h71;
	endcase
endfunction

wire [6:0] mi = {x, y};
wire [3:0] m  = ram[mi];
wire [4:0] mpa = {1'b0, m} + {1'b0, a};                  // AMAAC
wire [4:0] acc = {1'b0, a} + {1'b0, rev4(inst[3:0])} + 5'd1;   // ACxAC

always @(posedge clk) begin
	ostrobe <= 1'b0;
	fetch   <= 1'b0;
	if (reset) begin
		pc <= 0; pa <= 4'hf; pb <= 4'hf; ca <= 0; cb <= 0;
		x <= 0; y <= 0; a <= 0; s <= 0; sl <= 0;
		sr0 <= 0; sr1 <= 0; sr2 <= 0; psr0 <= 0; psr1 <= 0; psr2 <= 0;
		csr0 <= 0; csr1 <= 0; csr2 <= 0; cl0 <= 0; cl1 <= 0; cl2 <= 0;
		o <= 0; r <= 0; st <= IDLE;
	end else case (st)
	IDLE:  if (step) begin st <= FETCH; fetch <= 1'b1; end
	FETCH: st <= EXEC;
	EXEC: begin
		st <= IDLE;
		pc <= pcn;
		if (inst[7:6] == 2'b11) begin                                    // CALL
			if (s) begin
				sr2 <= sr1; sr1 <= sr0; sr0 <= pcn;
				psr2 <= psr1; psr1 <= psr0; psr0 <= pa;
				csr2 <= csr1; csr1 <= csr0; csr0 <= ca;
				cl2 <= cl1; cl1 <= cl0; cl0 <= 1'b1;
				pc <= inst[5:0]; pa <= pb; ca <= cb;
			end else begin cb <= ca; pb <= pa; s <= 1'b1; end
		end else if (inst[7:6] == 2'b10) begin                           // BR
			if (s) begin pa <= pb; ca <= cb; pc <= inst[5:0]; end
			else s <= 1'b1;
		end else case (inst[7:4])
		4'h0: case (inst[3:0])
			4'h0: s <= (m != a);                                           // MNEA
			4'h1: s <= (a <= m);                                           // ALEM
			4'h2: begin s <= (y != a); sl <= (y != a); end                 // YNEA
			4'h3: begin ram[mi] <= a; a <= m; s <= 1'b1; end               // XMA
			4'h4: begin s <= (y >= 1); y <= y - 1'd1; end                  // DYN
			4'h5: begin s <= (y == 15); y <= y + 1'd1; end                 // IYC
			4'h6: begin s <= mpa[4]; a <= mpa[3:0]; end                    // AMAAC
			4'h7: begin s <= (m >= 1); a <= m - 1'd1; end                  // DMAN
			4'h8: begin a <= k; s <= 1'b1; end                             // TKA
			4'h9: begin x <= x ^ 3'd4; s <= 1'b1; end                      // COMX
			4'ha: begin o <= opla(sl, a); ostrobe <= 1'b1; s <= 1'b1; end  // TDO
			4'hb: begin cb <= pb[1:0]; s <= 1'b1; end                      // TPC
			4'hc: begin r[y] <= 1'b0; ostrobe <= 1'b1; s <= 1'b1; end      // RSTR
			4'hd: begin r[y] <= 1'b1; ostrobe <= 1'b1; s <= 1'b1; end      // SETR
			4'he: s <= (k != 0);                                           // KNEZ
			4'hf: begin                                                    // RETN
				if (cl0) begin
					pc <= sr0; sr0 <= sr1; sr1 <= sr2; sr2 <= 0;
					pa <= psr0; pb <= psr0; psr0 <= psr1; psr1 <= psr2; psr2 <= 0;
					ca <= csr0; cb <= csr0; csr0 <= csr1; csr1 <= csr2; csr2 <= 0;
					cl0 <= cl1; cl1 <= cl2; cl2 <= 1'b0;
				end
				s <= 1'b1;
			end
		endcase
		4'h1: begin pb <= rev4(inst[3:0]); s <= 1'b1; end                  // LDP
		4'h2: if (inst[3]) begin x <= rev3(inst[2:0]); s <= 1'b1; end      // LDX
			else case (inst[2:0])
			3'h0: begin y <= a; s <= 1'b1; end                             // TAY
			3'h1: begin a <= m; s <= 1'b1; end                             // TMA
			3'h2: begin y <= m; s <= 1'b1; end                             // TMY
			3'h3: begin a <= y; s <= 1'b1; end                             // TYA
			3'h5: begin ram[mi] <= a; s <= (y == 15); y <= y + 1'd1; end   // TAMIYC
			3'h6: begin ram[mi] <= a; a <= 0; s <= 1'b1; end               // TAMZA
			3'h7: begin ram[mi] <= a; s <= 1'b1; end                       // TAM
			default: s <= 1'b1;                                            // 0x24: not decoded
			endcase
		4'h3: case (inst[3:2])
			2'b00: begin ram[mi] <= m |  (4'd1 << rev2(inst[1:0])); s <= 1'b1; end   // SBIT
			2'b01: begin ram[mi] <= m & ~(4'd1 << rev2(inst[1:0])); s <= 1'b1; end   // RBIT
			2'b10: s <= m[rev2(inst[1:0])];                                           // TBIT
			2'b11: case (inst[1:0])
				2'b00: begin s <= (a <= m); a <= m - a; end                    // SAMAN
				2'b01: begin s <= (a == 0); a <= 4'd0 - a; end                 // CPAIZ
				2'b10: begin s <= (m == 15); a <= m + 1'd1; end                // IMAC
				2'b11: s <= (m != 0);                                          // MNEZ
			endcase
		endcase
		4'h4: begin y <= rev4(inst[3:0]); s <= 1'b1; end                   // TCY
		4'h5: s <= (y != rev4(inst[3:0]));                                 // YNEC
		4'h6: begin ram[mi] <= rev4(inst[3:0]); y <= y + 1'd1; s <= 1'b1; end   // TCMIY
		4'h7: if (inst[3:0] == 4'hf) begin a <= 0; s <= 1'b1; end          // CLA
			else begin s <= acc[4]; a <= acc[3:0]; end                     // ACxAC
		default: ;
		endcase
	end
	default: st <= IDLE;
	endcase
end

endmodule
