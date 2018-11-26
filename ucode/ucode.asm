; Glacial RV32I microcode
; Implements RISC-V User-Level ISA specification version 2.2
; Implements a subset of RISC-V Privileged ISA specification version 1.10,
; machine mode (M) only

; Copyright 2018 Eric Smith <spacewar@gmail.com>
;
; Reistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions
; are met:
;
; 1. Redistributions of source code must retain the above copyright
;    notice, this list of conditions and the following disclaimer.
; 2. Redistributions in binary form must reproduce the above copyright
;    notice, this list of conditions and the following disclaimer in the
;    documentation and/or other materials provided with the distribution.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
; FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
; COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
; INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
; SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
; HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
; STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
; OF THE POSSIBILITY OF SUCH DAMAGE.
;
; SPDX-License-Identifier: BSD-2-Clause

ft_mem_addr_bytes	equ	2
ft_vectored_interrupts	equ	0
ft_misaligned_data_trap	equ	1	; needed to pass broken I-MISALIGN_LDST-01 compliance test
ft_uart_fast		equ	0	; if true, overrides BRG divisor
ft_external_clock_tick	equ	0	; if false, mtime counts RISC-V instructions executed (like minstret)

clock_rate		equ	27000000
uart_bit_rate		equ	115200


align	macro	alignment
	if	$&(alignment-1)
	ds	alignment-($&(alignment-1))
	endif
	endm

nop	macro
	opr	0x000
	endm

tax	macro
	opr	0x002
	endm

tay	macro
	opr	0x003
	endm

clc	macro
	opr	0x008
	endm

sec	macro
	opr	0x00c
	endm

rlc	macro
	opr	0x020
	endm

rrc	macro
	opr	0x030
	endm

lsl	macro
	opr	0x028
	endm

lsr	macro
	opr	0x038
	endm

ret	macro
	opr	0x040
	endm

addapc	macro
	opr	0x080
	endm

retadd	macro
	opr	0x0c0
	endm

uarttxr	macro
	opr	0x13c		; transmit AC LSB, set carry, rotate A right
	endm

	if	ft_external_clock_tick
clrtick	macro
	opr	0x020
	endm
	endif

skbs	macro	addr,bit
	skb	addr,bit,1
	endm

skbc	macro	addr,bit
	skb	addr,bit,0
	endm


; RISC-V memory addresses of memory-mapped registers required by
; Privileged Architecture V1.10  
mtime		equ	0x10
mtimecmp	equ	0x18


		org	0x0000

		jump	uc_reset
		dw	riscv_mem_offset

; RISC-V general registers - x1..x31 must be from uaddr 0x04 through 0x7f
x1:		ds	31*4

bss_start	equ	$

nextpc:		ds	4

; RV32I CSRs
; WARNING: access to registers other than 0x300..0x307 and
; 0x340..0x347 will trap, but no checking is done of legality of
; access to registers in those ranges.  Writing illegal values or
; writing to undocumented CSRs will have undefined behavior.

csr_300_start	equ	$

mstatus:	ds	4	; CSR 0x300
;      7: MPIE    M previous interrupt enable
;      3: MIE     M interrupt enable

misa:		ds	4	; CSR 0x301
medeleg:	ds	4	; CSR 0x302  machine exception delegation (should trap)
mideleg:	ds	4	; CSR 0x303  machine interrupt delegation (should trap)

mie:		ds	4	; CSR 0x304  interrupt enable
;     11: MEIE  external interrupt enabled
;      7: MTIE  timer interrupt enabled
;      3: MSIE  software interrupt enabled

mtvec:		ds	4	; CSR 0x305  trap handler base address
mcounteren:	ds	4	; CSR 0x306  (no bits implemented)
; Due to incomplete decode in the implementation of the CSR instructions, the
; following locations will be accessible as CSR 0x307
dest:		ds	4	; value to be written to rd

csr_340_start	equ	$
mscratch:	ds	4	; CSR 0x340   not used by microcode
mepc:		ds	4	; CSR 0x341   exception PC
mcause:		ds	4	; CSR 0x342   trap cause
;    31: interrupt   30..0: exception code
;         1                     3             machine software interrupt
;         1                     7             machine timer interrupt
;         1                    11             machine external interrupt
;         0                     0             instruction address misaligned
;         0                     1             instruction access fault
;         0                     2             illegal instruction
;         0                     3             breakpoint
;         0                     5             load access fault
;         0                     7             store access falt
;         0                     8             environment call

mtval:		ds	4	; CSR 0x343   (formerly mbadaddr)

mip:		ds	4	; CSR 0x344   interrupt pending
;     11: MEIP  external interrupt pending
;      7: MTIP  timer interrupt pending
;      3: MSIP  software interrupt pending, usually set by write to memory-mappe; all other bits whould be WARL, but are actuall trested as WPRI

