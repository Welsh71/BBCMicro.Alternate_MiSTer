// RAM clear sequencer for "Reset-Mem & SW RAM clear" (OSD).
//
// On a rising edge of start, busy goes high and the sequencer steps addr from 0 to
// WORDS-1, one word per clock, while BBCMicro_Alternate.sv holds the machine in reset and feeds
// addr/zero into the main block RAM write port. With WORDS = 196608 (12 x 16K) that
// covers co-processor RAM (banks 0-3), sideways RAM slots 4-7 (banks 4-7), main memory
// (banks 8-9) and the Master's filing system/private/shadow RAM, which also holds the
// Model B SWMMFS workspace (banks 10-11). At 96 MHz it takes about 2 ms.
//
// A start edge that arrives while busy is ignored; the clear in progress still covers
// every address.

module ram_clear #(
	parameter WORDS = 196608,
	parameter AW    = 18
) (
	input               clk,
	input               start,
	output reg          busy = 1'b0,
	output reg [AW-1:0] addr = {AW{1'b0}}
);

reg start_old = 1'b0;

always @(posedge clk) begin
	start_old <= start;
	if(busy) begin
		if(addr == WORDS - 1) busy <= 1'b0;
		else addr <= addr + 1'd1;
	end
	else if(start & ~start_old) begin
		busy <= 1'b1;
		addr <= {AW{1'b0}};
	end
end

endmodule
