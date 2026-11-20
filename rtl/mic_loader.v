// Loads a .MIC program file as it streams in from the SD card.
//
// The format is the text format of the Busch-2090 software archive and the
// browser emulator: '#' or ';' starts a comment that runs to the end of the
// line, "@ hh" sets the address, and every three-digit hex word is one
// instruction, stored at the address and the address advanced.  Like the
// emulator, it forgives the usual OCR slips: O, o and Q read as 0, I and l as 1.

module mic_loader
(
	input             clk,
	input             download,      // file transfer active
	input             wr,            // byte strobe
	input       [7:0] din,

	output reg        we,            // one clock per instruction word
	output reg  [7:0] addr,
	output reg [11:0] word
);

localparam NORMAL = 2'd0, COMMENT = 2'd1, ADDRESS = 2'd2;
reg  [1:0] st;
reg [11:0] acc;
reg  [2:0] nd;              // digits in acc (saturates at 7)
reg  [7:0] next;            // address of the next word
reg        dl;

wire       isdig = (din >= "0" && din <= "9");
wire       is0   = din == "O" || din == "o" || din == "Q";
wire       is1   = din == "I" || din == "l";
wire       ishex = isdig || is0 || is1 || (din >= "A" && din <= "F") || (din >= "a" && din <= "f");
wire [3:0] hv    = is0 ? 4'd0 : is1 ? 4'd1 : isdig ? din[3:0] : din[3:0] + 4'd9;

always @(posedge clk) begin
	we <= 1'b0;
	dl <= download;
	if (download && !dl) begin st <= NORMAL; acc <= 0; nd <= 0; next <= 0; end
	else if (!download && dl) begin                        // end of file: store a word in progress
		if (st == NORMAL && nd == 3) begin we <= 1'b1; addr <= next; word <= acc; end
	end
	else if (download && wr) begin
		if (st == COMMENT) begin
			if (din == 8'h0a) st <= NORMAL;
		end
		else if (ishex) begin
			acc <= {acc[7:0], hv};
			if (nd != 7) nd <= nd + 1'd1;
		end
		else begin                                         // a delimiter ends a word or an address
			if (st == ADDRESS) begin
				if (nd != 0) begin next <= acc[7:0]; st <= NORMAL; end
				else if (din == 8'h0a) st <= NORMAL;
			end
			else if (nd == 3) begin we <= 1'b1; addr <= next; word <= acc; next <= next + 1'd1; end
			acc <= 0; nd <= 0;
			if (din == "#" || din == ";") st <= COMMENT;
			else if (din == "@") st <= ADDRESS;
		end
	end
end

endmodule
