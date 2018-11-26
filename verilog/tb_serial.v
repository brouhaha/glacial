// async serial decoder for testbench

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

module tb_serial #(parameter CLOCK_HZ = 27000000,
		             BIT_RATE_HZ = 115200,
		             DATA_BITS = 8)
  (input clk,
   input reset,
   input rx_data);

  reg                 idle;
  reg [DATA_BITS-1:0] shifter;
  reg [3:0]           bit_counter;
  reg [31:0]          sample_counter;

  initial
  begin
    idle = 1;
    shifter = 0;
  end

  always @(posedge clk)
  begin
    if (reset)
      idle <= 1;
    else if (idle)
      begin
	if (rx_data == 0)
	  begin
	    idle <= 0;
	    bit_counter <= 0;
	    sample_counter <= CLOCK_HZ / (BIT_RATE_HZ * 2) - 1;
	  end
      end
    else
      begin
	if (sample_counter != 0)
	  sample_counter <= sample_counter - 1;
	else
          begin
            sample_counter <= CLOCK_HZ / BIT_RATE_HZ - 1;
	    bit_counter <= bit_counter + 1;

            if (bit_counter == 0)
	      begin
		// check for start bit
		if (rx_data != 0)
		  begin
		    $display("framing error: start bit");
		  end
	      end
	    else if (bit_counter == (DATA_BITS + 1))
	      begin
		// check for stop bit
		if (rx_data != 1)
		  begin
		    $display("framing error: stop bit");
		  end
		else
		  begin
		    if (shifter == 8'h04)  // end of file
		      $finish;
		    else
		      $write("%c", shifter);
		  end
		idle <= 1;
	      end
	    else
              begin
		// data bit
		shifter <= { rx_data, shifter[DATA_BITS-1:1] };
	      end
          end
      end
  end

endmodule
