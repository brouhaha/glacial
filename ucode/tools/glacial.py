#!/usr/bin/python3
# Glacial microarchitecture definitions
# Copyright 2016,2018 Eric Smith <spacewar@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of version 3 of the GNU General Public License
# as published by the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

from enum import Enum


IndirectReg = { 'x':   0,
                'y':   1 }


OperandClass = Enum('OperandClass', ['imm',
                                     'numeric',
                                     'ind',
                                     'postinc',
                                     'cond'])
                                     


# operand type
OT = Enum('OT', ['val',            # numeric value
                 'imm',            # immediate 8-bit
                 'mem',            # memory address 8-bit
                 'ind',            # indirect register (@x, @y)
                 'postinc',        # indirect register postincrement (@x+, @x-)
                 'bit',            # bit number, 0-7
                 'cond',           # branch condition
                 'jmp'             # 13-bit absolute address / 2 (12 bits)
                 ])

OperandClassByType = { OT.val:     OperandClass.numeric,
                       OT.imm:     OperandClass.imm,
                       OT.mem:     OperandClass.numeric,
                       OT.ind:     OperandClass.ind,
                       OT.postinc: OperandClass.postinc,
                       OT.bit:     OperandClass.numeric,
                       OT.cond:    OperandClass.cond,
                       OT.jmp:     OperandClass.numeric }


def bit_count(v):
    return bin(v).count('1')


class BitField:
    def __init__(self, byte_count = 0):
        self.width = 0  # width of the field within the instruction
        self.mask = bytearray(byte_count)

    def __repr__(self):
        return 'BitField(width = %d, mask = %s' % (self.width, str(self.mask))

    def append(self, mask_byte):
        self.mask.append(mask_byte)
        self.width += bit_count(mask_byte)

    def pad_length(self, length):
        if len(self.mask) < length:
            self.mask += bytearray(length - len(self.mask))

    def insert(self, bits, value):
        assert isinstance(value, int)
        for i in reversed(range(len(bits))):
            for b in [1 << j for j in range(8)]:
                if self.mask[i] & b:
                    if value & 1:
                        bits[i] |= b
                    value >>= 1
        assert value == 0  # XXX causes negative 8-bit immediates to fail
        

# An instruction form is a variant of an instruction that takes
# specific operand types.
class Form:
    @staticmethod
    def __byte_parse(bs, second_flag):
        b = 0
        m = 0
        f = { }
        for i in range(8):
            c = bs[7-i]
            if c == '0':
                m |= (1 << i)
            elif c == '1':
                b |= (1 << i)
                m |= (1 << i)
            else:
                if second_flag:
                    c += '2'
                if c not in f:
                    f[c] = 0
                f[c] |= (1 << i)
        return b, m, f

    @staticmethod
    def __encoding_parse(encoding):
        ep_debug = False
        if ep_debug:
            print('encoding', encoding)
        encoding = encoding.replace(' ', '')
        bits = []
        mask = []
        fields = { }
        second_flag = False
        while len(encoding):
            if encoding[0] == '/':
                encoding = encoding[1:]
                second_flag = True
                continue
            assert len(encoding) >= 8
            byte = encoding[0:8]
            encoding = encoding[8:]
            if ep_debug:
                print('byte', byte)
            b, m, f = Form.__byte_parse(byte, second_flag)
            if ep_debug:
                print('b: ', b, 'm:', m, 'f:', f)
            bits.append(b)
            mask.append(m)
            for k in f:
                if k not in fields:
                    fields[k] = BitField(len(bits)-1)
                fields[k].append(f[k])
        if ep_debug:
            print('fields before:', fields)
        for k in fields:
            fields[k].pad_length(len(bits))
        if ep_debug:
            print('fields after:', fields)
        return bits, mask, fields

    def __init__(self, operands, encoding):
        self.operands = operands
        self.encoding = encoding
        self.bits, self.mask, self.fields = Form.__encoding_parse(encoding)

    def __len__(self):
        return len(self.bits)

    def insert_fields(self, fields):
        bits = bytearray(self.bits)
        #if set(self.fields.keys()) != set(fields.keys()):
        #    print('self.fields.keys:', self.fields.keys())
        #    print('fields.keys:', fields.keys())
        assert set(self.fields.keys()) == set(fields.keys())
        for k, bitfield in self.fields.items():
            bitfield.insert(bits, fields[k])
        return bits
        