bss_end		equ	$

; Due to incomplete decode in the implementation of the CSR instructions, the
; following three locations will be accessible as CSR 0x345..0x347
s1:		ds	4	; value read from rs1
s2:		ds	4	; value read from rs2
temp:		ds	4

; temp2 is only used while incrementing mtimeh and comparing to mtimecmph,
; so it can be overlapped with other variables that don't need to be
; preserved across instruction boundaries
temp2:
access_type:	ds	1
		ds	3

pc:		ds	4
ir:		ds	4


uc_reset:
; set hard privilage mode to M (the only mode we have)
; set PC to an implementation-defined value (for us, zero)
; set mcause to value indicating cause of reset (zero if no distinguishable
;   reset causes)

; clear nextpc and all CSRs to zero
; will also clear dest because it is between CSRs
	load	#bss_end
	store	temp
rloop:
	load	temp
	clc
	adc	#0xff
	store	temp
	tax
	xor	#bss_start-1
	br	eq,main_loop
	load	#0x00
	store	@x
	jump	rloop

put_1_rd_main_loop:
	load	#0x01
	store	dest	

put_rd_main_loop:
	call	put_rd

main_loop:
	load	nextpc		; check PC alignment
	and	#0x03
	br	eq,pc_alignment_ok

	load	nextpc
	store	mtval
	load	nextpc+1
	store	mtval+1
	load	nextpc+2
	store	mtval+2
	load	nextpc+3
	store	mtval+3
	load	#0		; instruction misalignment trap
	jump	trap

pc_alignment_ok:
	load	nextpc
	store	pc
	load	nextpc+1
	store	pc+1
	load	nextpc+2
	store	pc+2
	load	nextpc+3
	store	pc+3

	if	ft_external_clock_tick
	br	ntick,loop2	; if code has changed mtime or mtimecmp,
				; there won't be a timer interrupt until
				; the next clock tick

	clrtick
	endif
	
; increment mtime[h] - can't access fault
	load	#mtime
	call	set_mem_addr_const
	call	mem_read_32_temp
	call	mem_read_32_y
	call	inc_temp	; changes X

	load	#mtime
	call	set_mem_addr_const
	call	mem_write_32_temp
	br	cc,loop1
	call	inc_temp2	; changes X
	call	mem_write_32_y
loop1:

; compare mtime[h] to mtimecmp[h] - can't access fault
	load	#mtimecmp
	call	set_mem_addr_const
	load	#s1
	call	mem_read_32
	call	mem_read_32_y

	sec
	load	s1
	xor	#0xff
	adc	temp
	load	s1+1
	xor	#0xff
	adc	temp+1
	load	s1+2
	xor	#0xff
	adc	temp+2
	load	s1+3
	xor	#0xff
	adc	temp+3
	load	s1+4
	xor	#0xff
	adc	temp2
	load	s1+5
	xor	#0xff
	adc	temp2+1
	load	s1+6
	xor	#0xff
	adc	temp2+2
	load	s1+7
	xor	#0xff
	adc	temp2+3
	br	lt,loop2

; mtime >= mtimecmp, so set mip.mtip
	load	mip
	and	#0x7f
	xor	#0x80
	store	mip

loop2:
; check whether mstatus.mie is set
	skbs	mstatus,3
	jump	loop3
	
; check for external interrupt
  	load	mip+1
	and	mie+1
	and	#0x08
	br	ne,int_external

; check for software interrupt
  	load	mip
	and	mie
	and	#0x08
	br	ne,int_software

; check for timer interrupt
	load	mip
	and	mie
	and	#0x80
	br	eq,loop3

; timer interrupt
	load	#7
	jump	interrupt

int_software:
	load	#3
	jump	interrupt

int_external:
	load	#11
interrupt:
	store	mcause
	load	#0x80
	store	mcause+3
	jump	trap1

trap:	store	mcause
	load	#0x00
	store	mcause+3
	
trap1:	load	#0x00
	store	mcause+1
	store	mcause+2

; mpp := M   ; NOP, don't have S or U modes

; mpie := mie
; mie := 0
	load	mstatus
	and	#0x7f
	clc
	skbc	mstatus,3
	adc	#0x80
	and	#0xf7
	store	mstatus

	call	copy_pc_to_mepc
	call	copy_mtvec_to_pc

	if	ft_vectored_interrupts
	skbs	mcause+3,7
	jump	trap9
	skbs	mtvec,0		; trap vector
	jump	trap9

	load	mcause
	rlc
	rlc
	and	#0xfc
	clc
	adc	pc
	store	pc
	load	pc+1
	adc	#0x00
	store	pc+1
	load	pc+2
	adc	#0x00
	store	pc+2
	load	pc+3
	adc	#0x00
	store	pc+3
	endif

