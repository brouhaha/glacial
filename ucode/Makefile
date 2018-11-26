all: ucode.hex ucode.lst

%.hex %.lst: %.asm
	tools/asg $*.asm -o $*.hex -l $*.lst
