all: verilator_sim

TB_VERILOG_SRCS = testbench.v glacial.v sram.v tb_serial.v

verilator_sim: obj_dir/Vtestbench

verilator: obj_dir/Vtestbench
	obj_dir/Vtestbench >verilator_sim.txt

obj_dir/Vtestbench: $(TB_VERILOG_SRCS) sim_main.cpp
	verilator --exe --cc --top-module testbench $^
	$(MAKE) -C obj_dir -f Vtestbench.mk


iverilog: testbench.vvp
	vvp -N testbench.vvp >iverilog_sim.txt

testbench.vvp: $(TB_VERILOG_SRCS)
	iverilog -o testbench.vvp $^
	chmod -x testbench.vvp


clean:
	rm -rf obj_dir verilator_sim.txt testbench.vvp