trap9:

loop3:				; nextpc = pc + 4
	clc
	load	pc
	adc	#0x04
	store	nextpc
	load	pc+1
	adc	#0x00
	store	nextpc+1
	load	pc+2
	adc	#0x00
	store	nextpc+2
	load	pc+3
	adc	#0x00
	store	nextpc+3

	load	#1		; fetch instruction (preload instruction access fault cause)
	store	access_type
	load	#pc
	call	set_mem_addr
	load	#ir
	call	mem_read_32

	load	ir
	and	#0x03
	xor	#0x03
	br	eq,inst_32bit

inst_illegal:
	load	ir
	store	mtval
	load	ir+1
	store	mtval+1
	load	ir+2
	store	mtval+2
	load	ir+3
	store	mtval+3
	load	#2		; illegal instruction trap
	jump	trap
	
inst_ecall:
	load	#0x0b		; ecall from M mode
	jump	trap

inst_ebreak:
	load	#3
	jump	trap

inst_32bit:
	load	ir
	call	rrc2
	and	#0x1f
	addapc
	jump	inst_load	; -000 00-- load
	jump	inst_illegal	; -000 01-- load-fp
	jump	inst_custom0	; -000 10-- custom-0
	jump	inst_misc_mem	; -000 11-- misc-mem
	jump	inst_op_imm	; -001 00-- op-imm
	jump	inst_auipc	; -001 01-- auipc
	jump	inst_illegal	; -001 10-- op-imm-32
	jump	inst_illegal	; -001 11-- 48b
	jump	inst_store	; -010 00-- store
	jump	inst_illegal	; -010 01-- store-fp
	jump	inst_illegal	; -010 10-- custom-1
	jump	inst_illegal	; -010 11-- amo
	jump	inst_op		; -011 00-- op
	jump	inst_lui	; -011 01-- lui
	jump	inst_illegal	; -011 10-- op-32
	jump	inst_illegal	; -011 11-- 64b
	jump	inst_illegal	; -100 00-- madd
	jump	inst_illegal	; -100 01-- msub
	jump	inst_illegal	; -100 10-- nmsub
	jump	inst_illegal	; -100 11-- nmadd
	jump	inst_illegal	; -101 00-- op-fp
	jump	inst_illegal	; -101 01-- reserved
	jump	inst_illegal	; -101 10-- custom-2/rv128
	jump	inst_illegal	; -101 11-- 48b
	jump	inst_branch	; -110 00-- branch
	jump	inst_jalr	; -110 01-- jalr
	jump	inst_illegal	; -110 10-- reserved
	jump	inst_jal	; -110 11-- jal
	jump	inst_system	; -111 00-- system
	jump	inst_illegal	; -111 01-- reserved
	jump	inst_illegal	; -111 10-- custom-3/rv128
	jump	inst_illegal	; -111 11-- >=80b


; -000 10-- custom 0
inst_custom0:
	call	get_rs1
	load	s1
	call	uart_tx_char
	jump	main_loop


; -000 00-- load
inst_load:
	load	#5		; preload load access fault cause
	store	access_type

	call	get_rs1
	call	get_imm12_i
	call	set_mem_addr_s1_plus_s2
	load	#dest
	tax
	call	dispatch_funct3

	jump	inst_lb
	jump	inst_lh
	jump	inst_lw
	jump	inst_illegal
	jump	inst_lbu
	jump	inst_lhu
	jump	inst_illegal
	jump	inst_illegal

inst_lb:
	load	@y+
	store	@x
	call	setup_sign_extend
lb_fill_24:
	store	@x+
lb_fill_16:
	store	@x+
lb_fill_8:
	store	@x+
	jump	put_rd_main_loop

inst_lh:
	if	ft_misaligned_data_trap
	load	s1
	and	#0x01
	br	ne,load_address_misaligned
	endif

	load	@y+
	store	@x+
	load	@y+
	store	@x
	call	setup_sign_extend
	jump	lb_fill_16

inst_lw:
	if	ft_misaligned_data_trap
	load	s1
	and	#0x03
	br	ne,load_address_misaligned
	endif

	load	@y+
	store	@x+
	load	@y+
	store	@x+
	load	@y+
	store	@x+
	load	@y+
	jump	lb_fill_8

inst_lbu:
	load	@y+
	store	@x+
	load	#0x00
	jump	lb_fill_24

inst_lhu:
	if	ft_misaligned_data_trap
	load	s1
	and	#0x01
	br	ne,load_address_misaligned
	endif

	load	@y+
	store	@x+
	load	@y+
	store	@x+
	load	#0x00
	jump	lb_fill_16

	if	ft_misaligned_data_trap
load_address_misaligned:
	call	copy_s1_to_mtval
	load	#4		; load address misaligned
	jump	trap
	endif


