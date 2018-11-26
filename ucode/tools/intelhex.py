#!/usr/bin/python3
# Intel hex file reader
# Copyright 2016, 2018 Eric Smith <spacewar@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of version 3 of the GNU General Public License
# as published by the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

from memory import Memory

class IntelHex:

    class BadChecksum(Exception):
        pass

    class UnknownRecordType(Exception):
        pass
    
    class Discontiguous(Exception):
        pass
    
    def get_bytes(self, count):
        s = self.f.read(2*count)
        if len(s) != 2*count:
            raise EOFError()
        return bytearray([int(s[2*i:2*i+2], 16) for i in range(count)])

    def get_ui8(self):
        return self.get_bytes(1)[0]
    
    def get_ui16(self):
        b = self.get_bytes(2)
        return (b[0] << 8) + b[1]
        

    def get_colon(self):
        while True:
            b = self.f.read(1)
            if len(b) == 0:
                raise EOFError()
            if b[0] == 0x3a:
                return
        

    def get_record(self):
        self.get_colon()
        self.rn += 1
        data_length = self.get_ui8()
        addr = self.get_ui16()
        rec_type = self.get_ui8()
        data = self.get_bytes(data_length)
        expected_checksum = (((data_length +
                               ((addr >> 8) & 0xff) +
                               (addr & 0xff) +
                               rec_type +
                               sum(data)) ^ 0xff) + 1) & 0xff
        checksum = self.get_ui8()
        if checksum != expected_checksum:
            raise IntelHex.BadChecksum('Bad checksum for record #%d' % self.rn)
        #print("rec type %02x, addr %04x" % (rec_type, addr))
        if rec_type == 0x00:  # data
            if addr < self.load_addr:
                raise IntelHex.Discontiguous('Address decreasing')
            self.load_addr = addr
            self.memory[self.load_addr:self.load_addr+data_length] = data
            self.load_addr += data_length

        elif rec_type == 0x01:  # end of file
            self.entry_addr = addr
            raise EOFError()  # end of file
        else:
            raise IntelHex.UnknownRecordType('Unknown record type %02x for record #%d', (rec_type, self.rn))
        return True


    # If memory is not provided, a new Memory will be allocated.
    # If load_addr is provided, it will be used in place of the addresses
    # in the hex file.
    def read(self, f, memory = None):
        self.f = f
        self.load_addr = 0x0000
        self.entry_addr = 0x0000
        if memory is None:
            self.memory = Memory(size = 0x10000)
        else:
            self.memory = memory

        self.rn = 0

        try:
            while True:
                self.get_record()
        except EOFError as e:
            pass

        if memory is None:
            self.memory.truncate()
        return self.memory


    def __write_record(self, f, addr, rec_type, data):
        raw_data = bytearray([len(data), addr >> 8, addr & 0xff, rec_type]) + data
        checksum = ((sum(raw_data) ^ 0xff) + 1) & 0xff
        raw_data += bytearray([checksum])
        s = ':' + ''.join(['%02x' % b for b in raw_data])
        print(s, file = f)

    def __write_range(self, f, memory, sl, data_bytes_per_line):
        addr = sl.start
        while addr < sl.stop:
            l = data_bytes_per_line
            if addr + l > sl.stop:
                l = sl.stop - addr
            self.__write_record(f, addr, 0x00, memory[addr:addr+l])
            addr += l

    def write(self, f, memory, entry_addr = 0x0000, data_bytes_per_line = 16):
        self.f = f
        self.memory = memory
        addr = 0
        while True:
            try:
                sl = self.memory.next_valid_range(addr)
            except Memory.Uninitialized:
                break
            self.__write_range(f, memory, sl, data_bytes_per_line)
            addr = sl.stop
        self.__write_record(f, entry_addr, 0x01, bytearray([]))
            
        
