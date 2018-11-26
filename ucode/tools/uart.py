#!/usr/bin/python3
# UART decoder for simulator
# Copyright 2018 Eric Smith <spacewar@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of version 3 of the GNU General Public License
# as published by the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

class UART:

    def __init__(self, clock_freq_hz, bit_rate_hz = 115200, data_bits = 8, stop_bits = 1, oversampling = 16):
        self.bit_time_cycles = clock_freq_hz / bit_rate_hz
        self.data_bits = data_bits
        self.stop_bits = stop_bits
        self.oversampling = oversampling

        self.line_state = 1
        self.sample_cycle = 0

        self.idle = True
        self.oversampling_counter = 0


    def process_tx_sample(self, value):
        if self.idle:
            if value:
                return	# still idle
            # start bit
            self.idle = False
            self.bit_num = -1  # start bit
            self.byte_val = 0x00
            self.oversampling_counter = self.oversampling // 2
            return
        self.oversampling_counter -= 1
        if self.oversampling_counter:
            return
        self.oversampling_counter = self.oversampling
        if self.bit_num < 0:
            # check start bit
            if value:
                print('framing error - start bit')
                self.idle = True
                return
            self.bit_num = 0
            return
        self.byte_val |= (value << self.bit_num)
        self.bit_num += 1
        if self.bit_num < (self.data_bits + self.stop_bits):
            return
        if (self.byte_val >> self.data_bits) != ((1 << self.stop_bits) - 1):
            print('framing error - stop bit')
            self.idle = True
            return
        self.byte_val &= ((1 << self.data_bits) - 1)
        self.idle = True
        return self.byte_val


    def tx(self, cycle, value):
        rxb = None
        while self.sample_cycle <= cycle:
            b = self.process_tx_sample(self.line_state)
            if b is not None:
                rxb = b
            self.sample_cycle += self.bit_time_cycles / self.oversampling
        self.line_state = value
        return rxb




                