; -000 11-- misc-mem
inst_misc_mem:
	jump	main_loop	; ignore FENCE, FENCEI


; -001 00-- op-imm
inst_op_imm:
	call	get_rs1
	call	get_imm12_i
	call	dispatch_funct3

	jump	inst_add
	jump	inst_sll	; shift left logical
	jump	inst_slt
	jump	inst_sltu
	jump	inst_xor
	jump	inst_srl_sra	; shift right logical, arithmetic
	jump	inst_or
	jump	inst_and

inst_add_sub:
	skbs	ir+3,6
	jump	inst_add

	load	s2		; complement subtrahend
	xor	#0xff
	store	s2
	load	s2+1
	xor	#0xff
	store	s2+1
	load	s2+2
	xor	#0xff
	store	s2+2
	load	s2+3
	xor	#0xff
	store	s2+3
	sec
	jump	ia1

inst_add:
	clc
ia1:
	load	s1
	adc	s2
	store	dest
	load	s1+1
	adc	s2+1
	store	dest+1
	load	s1+2
	adc	s2+2
	store	dest+2
	load	s1+3
	adc	s2+3
	store	dest+3
	jump	put_rd_main_loop


inst_sll:
	call	copy_s1_to_dest

sll_loop:
	load	s2
	and	#0x1f
	br	eq,put_rd_main_loop
	clc
	adc	#0xff
	store	s2

	clc
	load	dest
	rlc
	store	dest
	load	dest+1
	rlc
	store	dest+1
	load	dest+2
	rlc
	store	dest+2
	load	dest+3
	rlc
	store	dest+3

	jump	sll_loop


inst_slt:
	call	clear_dest
	call	compare_s1_s2_s
	br	cs,put_rd_main_loop
	jump	put_1_rd_main_loop


inst_sltu:
	call	clear_dest
	call	compare_s1_s2_u
	br	cs,put_rd_main_loop
	jump	put_1_rd_main_loop


inst_xor:
	load	s1
	xor	s2
	store	dest
	load	s1+1
	xor	s2+1
	store	dest+1
	load	s1+2
	xor	s2+2
	store	dest+2
	load	s1+3
	xor	s2+3
	store	dest+3
	jump	put_rd_main_loop


inst_srl_sra:
	call	copy_s1_to_dest

srl_sra_loop:
	load	s2
	and	#0x1f
	br	eq,put_rd_main_loop
	clc
	adc	#0xff
	store	s2

	load	s1+3		; assume arithmetic, get sign bit
	rlc
	skbs	ir+3,6		; is it arithmetic?
	clc			; no, logical, so shift in zero

	load	dest+3		; rotate right
	rrc
	store	dest+3
	load	dest+2
	rrc
	store	dest+2
	load	dest+1
	rrc
	store	dest+1
	load	dest+0
	rrc
	store	dest+0

	jump	srl_sra_loop


inst_or:
	load	s2
	xor	#0xff
	store	s2
	load	s2+1
	xor	#0xff
	store	s2+1
	load	s2+2
	xor	#0xff
	store	s2+2
	load	s2+3
	xor	#0xff
	store	s2+3
	
	load	s1
	xor	#0xff
	and	s2
	xor	#0xff
	store	dest

	load	s1+1
	xor	#0xff
	and	s2+1
	xor	#0xff
	store	dest+1

	load	s1+2
	xor	#0xff
	and	s2+2
	xor	#0xff
	store	dest+2

	load	s1+3
	xor	#0xff
	and	s2+3
	xor	#0xff
	store	dest+3
	jump	put_rd_main_loop

inst_and:
	load	s1
	and	s2
	store	dest
	load	s1+1
	and	s2+1
	store	dest+1
	load	s1+2
	and	s2+2
	store	dest+2
	load	s1+3
	and	s2+3
	store	dest+3
	jump	put_rd_main_loop

; -001 01-- auipc
inst_auipc:
	clc
	load	pc
	store	dest
	load	ir+1
	and	#0xf0
	adc	pc+1
	store	dest+1
	load	ir+2
	adc	pc+2
	store	dest+2
	load	ir+3
	adc	pc+3
	store	dest+3
	jump	put_rd_main_loop


; -010 00-- store
inst_store:
	load	#7		; preload store/amo access fault cause
	store	access_type

	call	get_rs1
	call	get_rs2
	call	get_imm12_s
	call	set_mem_addr_s1_plus_temp
; At this point the RISC-V memory address is in s1.
; We have to check whether the address is in {mtimecmp, mtimecmph}, and
; if so, clear mip.MTIP.  Assumes mtimecmp address is 8-byte aligned.

	load	s1
	and	#0xf8
	xor	#mtimecmp
	br	ne,store1
	load	s1+1
	br	ne,store1
	load	s1+2
	br	ne,store1
	load	s1+3
	br	ne,store1

	load	mip
	and	#0x7f
	store	mip

