// synchronous static RAM

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

module sram #(parameter ADDRESS_WIDTH=16, DATA_WIDTH=8)
  (input                          clk,
   input      [ADDRESS_WIDTH-1:0] addr,
   input                          mem_rd_en,
   output reg    [DATA_WIDTH-1:0] mem_rd_data,
   input 	                  mem_wr_en,
   input         [DATA_WIDTH-1:0] mem_wr_data);

  localparam RAM_DEPTH = 1 << ADDRESS_WIDTH;
   
  reg [DATA_WIDTH-1:0]    mem [0:RAM_DEPTH-1];

  initial
  begin
    //$display("loading initial RAM contents");
    $readmemh("sram.mem", mem);

    // mem[ADDRESS_WIDTH'h0000] = 8'h00;
    // mem[ADDRESS_WIDTH'h0001] = 8'h01;
  end

  always @(negedge clk)
  begin
    mem_rd_data <= 0;
    if (mem_wr_en) begin
      //$display("sram write %04x: %02x", addr, mem_wr_data);
      mem[addr] <= mem_wr_data;
    end
    else if (mem_rd_en) begin
      mem_rd_data <= mem[addr];
      //$display("sram read %04x: %02x", addr, mem[addr]);
    end
  end

endmodule
