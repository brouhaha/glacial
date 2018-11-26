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

module glacial(input             clk,
	       input             reset,
	       output reg [15:0] mem_addr,
    	       output reg        mem_rd_en,
	       input       [7:0] mem_rd_data,
	       output reg        mem_wr_en,
	       output      [7:0] mem_wr_data,
	       input             xint,
	       input             xtick,
	       output reg        uart_tx
	       );

// registers
  reg    [1:0]  phase;

  reg    [11:1] pc;
  reg    [11:1] ret;
  reg    [15:0] ir;

  reg    [7:0]  x;
  reg    [15:0] y;

  reg    [7:0]  ac;  // accumulator
  reg           cy;  // carry

  reg 		prev_xtick;
  reg           tick;

// combinatorial signals for timing decode
  reg           phase3;

// combinatorial signals for microinstruction decode
  reg 		inst_opr;

// combinatorial signals for control (output by microinstruction decoder)
  reg    [1:0]  mem_addr_sel;
  reg    [2:0]  pc_sel;
  reg    [0:0]  ret_sel;
  reg    [1:0] 	x_sel;
  reg    [1:0] 	y_sel;
  reg    [1:0]	ac_sel;
  reg    [1:0]	cy_sel;
  reg           clr_tick;
  reg 		uart_tx_sel;
   