store1:	load	#s2
	tax
	call	dispatch_funct3

	jump	inst_sb
	jump	inst_sh
	jump	inst_sw
	jump	inst_illegal
	jump	inst_illegal
	jump	inst_illegal
	jump	inst_illegal
	jump	inst_illegal


inst_sw:
	if	ft_misaligned_data_trap
	load	s1
	and	#0x03
	br	ne,store_address_misaligned
	endif

	load	@x+
	store	@y+
	load	@x+
	store	@y+

	if	ft_misaligned_data_trap
inst_sh_aligned:
	else
inst_sh:
	endif

	load	@x+
	store	@y+
inst_sb:
	load	@x+
	store	@y+
	jump	main_loop


	if	ft_misaligned_data_trap
inst_sh:
	load	s1
	and	#0x01
	br	ne,store_address_misaligned
	jump	inst_sh_aligned
	endif



	if	ft_misaligned_data_trap
store_address_misaligned:
	call	copy_s1_to_mtval
	load	#6		; store/AMO address misaligned
	jump	trap
	endif


; -011 00-- op
inst_op:
	call	get_rs1
	call	get_rs2
	call	dispatch_funct3

	jump	inst_add_sub
	jump	inst_sll
	jump	inst_slt
	jump	inst_sltu
	jump	inst_xor
	jump	inst_srl_sra
	jump	inst_or
	jump	inst_and


; -011 01-- lui
inst_lui:
	load	#0x00
	store	dest
	load	ir+1
	and	#0xf0
	store	dest+1
	load	ir+2
	store	dest+2
	load	ir+3
	store	dest+3
	jump	put_rd_main_loop


; -110 00-- branch
inst_branch:
	call	get_rs1
	call	get_rs2
	call	dispatch_funct3
	
	jump	inst_beq_bne
	jump	inst_beq_bne
	jump	inst_illegal
	jump	inst_illegal
	jump	inst_blt_bge
	jump	inst_blt_bge
	jump	inst_bltu_bgeu
	jump	inst_bltu_bgeu


inst_beq_bne:
	load	s1
	xor	s2
	br	ne,branch_not_taken
	load	s1+1
	xor	s2+1
	br	ne,branch_not_taken
	load	s1+2
	xor	s2+2
	br	ne,branch_not_taken
	load	s1+3
	xor	s2+3
	br	ne,branch_not_taken
	jump	branch_taken


inst_blt_bge:
	call	compare_s1_s2_s
	br	cc,branch_taken
	jump	branch_not_taken

inst_bltu_bgeu:
	call	compare_s1_s2_u
	br	cc,branch_taken
	jump	branch_not_taken


branch_not_taken:
	skbc	ir+1,4
	jump	branch_taken_1

branch_not_taken_1:
	jump	main_loop

branch_taken:
	skbc	ir+1,4
	jump	branch_not_taken_1

branch_taken_1:
	call	get_imm12_b

	clc
	load	pc
	adc	temp
	store	nextpc
	load	pc+1
	adc	temp+1
	store	nextpc+1
	load	pc+2
	adc	temp+2
	store	nextpc+2
	load	pc+3
	adc	temp+3
	store	nextpc+3

	jump	main_loop


; -110 01-- jalr
inst_jalr:
	call	copy_nextpc_to_dest
	call	get_rs1
	call	get_imm12_i

	load	#s1
	tax

	clc
	load	@x+
	adc	s2
	and	#0xfe

	jump	jal1


; -110 11-- jal
inst_jal:
	call	copy_nextpc_to_dest
	call	get_imm20_j

	load	#pc
	tax

	clc
	load	@x+
	adc	s2
jal1:	store	nextpc
	load	@x+
	adc	s2+1
	store	nextpc+1
	load	@x+
	adc	s2+2
	store	nextpc+2
	load	@x+
	adc	s2+3
	store	nextpc+3

	jump	put_rd_main_loop


; -111 00-- system
; assuming that it's a CSR instruction, get the rs1 value or uimm5 value
inst_system:
	skbs	ir+1,6
	jump	sys0
	call	get_uimm5
	jump	sys1

sys0:	call	get_rs1

sys1:	call	dispatch_funct3

	jump	inst_system_misc
	jump	inst_csrrw_csrrwi
	jump	inst_csrrs_csrrsi
	jump	inst_csrrc_csrrci
	jump	inst_system_misc
	jump	inst_csrrw_csrrwi
	jump	inst_csrrs_csrrsi
	jump	inst_csrrc_csrrci