# An instruction has a single mnemonic, but possibly multiple
# forms.
class Inst:
    def __init__(self, mnem, *forms):
        self.mnem = mnem
        self.forms = forms


class Glacial:
    class UnknownMnemonic(Exception):
        def __init__(self, mnem):
            super().__init__('unknown mnemonic "%s"' % mnem)

    class NoMatchingForm(Exception):
        def __init__(self):
            super().__init__('no matching form')

    class OperandOutOfRange(Exception):
        def __init__(self):
            super().__init__('operand out of range')


    BranchCond = { 'ne':    0,
                   'nz':    0,
                   'eq':    1,
                   'z':     1,
                   'cc':    2,
                   'ge':    2,
                   'cs':    3,
                   'lt':    3,
                   'nxint': 4,
                   'xint':  5,
                   'ntick': 6,
                   'tick':  7 }


    class OperandImmediate:
        def __init__(self, ival):
            self.ival = ival

    class OperandIndirect:
        def __init__(self, ireg):
            self.ireg = ireg

    class OperandPostincrement:
        def __init__(self, ireg):
            self.ireg = ireg

    class OperandCondition:
        def __init__(self, cond):
            self.cond = cond


    __inst_set = [
        Inst('opr',     Form((OT.val,)           , '0000iiii iiiiiiii')),

        Inst('store',   Form((OT.mem,)           , '00010000 mmmmmmmm'),
                        Form((OT.ind,)           , '00100000 0000000x'),
                        Form((OT.postinc,)       , '00110000 0000000x')),

        Inst('load',    Form((OT.imm,)           , '01000000 iiiiiiii'),
                        Form((OT.mem,)           , '01010000 mmmmmmmm'),
                        Form((OT.ind,)           , '01100000 0000000x'),
                        Form((OT.postinc,)       , '01110000 0000000x')),

        Inst('and',     Form((OT.imm,)           , '01000001 iiiiiiii'),
                        Form((OT.mem,)           , '01010001 mmmmmmmm'),
                        Form((OT.ind,)           , '01100001 0000000x'),
                        Form((OT.postinc,)       , '01110001 0000000x')),

        Inst('xor',     Form((OT.imm,)           , '01000010 iiiiiiii'),
                        Form((OT.mem,)           , '01010010 mmmmmmmm'),
                        Form((OT.ind,)           , '01100010 0000000x'),
                        Form((OT.postinc,)       , '01110010 0000000x')),

        Inst('adc',     Form((OT.imm,)           , '01000011 iiiiiiii'),
                        Form((OT.mem,)           , '01010011 mmmmmmmm'),
                        Form((OT.ind,)           , '01100011 0000000x'),
                        Form((OT.postinc,)       , '01110011 0000000x')),

        Inst('jump',    Form((OT.jmp,)           , '10000jjj jjjjjjjj')),
        Inst('call',    Form((OT.jmp,)           , '10001jjj jjjjjjjj')),

        Inst('skb',     Form((OT.mem,     OT.bit, OT.val), '1001ibbb mmmmmmmm'),
                        Form((OT.ind,     OT.bit, OT.val), '1010ibbb 0000000x'),
                        Form((OT.postinc, OT.bit, OT.val), '1011ibbb 0000000x')),

        Inst('br',      Form((OT.cond, OT.jmp)   , '11cccjjj jjjjjjjj'))
    ]


    def __mnemonic_table_init(self):
        self.__inst_by_mnemonic = { }
        self.__inst_by_opcode = { }
        for inst in self.__inst_set:
            if inst.mnem not in self.__inst_by_mnemonic:
                self.__inst_by_mnemonic[inst.mnem] = inst
            for form in inst.forms:
                opcode = form.bits[0] << 8 | form.bits[1]
                mask = form.mask[0] << 8 | form.mask[1]
                # XXX inefficient way to populate the table, should enumerate based on fields
                for i in range(0x10000):
                    if i & mask == opcode:
                        assert not i in self.__inst_by_opcode
                        self.__inst_by_opcode[i] = ( inst, form )

    def _mnemonic_table_print(self):
        for mnemonic in sorted(self.__inst_by_mnemonic.keys()):
            inst = self.__inst_by_mnemonic[mnemonic]
            for form in inst.forms:
                print("%7s: %02x %02x" % (mnemonic, form.bits[0], form.bits[1]), form.operands)


    @staticmethod
    def __extract_field(opcode, fields, f):
        mask = (fields[f].mask[0] << 8) | fields[f].mask[1]
        width = 0
        v = 0
        for i in reversed(range(16)):
            if mask & (1 << i):
                v = (v << 1) | ((opcode >> i) & 1)
                width += 1
        if f == 'j':
            v *= 2
        return v


    class BadInstruction(Exception):
        pass


    def mnemonic_search(self, mnemonic):
        if mnemonic not in self.__inst_by_mnemonic:
            raise Glacial.UnknownMnemonic(mnemonic)
        return self.__inst_by_mnemonic[mnemonic]


    def opcode_search(self, opcode):
        if opcode not in self.__inst_by_opcode:
            raise Glacial.BadInstruction()
        inst, form = self.__inst_by_opcode[opcode]
        fields = { }
        for f in form.fields:
            fields[f] = self.__extract_field(opcode, form.fields, f)
        return inst, form, fields
        # should never get here
        raise Glacial.BadInstruction()


    @staticmethod
    def ihex(v):
        s = '%xh' % v
        if s[0].isalpha():
            s = '0' + s
        return s


    def __get_operand_class(celf, operand):
        if isinstance(operand, Glacial.OperandImmediate):
            return OperandClass.imm
        if isinstance(operand, Glacial.OperandIndirect):
            return OperandClass.ind
        if isinstance(operand, Glacial.OperandPostincrement):
            return OperandClass.postinc
        if isinstance(operand, Glacial.OperandCondition):
            return OperandClass.cond
        if isinstance(operand, int):
            return OperandClass.numeric
        return None


    def __operand_types_match(self, operand_classes, operand_types):
        if len(operand_classes) != len(operand_types):
            return False
        for i in range(len(operand_classes)):
            if OperandClassByType[operand_types[i]] != operand_classes[i]:
                return False
        return True


    def __check_range(self, value, r):
        if value not in r:
            raise Glacial.OperandOutOfRange()

    def __width_bit(self, s):
        if s == 8:
            return 0
        elif s == 16:
            return 1
        else:
            raise Glacial.OperandOutOfRange()

    def __assemble_operand(self, operand, operand_type):
        if operand_type == OT.val:
            return { 'i': operand }
        elif operand_type == OT.imm:
            return { 'i': operand.ival }
        elif operand_type == OT.mem:
            return { 'm': operand }
        elif operand_type == OT.ind:
            return { 'x': operand.ireg }
        elif operand_type == OT.postinc:
            return { 'x': operand.ireg }
        elif operand_type == OT.bit:
            return { 'b': operand }
        elif operand_type == OT.cond:
            return { 'c': operand.cond }
        elif operand_type == OT.jmp:
            return { 'j': operand // 2 }
        else:
            raise Unimplemented("can't assemble operand")


    def decode_instruction(self, opcode):
        inst, form, fields = self.opcode_search(opcode)
        return inst.mnem, form.operands, fields
        

    # pc is used to compute relative branch targets                       
    # inst can be:
    #   Inst (return value from mnemonic_search)
    #   mnemonic (string)
    # each operand can be:
    #   integer
    def assemble_instruction(self, pc, inst, operands):
        if not isinstance(inst, Inst):
            inst = self.mnemonic_search(inst)
            if inst is None:
                raise Glacial.UnknownMnemonic(inst)

        operand_classes = [self.__get_operand_class(operand) for operand in operands]
        for form in inst.forms:
            if self.__operand_types_match(operand_classes, form.operands):
                break
        else:
            raise Glacial.NoMatchingForm()

        fields = { }
        for i in range(len(operands)):
            fields.update(self.__assemble_operand(operands[i], form.operands[i]))
        return form.insert_fields(fields)

    def __init__(self):
        self.__mnemonic_table_init()

if __name__ == '__main__':
    glacial = Glacial()
    glacial._mnemonic_table_print()
