"""APB transaction object shared by sequences, driver, monitor and scoreboard."""

import random

from pyuvm import uvm_sequence_item

ADDR_MASK = 0x7FFF  # 15-bit address -> 32K byte space
DATA_MASK = 0xFF    # byte-wide data


class ApbSeqItem(uvm_sequence_item):
    """A single APB read or write transfer."""

    def __init__(self, name="ApbSeqItem", addr=0, data=0, write=True):
        super().__init__(name)
        self.addr = addr & ADDR_MASK
        self.data = data & DATA_MASK   # write payload (PWDATA)
        self.write = write             # True -> write, False -> read
        self.rdata = 0                 # captured read data (PRDATA)

    def randomize(self):
        self.addr = random.randint(0, ADDR_MASK)
        self.data = random.randint(0, DATA_MASK)
        self.write = bool(random.getrandbits(1))

    def __eq__(self, other):
        if not isinstance(other, ApbSeqItem):
            return NotImplemented
        # Compare the observable transfer: direction, address, and the payload
        # relevant to that direction.
        payload = self.data if self.write else self.rdata
        other_payload = other.data if other.write else other.rdata
        return (self.write, self.addr, payload) == \
               (other.write, other.addr, other_payload)

    def __str__(self):
        kind = "WR" if self.write else "RD"
        payload = self.data if self.write else self.rdata
        return f"{kind} @0x{self.addr:04X} = 0x{payload:02X}"