inst_system_misc:
	load	ir+1
	br	ne,inst_illegal	; will cause SFENCE.VMA to trap
	load	ir+3
	and	#0xcf
	br	ne,inst_illegal
	load	ir+2
	and	#0xcf
	br	ne,inst_illegal	; will cause WFI to trap
	load	ir+2
	call	rrc4
	and	#0x03
	addapc
	jump	inst_ecall
	jump	inst_ebreak
	jump	inst_mret	; will also catch URET, SRET
	jump	inst_illegal

inst_mret:
	load	ir+3
	xor	#0x30		; trap URET, SRET
	br	ne,inst_illegal

; mie := mpie
	load	mstatus
	and	#0xf7
	clc
	skbc	mstatus,7
	adc	#0x08
	store	mstatus

; privilege := mpp     ; NOP: mpp is always M since no S or U mode
; mpp := machine mode  ; NOP: mpp is always M since no S or U mode

; pc := mepc
	load	mepc
	store	nextpc
	load	mepc+1
	store	nextpc+1
	load	mepc+2
	store	nextpc+2
	load	mepc+3
	store	nextpc+3

	jump	main_loop


inst_csrrw_csrrwi:
; CSR read/write (swap):
;     if rd != 0    ; avoid any side effects from reading CSR
;         read CSR, write rd
;     read rs1 or uimm5, write CSR
	call	get_csr
	call	copy_s2_to_dest
	load	temp
	tax
	load	s1
	store	@x+
	load	s1+1
	store	@x+
	load	s1+2
	store	@x+
	load	s1+3
	store	@x+
	jump	put_rd_main_loop


inst_csrrs_csrrsi:
; CSR read and set:
;     read CSR, write rd
;     if rs1/uimm5 != 0
;         read rs1 or uimm5, set bits in CSR
	call	get_csr
	call	copy_s2_to_dest

	load	s1
	xor	#0xff
	store	s1
	load	s1+1
	xor	#0xff
	store	s1+1
	load	s1+2
	xor	#0xff
	store	s1+2
	load	s1+3
	xor	#0xff
	store	s1+3

	load	temp
	tax
	load	@x
	xor	#0xff
	and	s1
	xor	#0xff
	store	@x+
	load	@x
	xor	#0xff
	and	s1+1
	xor	#0xff
	store	@x+
	load	@x
	xor	#0xff
	and	s1+2
	xor	#0xff
	store	@x+
	load	@x
	xor	#0xff
	and	s1+3
	xor	#0xff
	store	@x+

	jump	put_rd_main_loop

inst_csrrc_csrrci:
; CSR read and clear:
;     read CSR, write rd
;     if rs1/uimm5 != 0
;         read rs1 or uimm5, clear bits in CSR
	call	get_csr
	call	copy_s2_to_dest
	load	temp
	tax
	load	s1
	xor	#0xff
	and	@x
	store	@x+
	load	s1+1
	xor	#0xff
	and	@x
	store	@x+
	load	s1+2
	xor	#0xff
	and	@x
	store	@x+
	load	s1+3
	xor	#0xff
	and	@x
	store	@x+
	jump	put_rd_main_loop


get_csr:
; currently only handles 0x300..0x307, 0x340..0x347 CSRs
; returns pointer to CSR in temp
; returns contents of CSR in s2
	load	ir+3		; reject outside 0x300..0x30f, 0x340..0x34f
	and	#0xfb
	xor	#0x30
	br	ne,inst_illegal

	skbc	ir+2,7		; reject 0x308..0x30f, 0x348..0x34f
	jump	inst_illegal

	load	ir+2		; convert 0x340..0x347 to 0x308..0x30f
	skbc	ir+3,2
	xor	#0x80
	rrc
	rrc
	and	#0x3c
	clc
	adc	#csr_300_start
	store	temp
	jump	get_rs2_2


set_mem_addr_s1_plus_s2:
	clc
	load	s1
	adc	s2
	store	s1
	load	s1+1
	adc	s2+1
	store	s1+1
	load	s1+2
	adc	s2+2
	store	s1+2
	load	s1+3
	adc	s2+3
	store	s1+3
	jump	set_mem_addr_s1

set_mem_addr_s1_plus_temp:
	clc
	load	s1
	adc	temp
	store	s1
	load	s1+1
	adc	temp+1
	store	s1+1
	load	s1+2
	adc	temp+2
	store	s1+2
	load	s1+3
	adc	temp+3
	store	s1+3

set_mem_addr_s1:
	load	#s1
set_mem_addr:
	tax

	clc
	load	@x+
	tay
	load	@x+
	adc	#(riscv_mem_offset>>8)&0xff
	tay
	if	ft_mem_addr_bytes>=3
	load	@x+
	adc	#0x00
	tay
	if	ft_mem_addr_bytes>=4
	load	@x+
	adc	#0x00
	tay
	endif
	endif
	br	cs,mem_access_trap
	ret

mem_access_trap:
	load	access_type
	jump	trap
	

