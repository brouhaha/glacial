// RISC-V RV32I core design for minimal FPGA resource utilization

/*
 * Copyright 2018 Eric Smith <spacewar@gmail.com>
 *
 * Reistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

`timescale 1 ns / 1 ps

module testbench(
`ifdef VERILATOR
    input clk
`endif
);

wire [15:0] mem_addr;
wire        mem_rd_en;
wire  [7:0] mem_rd_data;
wire        mem_wr_en;
wire  [7:0] mem_wr_data;
wire        xint;
wire        xtick;
wire        uart_tx;

reg 	    reset = 1;

`ifdef VERILATOR
  always @(negedge clk) begin
     reset = 0;
  end
`endif
   
`ifndef VERILATOR
   reg [31:0] cycle = 0;
   reg 	  clk = 0;
   always #10 begin
     if (clk) begin
       clk = 0;
       reset = 0;
`define TRACE
`ifdef TRACE
       if ((g0.phase == 3) && (g0.pc == 11'h0f4))
	 begin
	   $display("cycle %d", cycle);
	   $display("                   x1/ra=%02x%02x%02x%02x   x2/sp=%02x%02x%02x%02x   x3/gp=%02x%02x%02x%02x",
		    r0.mem[16'h007], r0.mem[16'h006], r0.mem[16'h005], r0.mem[16'h004],
		    r0.mem[16'h00b], r0.mem[16'h00a], r0.mem[16'h009], r0.mem[16'h008],
		    r0.mem[16'h00f], r0.mem[16'h00e], r0.mem[16'h00d], r0.mem[16'h00c]);
	   $display("  x4/tp=%02x%02x%02x%02x   x5/t0=%02x%02x%02x%02x   x6/t1=%02x%02x%02x%02x   x7/t2=%02x%02x%02x%02x",
		    r0.mem[16'h013], r0.mem[16'h012], r0.mem[16'h011], r0.mem[16'h010],
		    r0.mem[16'h017], r0.mem[16'h016], r0.mem[16'h015], r0.mem[16'h014],
		    r0.mem[16'h01b], r0.mem[16'h01a], r0.mem[16'h019], r0.mem[16'h018],
		    r0.mem[16'h01f], r0.mem[16'h01e], r0.mem[16'h01d], r0.mem[16'h01c]);
	   $display("  x8/s0=%02x%02x%02x%02x   x9/s1=%02x%02x%02x%02x  x10/a0=%02x%02x%02x%02x  x11/a1=%02x%02x%02x%02x",
		    r0.mem[16'h023], r0.mem[16'h022], r0.mem[16'h021], r0.mem[16'h020],
		    r0.mem[16'h027], r0.mem[16'h026], r0.mem[16'h025], r0.mem[16'h024],
		    r0.mem[16'h02b], r0.mem[16'h02a], r0.mem[16'h029], r0.mem[16'h028],
		    r0.mem[16'h02f], r0.mem[16'h02e], r0.mem[16'h02d], r0.mem[16'h02c]);
	   $display(" x12/a2=%02x%02x%02x%02x  x13/a3=%02x%02x%02x%02x  x14/a4=%02x%02x%02x%02x  x15/a5=%02x%02x%02x%02x",
		    r0.mem[16'h033], r0.mem[16'h032], r0.mem[16'h031], r0.mem[16'h030],
		    r0.mem[16'h037], r0.mem[16'h036], r0.mem[16'h035], r0.mem[16'h034],
		    r0.mem[16'h03b], r0.mem[16'h03a], r0.mem[16'h039], r0.mem[16'h038],
		    r0.mem[16'h03f], r0.mem[16'h03e], r0.mem[16'h03d], r0.mem[16'h03c]);
	   $display(" x16/a6=%02x%02x%02x%02x  x17/a7=%02x%02x%02x%02x  x18/s2=%02x%02x%02x%02x  x19/s3=%02x%02x%02x%02x",
		    r0.mem[16'h043], r0.mem[16'h042], r0.mem[16'h041], r0.mem[16'h040],
		    r0.mem[16'h047], r0.mem[16'h046], r0.mem[16'h045], r0.mem[16'h044],
		    r0.mem[16'h04b], r0.mem[16'h04a], r0.mem[16'h049], r0.mem[16'h048],
		    r0.mem[16'h04f], r0.mem[16'h04e], r0.mem[16'h04d], r0.mem[16'h04c]);
	   $display(" x20/s4=%02x%02x%02x%02x  x21/s5=%02x%02x%02x%02x  x22/s6=%02x%02x%02x%02x  x23/s7=%02x%02x%02x%02x",
		    r0.mem[16'h053], r0.mem[16'h052], r0.mem[16'h051], r0.mem[16'h050],
		    r0.mem[16'h057], r0.mem[16'h056], r0.mem[16'h055], r0.mem[16'h054],
		    r0.mem[16'h05b], r0.mem[16'h05a], r0.mem[16'h059], r0.mem[16'h058],
		    r0.mem[16'h05f], r0.mem[16'h05e], r0.mem[16'h05d], r0.mem[16'h05c]);
	   $display(" x24/s8=%02x%02x%02x%02x  x25/s9=%02x%02x%02x%02x x26/s10=%02x%02x%02x%02x x27/s11=%02x%02x%02x%02x",
		    r0.mem[16'h063], r0.mem[16'h062], r0.mem[16'h061], r0.mem[16'h060],
		    r0.mem[16'h067], r0.mem[16'h066], r0.mem[16'h065], r0.mem[16'h064],
		    r0.mem[16'h06b], r0.mem[16'h06a], r0.mem[16'h069], r0.mem[16'h068],
		    r0.mem[16'h06f], r0.mem[16'h06e], r0.mem[16'h06d], r0.mem[16'h06c]);
	   $display(" x28/t3=%02x%02x%02x%02x  x29/t4=%02x%02x%02x%02x  x30/t5=%02x%02x%02x%02x  x31/t6=%02x%02x%02x%02x",
		    r0.mem[16'h073], r0.mem[16'h072], r0.mem[16'h071], r0.mem[16'h070],
		    r0.mem[16'h077], r0.mem[16'h076], r0.mem[16'h075], r0.mem[16'h074],
		    r0.mem[16'h07b], r0.mem[16'h07a], r0.mem[16'h079], r0.mem[16'h078],
		    r0.mem[16'h07f], r0.mem[16'h07e], r0.mem[16'h07d], r0.mem[16'h07c]);
	   $display("mpc=%02x%02x%02x%02x ir=%02x%02x%02x%02x",
		    r0.mem[16'h00cb],
		    r0.mem[16'h00ca],
		    r0.mem[16'h00c9],
		    r0.mem[16'h00c8],
		    r0.mem[16'h00cf],
		    r0.mem[16'h00ce],
		    r0.mem[16'h00cd],
		    r0.mem[16'h00cc]);
	 end
       $display("ph=%d mre=%d mad=%04x mrd=%02x mwe=%d mwd=%02x ac=%02x c=%d x=%02x y=%04x", g0.phase, mem_rd_en, mem_addr, mem_rd_data, mem_wr_en, mem_wr_data, g0.ac, g0.cy, g0.x, g0.y);
       $display("xsel=%d ysel=%d", g0.x_sel, g0.y_sel);
       $display("ac_sel=%d, alu_b=%02x alu_out=%02x", g0.ac_sel, g0.alu_b, g0.alu_out);
       //if (g0.phase == 2)
       //  $display("pc=%04x ir=%04x", (g0.pc << 1) - 2, g0.ir);
       if ((g0.phase == 3) && (g0.pc == 11'h4d5)) begin
         $display("cycle %d", cycle);
	 $display("uart %02x", g0.ac);
       end
`endif
     end else begin
       clk = 1;
       cycle += 1;
     end
   end
`endif

glacial g0(
  .clk         (clk),
  .reset       (reset),
  .mem_addr    (mem_addr),
  .mem_rd_en   (mem_rd_en),
  .mem_rd_data (mem_rd_data),
  .mem_wr_en   (mem_wr_en),
  .mem_wr_data (mem_wr_data),
  .xint        (xint),
  .xtick       (xtick),
  .uart_tx     (uart_tx)
);

sram r0(
  .clk         (clk),
  .addr        (mem_addr),
  .mem_rd_en   (mem_rd_en),
  .mem_rd_data (mem_rd_data),
  .mem_wr_en   (mem_wr_en),
  .mem_wr_data (mem_wr_data)
);

tb_serial u0(
  .clk         (clk),
  .reset       (reset),
  .rx_data     (uart_tx)
);


`ifdef VCD
initial
  begin
     $dumpfile("test.vcd");
     $dumpvars(0, testbench);
  end
`endif

endmodule
