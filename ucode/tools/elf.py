#!/usr/bin/env python3
# Copyright 2012, 2018 Eric Smith <spacewar@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of version 3 of the GNU General Public License
# as published by the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import argparse
from collections import OrderedDict
import mmap
import struct
import sys

from elfdefs import ET, EM, PT


field_char = { 1: 'B',
               2: 'H',
               4: 'I',
               8: 'Q' }


class ElfError(Exception):
    pass


class ElfFileIdentHeader:
    def __init__(self, data):
        self.ei_magic, self.ei_class, self.ei_data, self.ei_version, self.ei_pad = struct.unpack_from('4sBBB9s', data, 0)

        if self.ei_magic != b'\x7fELF':
            raise ElfError('Not an ELF file')
        if self.ei_class == 1:  # ELFCLASS32
            self.width = 32
        elif self.ei_class == 2:  # ELFCLASS64
            self.width = 64
        else:
            raise ElfError('ELF file unrecognized EI_CLASS %d' % self.ei_class)

        if self.ei_data == 1:  # ELFDATA2LSB
            self.endian = '<'
        elif self.ei_data == 2:  # ELFDATA2MSB
            self.endian = '>'
        else:
            raise ElfError('Unrecognized ELF endianness')

        if self.ei_version != 1:
            raise ElfError('Unrecognized ELF version %u' % elf_ident.ei_version)

        if self.ei_pad != (9 * b'\0'):
            raise ElfError('Garbage in ELF ident padding')

        
class ElfFileHeader:
    def __init__(self, data, endian, width):
        fields = OrderedDict([('e_type', 2),
                              ('e_machine', 2),
                              ('e_version', 4),
                              ('e_entry', width // 8),
                              ('e_phoff', width // 8),
                              ('e_shoff', width // 8),
                              ('e_flags', 4),
                              ('e_ehsize', 2),
                              ('e_phentsize', 2),
                              ('e_phnum', 2),
                              ('e_shentsize', 2),
                              ('e_shnum', 2),
                              ('e_shstrndx', 2)])
        offset = 16
        for name, size in fields.items():
            v = struct.unpack_from(endian + field_char[size], data, offset)[0]
            setattr(self, name, v)
            offset += size
        if offset != self.e_ehsize:
            raise ElfError('Header length mismatch %d %d' % (offset, self.e_ehsize))
                         

class ProgHeader:
    def __init__(self, data, offset, endian, width):
        if width == 32:
            self.fields = OrderedDict([('p_type', 4),
                                       ('p_offset', 4),
                                       ('p_vaddr', 4),
                                       ('p_paddr', 4),
                                       ('p_filesz', 4),
                                       ('p_memsz', 4),
                                       ('p_flags', 4),
                                       ('p_align', 4)])
        else:
            self.fields = OrderedDict([('p_type', 4),
                                       ('p_flags', 4),
                                       ('p_offset', 8),
                                       ('p_vaddr', 8),
                                       ('p_paddr', 8),
                                       ('p_filesz', 8),
                                       ('p_memsz', 8),
                                       ('p_align', 8)])
        for name, size in self.fields.items():
            v = struct.unpack_from(endian + field_char[size], data, offset)[0]
            setattr(self, name, v)
            offset += size

    def __str__(self):
        return 'ProgHeader(' + ', '.join(['%s=%0*x' % (name, size*2, getattr(self, name)) for (name, size) in self.fields.items()]) + ')'


class ElfSegment:
    def __init__(self, data, prog_header):
        self.prog_header = prog_header
        self.paddr = prog_header.p_paddr
        self.eaddr = prog_header.p_paddr + prog_header.p_filesz - 1
        self.data = data[prog_header.p_offset + self.paddr:prog_header.p_offset + self.eaddr + 1]

    def __str__(self):
        return 'ElfSegment[0x%08x:0x%08x]' % (self.paddr, self.eaddr)


class ElfFile:
    def parse_headers(self):
        elf_file_ident = ElfFileIdentHeader(self.data)
        elf_file_header = ElfFileHeader(self.data, elf_file_ident.endian, elf_file_ident.width)

        if elf_file_header.e_type != ET.ET_EXEC:
            raise ElfError('Not an executable ELF file')

        if elf_file_header.e_machine != EM.EM_RISCV:
            raise ElfError('Not a RISC-V ELF file')

        self.prog_headers = []
        for ph_index in range (elf_file_header.e_phnum):
            ph_offset = elf_file_header.e_phoff + ph_index * elf_file_header.e_phentsize
            prog_header = ProgHeader(self.data, ph_offset, elf_file_ident.endian, elf_file_ident.width)
            if prog_header.p_type == PT.PT_LOAD:
                if prog_header.p_filesz != 0:
                    self.prog_headers += [prog_header]
            else:
                print('skipping unrecognized program header type %x', prog_header.p_type, file = sys.stderr)

        # sort program headers in physical address order
        self.prog_headers.sort(key=lambda foo: foo.p_paddr)
        if self.debug:
            for ph in self.prog_headers:
                print(ph)

        self.segments = [ElfSegment(self.data, ph) for ph in self.prog_headers]
        for seg in self.segments:
            if self.debug:
                print(seg)

    def __init__(self, f, debug = False):
        self.data = mmap.mmap(f.fileno(),
                              0,  # length
                              access = mmap.ACCESS_READ)
        self.debug = debug
        self.parse_headers()

    def find_segment(self, addr):
        for segment in self.segments:
            if addr >= segment.paddr and addr <= segment.eaddr:
                return segment
        return None


if __name__ == '__main__':

    parser = argparse.ArgumentParser()

    parser.add_argument('elffile',
                        type = argparse.FileType('rb'),
                        help = 'Elf file')

    args = parser.parse_args ()

    elf = ElfFile(args.elffile, debug = True)