set_mem_addr_const:
	tay
	load	#(riscv_mem_offset>>8)&0xff
	tay
	if	ft_mem_addr_bytes>=3
	load	#0x00
	tay
	if	ft_mem_addr_bytes>=4
	tay
	endif
	endif
	ret

mem_read_32_temp:
	load	#temp
mem_read_32:
	tax
mem_read_32_y:
	load	@y+
	store	@x+
	load	@y+
	store	@x+
	load	@y+
	store	@x+
	load	@y+
	store	@x+
	ret

mem_write_32_temp:
	load	#temp
	tax
mem_write_32_y:
	load	@x+
	store	@y+
	load	@x+
	store	@y+
	load	@x+
	store	@y+
	load	@x+
	store	@y+
	ret


; remember, these can't be called from a subroutine
rrc5:	rrc
rrc4:	rrc
	rrc
rrc2:	rrc
	rrc
	ret


inc_temp2:
	load	#temp2
	jump	inc32_a

inc_temp:
	load	#temp
	jump	inc32_a

inc32_a:
	tax
inc32:	
	load	@x
	clc
	adc	#0x01
	store	@x+
	load	@x
	adc	#0x00
	store	@x+
	load	@x
	adc	#0x00
	store	@x+
	load	@x
	adc	#0x00
	store	@x+
	ret


get_uimm5:
	load	ir+1
	clc
	adc	ir+1
	load	ir+2
	adc	ir+2
	and	#0x1f
	store	s1
	load	#0x00
	store	s1+1
	store	s1+2
	store	s1+3
	ret

get_rs1:
	load	ir+1
	rlc
	load	ir+2
	rlc
	rlc
	rlc
	and	#0x7c
	br	eq,get_rs1_zero
	tax
	load	@x+
	store	s1
	load	@x+
	store	s1+1
	load	@x+
	store	s1+2
	load	@x+
	store	s1+3
	ret

get_rs1_zero:
	load	#s1
	jump	clear32_a


; note: stores pointer to origin of s2 in temp
get_rs2:
	load	ir+3
	rrc
	load	ir+2
get_rs2_1:
	rrc
	rrc
	and	#0x7c
	br	eq,get_rs2_zero
	store	temp
get_rs2_2:
	tax
	load	@x+
	store	s2
	load	@x+
	store	s2+1
	load	@x+
	store	s2+2
	load	@x+
	store	s2+3
	ret

get_rs2_zero:
	load	#s2
clear32_a:
	tax
clear32_x:
	load	#0x00
	store	@x+
	store	@x+
	store	@x+
	store	@x+
	ret


put_rd:
	load	ir
	rlc
	load	ir+1
	rlc
	rlc
	rlc
	and	#0x7c
	br	eq,put_rd_0
	tax
	load	dest
	store	@x+
	load	dest+1
	store	@x+
	load	dest+2
	store	@x+
	load	dest+3
	store	@x+
put_rd_0:
	ret


get_imm12_i:
	load	ir+3
	rrc
	store	s2+1
	load	ir+2
	rrc
	store	s2

	load	s2+1
	rrc
	store	s2+1
	load	s2
	rrc
	store	s2

	load	s2+1
	rrc
	store	s2+1
	load	s2
	rrc
	store	s2

	load	s2+1
	rrc
	and	#0x0f
	store	s2+1
	load	s2
	rrc
	store	s2

	load	#0x00
	skbs	s2+1,3
	jump	gi12_i1

	load	s2+1
	clc
	adc	#0xf0
	store	s2+1

	load	#0xff

gi12_i1:
	store	s2+2
	store	s2+3
	ret


get_imm12_s:
	; temp[11..5] := IR[31..25]  (imm[11..5])
	load	ir+3
	rrc
	store	temp+1

	load	temp+1
	rrc
	store	temp+1
	load	#0x00
	rrc
	store	temp

	load	temp+1
	rrc
	store	temp+1
	load	temp
	rrc
	store	temp

	load	temp+1
	rrc
	and	#0x0f
	store	temp+1
	load	temp
	rrc
	store	temp

	; temp[4..0] := IR[11..7]   (imm[4..0])
	load	ir
	rlc
	load	ir+1
	rlc
	and	#0x1f
	clc
	adc	temp
	store	temp

	load	#0x00
	skbs	temp+1,3
	jump	gi12_s1

	load	temp+1
	clc
	adc	#0xf0
	store	temp+1

	load	#0xff

gi12_s1:
	store	temp+2
	store	temp+3
	ret