// combinatorial signals in data path
  reg    [7:0]  rotate_out;
  reg           rotate_cout;

  reg	 [7:0]  mem_rd_data_delayed;
  reg    [7:0]	alu_b;
  reg    [7:0]	alu_out;
  reg    	alu_cy_out;

  reg           branch_cond;
  reg  	        skb_cond;

  localparam [1:0] mem_addr_sel_pc = 2'b00;
  localparam [1:0] mem_addr_sel_ir = 2'b01;
  localparam [1:0] mem_addr_sel_x  = 2'b10;
  localparam [1:0] mem_addr_sel_y  = 2'b11;

  localparam [2:0] pc_sel_hold   = 3'b100;
  localparam [2:0] pc_sel_inc    = 3'b000;
  localparam [2:0] pc_sel_add_a  = 3'b001;
  localparam [2:0] pc_sel_return = 3'b010;
  localparam [2:0] pc_sel_branch = 3'b011;

  localparam [0:0] ret_sel_hold  = 1'b0;
  localparam [0:0] ret_sel_pc    = 1'b1;

  localparam [1:0] x_sel_hold    = 2'b00;
  localparam [1:0] x_sel_ac      = 2'b01;
  localparam [1:0] x_sel_inc     = 2'b10;

  localparam [1:0] y_sel_hold    = 2'b10;
  localparam [1:0] y_sel_ac      = 2'b00;
  localparam [1:0] y_sel_inc     = 2'b01;

  localparam [1:0] ac_sel_hold   = 2'b00;
  localparam [1:0] ac_sel_alu    = 2'b01;
  localparam [1:0] ac_sel_rotate = 2'b10;

  localparam [1:0] cy_sel_hold   = 2'b00;
  localparam [1:0] cy_sel_alu    = 2'b01;
  localparam [1:0] cy_sel_rotate = 2'b10;
  localparam [1:0] cy_sel_ir2    = 2'b11;

  localparam [1:0] alu_op_sel_mem = 2'b00;
  localparam [1:0] alu_op_sel_and = 2'b01;
  localparam [1:0] alu_op_sel_xor = 2'b10;
  localparam [1:0] alu_op_sel_adc = 2'b11;

  assign mem_wr_data = ac;

  always @(posedge clk) begin
    if (reset) begin
      phase <= 0;
    end else begin
      phase <= phase + 1;
    end
  end

  always @(posedge clk) begin
    prev_xtick <= xtick;
    if (reset | clr_tick)
      tick <= 1'b0;
    else if ((prev_xtick == 1'b0) & (xtick == 1'b1))
      tick <= 1'b1;
  end

  always @(posedge clk) begin
    if (reset)
      uart_tx <= 1'b1;
    else if (uart_tx_sel == 1'b1)
      begin
        uart_tx <= ac[0];
      end
  end

  always @(posedge clk) begin
    if (phase == 0)
      ir[15:8] = mem_rd_data;
    if (phase == 1)
      ir[7:0] = mem_rd_data;
  end

  always @(ir[15:12]) begin
    inst_opr = (ir[15:12] == 4'b0000);
  end

  always @(phase) begin
    phase3 = (phase == 3);
  end

  always @(posedge clk) begin
    mem_rd_data_delayed <= mem_rd_data;
  end
  

  always @(ir[13:12], ir[7:0], mem_rd_data_delayed) begin
    if (ir[13:12] == 2'b00)
      alu_b = ir [7:0];
    else 
      alu_b = mem_rd_data_delayed;
  end

  always @(ir[9:8], ac, alu_b, cy) begin
    case (ir[9:8])
      alu_op_sel_mem: { alu_cy_out, alu_out } = { cy, alu_b };
      alu_op_sel_and: { alu_cy_out, alu_out } = { cy, ac & alu_b };
      alu_op_sel_xor: { alu_cy_out, alu_out } = { cy, ac ^ alu_b };
      alu_op_sel_adc: { alu_cy_out, alu_out } = { 1'b0, ac } + { 1'b0, alu_b } + { 8'b0000000, cy };
    endcase
  end

  always @(phase, mem_addr_sel, pc, ir, x, y) begin
    case (mem_addr_sel)
      mem_addr_sel_pc: mem_addr = { 4'b0000, pc, phase[0] };
      mem_addr_sel_ir: mem_addr = { 8'b00000000, ir [7:0] };
      mem_addr_sel_x:  mem_addr = { 8'b00000000, x };
      mem_addr_sel_y:  mem_addr = y;
    endcase
  end

  always @(ir[13:12], ac, cy, xint, tick) begin
    case (ir[13:12])
      2'b00: branch_cond = (ac == 8'b00000000);
      2'b01: branch_cond = cy;
      2'b10: branch_cond = xint;
      2'b11: branch_cond = tick;
    endcase
  end

  always @(ir[10:8], mem_rd_data_delayed) begin
    skb_cond = mem_rd_data_delayed[ir[10:8]];
  end

  always @(posedge clk) begin
    if (reset) begin
      pc <= 0;
    end else begin
      case (pc_sel)
	pc_sel_hold:   ;
        pc_sel_inc:    pc <= pc + 1;
	pc_sel_add_a:  pc <= pc + { 3'b000, ac };
	pc_sel_return: pc <= ret;
	pc_sel_branch: pc <= ir [10:0];
	default:       ;
      endcase
    end
  end // always @ (posedge clk)

  always @(posedge clk) begin
    case (ret_sel)
      ret_sel_hold:  ;
      ret_sel_pc:    ret <= pc;
    endcase
  end

  always @(posedge clk) begin
    case (x_sel)
      x_sel_hold:  ;
      x_sel_ac:    x <= ac;
      x_sel_inc:   x <= x + 1;
      default:     ;
    endcase
  end

  always @(posedge clk) begin
    case (y_sel)
      y_sel_hold:  ;
      y_sel_ac:    y <= { ac, y [15:8] };
      y_sel_inc:   y <= y + 1;
      default:     ;
    endcase
  end

  always @(ac, cy, ir [4]) begin
    if (ir [4]) begin
      rotate_out  = { cy, ac [7:1] };
      rotate_cout = ac [0];
    end else begin
      rotate_out  = { ac [6:0], cy };
      rotate_cout = ac [7];
    end
  end

  always @(posedge clk) begin
    case (ac_sel)
      ac_sel_hold:   ;
      ac_sel_alu:    ac <= alu_out;
      ac_sel_rotate: ac <= rotate_out;
      default:       ;
    endcase
  end

  always @(posedge clk) begin
    case (cy_sel)
      cy_sel_hold:   ;
      cy_sel_alu:    cy <= alu_cy_out;
      cy_sel_rotate: cy <= rotate_cout;
      cy_sel_ir2:    cy <= ir[2];
    endcase
  end

  always @(phase, phase3, ir, inst_opr, skb_cond, branch_cond) begin
    pc_sel = pc_sel_hold;
    ret_sel = ret_sel_hold;
    x_sel = x_sel_hold;
    y_sel = y_sel_hold;
    ac_sel = ac_sel_hold;
    cy_sel = cy_sel_hold;

    mem_rd_en = ! phase3;  // not all instructions need phase 2 read, but simpler decoding
    mem_wr_en = phase3 & (ir[15:14] == 2'b00) & (ir[13:12] != 2'b00);  // store

    if (phase[1] == 0)
      mem_addr_sel = mem_addr_sel_pc;
    else if (ir[13] == 1'b0)
      mem_addr_sel = mem_addr_sel_ir;
    else if (ir[0] == 0)
      mem_addr_sel = mem_addr_sel_x;
    else
      mem_addr_sel = mem_addr_sel_y;
	      
    uart_tx_sel = phase3 & inst_opr & ir[8];
    clr_tick    = phase3 & inst_opr & ir[9];

    case (phase)
      0:
	begin
	  ;
	end
      1:
	begin
	  pc_sel = pc_sel_inc;
	end
      2:
	begin
	  if (inst_opr)
	    begin
	      if (ir[3] == 1'b1)
		cy_sel = cy_sel_ir2;     // clc, sec
	      if (ir[6] == 1'b1)
		pc_sel = pc_sel_return;  // ret
	    end
        end
      3:
       begin
	if (inst_opr)
	  begin
	    if (ir[1] == 1'b1)
	      begin
		if (ir[0] == 1'b0)
		  x_sel = x_sel_ac;  // tax
		else
		  y_sel = y_sel_ac;  // tay
	      end
	    if (ir[5] == 1'b1)  // rlc, rrc
	      begin
		ac_sel = ac_sel_rotate;
		cy_sel = cy_sel_rotate;
	      end
	    if (ir[7] == 1'b1)
	      pc_sel = pc_sel_add_a;  // addapc
	  end // if (inst_opr)
	if ((ir[15:14] != 2'b11) & (ir[13:12] == 2'b11))
	  begin
	    if (ir[0] == 1'b0)
	      x_sel = x_sel_inc;
	    else
	      y_sel = y_sel_inc;
	  end
	if (ir[15:14] == 2'b01)
	  begin
	    ac_sel = ac_sel_alu;
	    cy_sel = cy_sel_alu;
	  end
	casez (ir[15:8])
	  8'b1000????: // jump
	    begin
	      pc_sel = pc_sel_branch;
	      if (ir[11])
		ret_sel = ret_sel_pc;
	    end
	  8'b1001????, // skb direct
	  8'b1010????, // skb indirect
	  8'b1011????: // skb postinc
	    begin
	      if (skb_cond == ir[11])
		pc_sel = pc_sel_inc;
	    end
	  8'b11??????: // br
	    begin
	      if (branch_cond == ir[11])
		pc_sel = pc_sel_branch;
	    end
	  default:
	    ;
	endcase
       end
    endcase
  end

endmodule
