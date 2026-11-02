// Testbench for rtl/ram_clear.v and the RAM write-port mux in BBCMicro.sv.
// The write port below is a copy of BBCMicro.sv's (ram_we_r/ram_waddr_r/ram_wdata_r);
// keep the two in step.
`timescale 1ns/1ps

module tb;

localparam WORDS = 196608;

reg clk = 0;
always #5 clk = ~clk;

reg        start = 0;
wire       busy;
wire [17:0] clr_addr;

ram_clear #(.WORDS(WORDS)) dut (.clk(clk), .start(start), .busy(busy), .addr(clr_addr));

// CPU-side write request (one-cycle strobe, as mem_addr[18] & old_we & ~mem_we_n)
reg        cpu_we = 0;
reg [17:0] cpu_addr = 0;
reg  [7:0] cpu_din = 0;

reg        ram_we_r;
reg [17:0] ram_waddr_r;
reg  [7:0] ram_wdata_r;
always @(posedge clk) begin
	ram_we_r    <= busy | cpu_we;
	ram_waddr_r <= busy ? clr_addr : cpu_addr;
	ram_wdata_r <= busy ? 8'd0 : cpu_din;
end

reg [7:0] ram[0:WORDS-1];
always @(posedge clk) if(ram_we_r) ram[ram_waddr_r] <= ram_wdata_r;

wire reset = start | busy;

integer i, errors, cycles, nz;
integer fails = 0;

task check(input cond, input [8*96-1:0] msg);
	begin
		if(cond) $display("PASS  %0s", msg);
		else begin $display("FAIL  %0s", msg); fails = fails + 1; end
	end
endtask

task cpu_write(input [17:0] a, input [7:0] d);
	begin
		@(negedge clk); cpu_addr = a; cpu_din = d; cpu_we = 1;
		@(negedge clk); cpu_we = 0;
	end
endtask

// Hold start high for n cycles (hps_io holds a trigger bit for a while), count busy cycles
task run_clear(input integer hold);
	begin
		cycles = 0;
		@(negedge clk); start = 1;
		fork
			begin repeat(hold) @(negedge clk); start = 0; end
			begin
				@(posedge busy);
				while(busy) begin @(negedge clk); if(busy) cycles = cycles + 1; end
			end
		join
		repeat(4) @(posedge clk);
	end
endtask

task count_nonzero;
	begin
		nz = 0;
		for(i = 0; i < WORDS; i = i + 1) if(ram[i] !== 8'd0) nz = nz + 1;
	end
endtask

initial begin
	// Power-up state: uninitialised RAM, then "loaded ROMs" everywhere
	for(i = 0; i < WORDS; i = i + 1) ram[i] = (i * 37 + 11) | 8'h01;
	repeat(5) @(posedge clk);
	check(!busy, "idle after power-up");

	// 1: clear with a short trigger
	run_clear(3);
	$display("      busy cycles = %0d", cycles);
	check(cycles == WORDS, "busy lasts exactly 196608 cycles (2.05 ms at 96 MHz)");
	count_nonzero;
	check(nz == 0, "all 12 banks read back zero (co-pro, SW RAM 4-7, main, Master/SWMMFS)");
	check(ram[16'h4000 * 4 + 7] == 0, "slot 4 copyright offset (&8007) is zero");

	// 2: normal writes work after the clear
	cpu_write(18'h20000, 8'hA5);   // main memory &0000
	cpu_write(18'h1C000, 8'h5A);   // slot 7 &8000
	repeat(3) @(posedge clk);
	check(ram[18'h20000] == 8'hA5 && ram[18'h1C000] == 8'h5A, "CPU writes land after clear");

	// 3: trigger held high for longer than the clear itself: one clear, no retrigger
	for(i = 0; i < WORDS; i = i + 1) ram[i] = 8'hFF;
	run_clear(WORDS + 1000);
	check(cycles == WORDS, "long trigger: single clear");
	repeat(20) @(posedge clk);
	check(!busy, "long trigger: no retrigger while held");
	count_nonzero;
	check(nz == 0, "long trigger: all zero");

	// 4: CPU write strobes during the clear are overridden (machine is in reset anyway)
	for(i = 0; i < WORDS; i = i + 1) ram[i] = 8'h77;
	@(negedge clk); start = 1;
	@(posedge busy);
	@(negedge clk); start = 0;
	repeat(1000) @(negedge clk);
	cpu_addr = 18'h00000; cpu_din = 8'h99; cpu_we = 1;   // address the clear has already passed
	repeat(5) @(negedge clk);
	cpu_we = 0;
	check(reset, "reset held while clearing");
	@(negedge busy);
	repeat(4) @(posedge clk);
	count_nonzero;
	check(nz == 0, "CPU writes during clear do not survive");
	check(!reset, "reset released after clear");

	if(fails == 0) $display("ALL TESTS PASSED");
	else $display("%0d TEST(S) FAILED", fails);
	$finish;
end

endmodule