get_imm12_b:
	load	ir+1		; temp[4..0] := ir[11..8],0
	adc	ir+1
	and	#0x1e
	store	temp

	load	ir+3		; temp[7..5] := ir[27..25]
	rlc
	rlc
	rlc
	rlc
	and	#0xe0
	clc
	adc	temp
	store	temp

	load	ir+3		; temp[10..8] := ir[30..28]
	rrc
	rrc
	rrc
	rrc
	and	#0x07
	store	temp+1

	load	#0x00		; temp[11] := ir[7]
	skbc	ir,7
	load	#0x08
	clc
	adc	temp+1
	store	temp+1

	load	#0x00		; temp[15..12] := expand(ir[31])
	skbc	ir+3,7
	load	#0xf0
	clc
	adc	temp+1
	store	temp+1

	load	#0x00		; temp[31..16] := expand(ir[31])
	skbc	ir+3,7
	load	#0xff
	store	temp+2
	store	temp+3

	ret


get_imm20_j:
	load	ir+3		; s2[13..4] := ir[30..21]
	rrc
	store	s2+1
	load	ir+2
	rrc
	store	s2

	load	s2+1		; s2[12..3] := ir[30..21]
	rrc
	store	s2+1
	load	s2
	rrc
	store	s2

	load	s2+1		; s2[11..2] := ir[30..21]
	rrc
	store	s2+1
	load	s2
	rrc
	store	s2

	load	s2+1		; s2[10..0] := ir[30..21], 0
	rrc
	and	#0x07
	store	s2+1
	load	s2
	rrc
	and	#0xfe
	store	s2

	load	#0x00		; s2[11] := ir[20]
	skbc	ir+3,4
	load	#0x08
	clc
	adc	s2+1
	store	s2+1

	load	ir+1		; s2[19..12] := ir[19..12]
	and	#0xf0
	clc
	adc	s2+1
	store	s2+1
	load	ir+2
	and	#0x0f
	store	s2+2

	load	#0x00		; s2[23..20] := expand(ir[31])
	skbc	ir+3,7
	load	#0xf0
	clc
	adc	s2+2
	store	s2+2

	load	#0x00		; s2[23..20] := expand(ir[31])
	skbc	ir+3,7
	load	#0xff
	store	s2+3

	ret


setup_sign_extend:
	load	#0x00
	skbc	@x+,7
	load	#0xff
	ret


dispatch_funct3:
	load	ir+1
	rrc
	rrc
	rrc
	rrc
	and	#0x07
	retadd


	if	ft_misaligned_data_trap
copy_s1_to_mtval:
	load	s1
	store	mtval
	load	s1+1
	store	mtval+1
	load	s1+2
	store	mtval+2
	load	s1+3
	store	mtval+3
	ret
	endif

copy_s1_to_dest:
	load	s1
	store	dest
	load	s1+1
	store	dest+1
	load	s1+2
	store	dest+2
	load	s1+3
	store	dest+3
	ret

copy_s2_to_dest:
	load	s2
	store	dest
	load	s2+1
	store	dest+1
	load	s2+2
	store	dest+2
	load	s2+3
	store	dest+3
	ret

copy_nextpc_to_dest:
	load	nextpc
	store	dest
	load	nextpc+1
	store	dest+1
	load	nextpc+2
	store	dest+2
	load	nextpc+3
	store	dest+3
	ret

copy_pc_to_mepc:
	load	pc
	store	mepc
	load	pc+1
	store	mepc+1
	load	pc+2
	store	mepc+2
	load	pc+3
	store	mepc+3
	ret

copy_mtvec_to_pc:
	load	mtvec
	and	#0xfc
	store	pc
	load	mtvec+1
	store	pc+1
	load	mtvec+2
	store	pc+2
	load	mtvec+3
	store	pc+3
	ret

clear_dest:
	load	#0x00
	store	dest
	store	dest+1
	store	dest+2
	store	dest+3
	ret

compare_s1_s2_s:
	load	s1+3
	xor	#0x80
	store	s1+3
	load	s2+3
	xor	#0x80
	store	s2+3

compare_s1_s2_u:
	sec
	load	s2
	xor	#0xff
	adc	s1
	load	s2+1
	xor	#0xff
	adc	s1+1
	load	s2+2
	xor	#0xff
	adc	s1+2
	load	s2+3
	xor	#0xff
	adc	s1+3
	ret


uart_tx_char:
	store	temp
	load	#0x00
	uarttxr			; start bit
	
	load	#9		; 8 data bits, 1 stop bit
	store	temp+1

	nop
	nop
	nop
	nop

ut1:
	if	!ft_uart_fast
	
	load	#((clock_rate/(4*uart_bit_rate))-12)/3+1
ut2:	clc
	adc	#0xff
	br	ne,ut2
	endif

	load	temp
	uarttxr			; output data bit, rotate right, shifting in 1
	store	temp
	load	temp+1
	clc
	adc	#0xff
	store	temp+1
	br	ne,ut1

	ret


	align	256
riscv_mem_offset:

	end	0
