# Glacial - microcoded RISC-V core designed for low FPGA resource utilization

Copyright 2018 Eric Smith <spacewar@gmail.com>

Hosted at the
[glacial Github repository](https://github.com/brouhaha/glacial/).

## Introduction

Glacial is an RV32I core designed for the 2018 RISC-V SoftCPU Contest,
for the "smallest implementation" categories. Glacial is implemented
as a microcoded processor core with a very simple 8-bit data path. The
microcode, scratchpad, and RISC-V memory are all stored in the same
8-bit wide RAM.

Glacial is compliant with the RISC-V Instruction Set Manual,
Volume I: User Level ISA, Document Version 2.2, dated 2017-05-07.

Glacial implements only the minimal subset of the Volume II:
Privileged Architecture specification needed to pass the RV32I
conformance tests and to run the Zephyr kernel. Glacial implements
M-mode only. Numerous deviations from the Privileged Architecture
specification exist; for example, all of the implmented CSRs are fully
writeable.

## Microarchitecture inspiration

In order to achieve minimal FPGA resource utilization, a microcoded
architecture is used, trading off FPGA logic cells for additional static
RAM and slower execution. Microcoding was invented by M.V. Wilkes, and
described in "The Best Way to Design an Automated Calculating Machine",
Manchester University Computer Inagural Conf., 1951, pp. 16-18.

The initial IBM System/360 machines announced in 1964 may have been the
first mass-produced microcoded computers. The System/360 Model 30, in
particular, is notable as it used microcoding with 8-bit data paths to
implement a 32-bit architecture. For further information, see S.G. Tucker,
"Microprogram control for System/360", IBM Systems Journal, 6(4), 1967,
pp. 222-241.

Some specific features of the Zephyr microarchitecture were drawn from
well-known minicomputers and microprocessors of the 1960s and 1970s:

* DEC PDP-1 (1960): bit-mapped operate instruction (popularized by the later
PDP-8, 1964)
* DEC PDP-5 (1963): short-form page zero addressing (popularized by the PDP-8)
* DEC PDP-11 (1970): register indirect with postincrement memory addressing mode
* General Instruments  PIC1650 (1976): skip on memory bit set or clear (popularized by Microchip PIC16C family)

## Acknowledgements

Antti Lukats provided a huge amount of assistance, including a bootloader
for the Microsemi SmartFusion2, and huge amounts of general advice on the
mailing list and on a wiki he set up.

Charles Papon provided an example of assembly language code to output the
compliance test result signatures to a UART.

Nelson Ribeiro provided advice on porting the Zephyr RTOS to a new platform.

Thanks also to the RISC-V Foundation and its sponsors for organizing the
contest, and to Microsemi and Lattice for providing FPGA development boards.

## Hardware Requirements

The Glacial core is written in non-vendor-specific Verilog, and should
synthesize for any FPGA. Glacial has been specifically tested with:

* Lattice iCE40 UltraPlus iCE40UP5K, using the iCE40 UltraPlus MDP board
* Microsemi SmartFusion2 M2S025, using the Future Electronics Creative Development Board

## Software Requirements

All development was done on Linux, and instructions are only provided for
Linux. The author specifically used Fedora 28 on an x86_64 platform.

* Building the microcode and memory images requires GNU Make and Python 3.
* Verilog simulation requires Verilator.
* Compiling RISC-V programs including the conformance tests and Zephyr
requires the Zephyr SDK.
* Building the FPGA image for the Lattice iCE40 UltraPlus requires
Lattice iCEcube2 software.
* Building the FPGA image for the Microsemi SmartFusion2 requires
Microsemi Libero SoC Design Software.

## Subdirectories
* ucode:             microcode source code
* ucode/tools:       microcode assembler, simulator, memory utility
* verilog:           Verilog core and testbench
* riscv-compliance:  compliance tests (use "glacial" branch)
* zephyr:            Zephyr RTOS and examples (use "glacial" branch)

## Instructions

### clone repository and set GLACIAL environment variable
```
git clone https://github.com/brouhaha/glacial.git
cd glacial
export GLACIAL=`pwd`
```

### build microcode
```
make -C ucode
```

### build Verilator simulator
```
make -C verilog
```

### run RV32I conformance tests on Verilator simulator
```
TBD
```
