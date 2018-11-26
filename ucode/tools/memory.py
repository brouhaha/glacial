#!/usr/bin/python3
# Byte-addressable memory model
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

import math

class Memory:

    class Uninitialized(Exception):
        pass

    class UpdateAttempted(Exception):
        pass

    # if both data and size are present size must equal len(data)
    # if neither is present, a default size will be used
    def __init__(self, data = None, size = None, write_once = False):
        self.default_size = 0x10000
        if data is None:
            if size is None:
                self.size = self.default_size
            else:
                self.size = size
            self.data = bytearray(self.size)
            self.valid = bytearray(self.size)
        else:
            if size is not None:
                assert size == len(data)
            self.size = len(data)
            self.data = bytearray(data)
            self.valid = bytearray([1] * self.size)
        self.write_once = write_once

    def __len__(self):
        return self.size

    def _slice_len(self, sl):
        if sl.stop is None:
            stop = self.size
        else:
            stop = sl.stop
        if sl.step is None:
            return max(0, stop - sl.start)
        else:
            return max(0, math.ceil((stop - sl.start)/sl.step))

    def _slice_last(self, sl):
        if sl.stop is None:
            stop = self.size
        else:
            stop = sl.stop
        if sl.step is None:
            return stop - 1
        else:
            return sl.start + sl.step * (Memory._slice_len(sl) - 1)

    def __getitem__(self, address):
        if isinstance(address, slice):
            if self._slice_last(address) >= self.size:
                raise IndexError()
            if self.valid[address].find(0) > -1:
                raise Memory.Uninitialized()
            return self.data[address.start:address.stop:address.step]
        else:
            if not self.valid[address]: # can raise IndexError
                raise Memory.Uninitialized()
            return self.data[address]

    def __setitem__(self, address, data):
        if isinstance(address, slice):
            if self.write_once and self.valid[address].find(1) > -1:
                raise Memory.UpdateAttempted()
            self.data[address] = data # can raise IndexError or ValueError
            # possibly itertools.repeat might be faster than list multiplications?
            self.valid[address] = [1] * self._slice_len(address)
        else:
            if self.write_once and self.valid[address]:
                raise Memory.UpdateAttempted()
            self.data[address] = data # can raise IndexError or ValueError
            self.valid[address] = 1

    # can pass a slice object for address
    def deinit(self, address):
        self.valid[address] = 0

    # returns a slice object giving the range from
    # the first valid address to the last valid address,
    # though there may be hole between.
    def valid_bounds(self):
        first = self.valid.find(1)
        if first < 0:
            raise Memory.Uninitialized()
        last = self.valid.rfind(1)
        return slice(first, last + 1)

    def next_valid_range(self, first):
        first = self.valid.find(1, first)
        if first < 0:
            raise Memory.Uninitialized()
        last = self.valid.find(0, first + 1)
        if last < 0:
            last = self.size - 1
        return slice(first, last)

    def truncate(self, last = None):
        if last is None:
            last = self.valid.rfind(1)
            if last < 0:
                raise Memory.Uninitialized()
        self.size = last + 1
        self.data = self.data[:self.size]
        self.valid = self.valid[:self.size]


    @staticmethod
    def interleave(meml):
        count = len(meml)
        memlen = [len(mem) for mem in meml]
        # the lengths of all the Memory supplied in the list must be the same
        assert all(x == memlen[0] for x in memlen)

        mem = Memory(size = memlen[0] * count)
        for i in range(count):
            mem[i::count] = meml[i]
        return mem


if __name__ == '__main__':
    memory = Memory()


    memory[4] = 75
    memory[1:6:2] = [64, 45, 45]
    #print(memory[:6])
    print(memory[1:6:2])
    
    memory[7:9] = [33, 34]
    #print(memory[:10])
    print(memory[7:9])
    
    s = 0
    while True:
        r = memory.next_valid_range(s)
        print('r', r)
        s = r.stop

    memory.truncate()
    print(memory[1:6:2])
    print(memory[7:9])
    print(memory.valid_range())
    
