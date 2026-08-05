"""Bus Functional Model: the only layer that touches DUT signals directly.

pyuvm components stay simulator-agnostic and talk to this cocotb singleton via
async methods and queues.  Signals are driven *after* the clock edge so the DUT
samples clean, race-free values on the following edge.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

from pyuvm import utility_classes


class ApbBfm(metaclass=utility_classes.Singleton):
    def __init__(self):
        self.dut = cocotb.top
        self.driver_queue = Queue()        # command items handed to the driver
        self.result_queue = Queue()        # read data returned to the driver
        self.monitor_queue = Queue()       # completed transfers seen on the bus

    # -- clock / reset --------------------------------------------------------
    async def start_clock(self, period_ns=10):
        cocotb.start_soon(Clock(self.dut.PCLK, period_ns, units="ns").start())

    async def reset(self):
        # Idle the request channel and pulse PRESETn low.
        self.dut.PRESETn.value = 0
        self.dut.PSEL.value = 0
        self.dut.PENABLE.value = 0
        self.dut.PWRITE.value = 0
        self.dut.PADDR.value = 0
        self.dut.PWDATA.value = 0
        await ClockCycles(self.dut.PCLK, 3)
        await FallingEdge(self.dut.PCLK)
        self.dut.PRESETn.value = 1
        await RisingEdge(self.dut.PCLK)

    # -- primitive APB transfers ---------------------------------------------
    async def _transfer(self, addr, write, wdata=0):
        """Drive one SETUP+ACCESS APB transfer; return PRDATA (valid on reads)."""
        # SETUP phase: drive request after the edge, PENABLE stays low.
        await FallingEdge(self.dut.PCLK)
        self.dut.PSEL.value = 1
        self.dut.PENABLE.value = 0
        self.dut.PWRITE.value = 1 if write else 0
        self.dut.PADDR.value = addr
        self.dut.PWDATA.value = wdata

        # ACCESS phase: raise PENABLE, wait for PREADY, sample on the edge.
        await FallingEdge(self.dut.PCLK)
        self.dut.PENABLE.value = 1
        await RisingEdge(self.dut.PCLK)
        while self.dut.PREADY.value != 1:
            await RisingEdge(self.dut.PCLK)
        rdata = int(self.dut.PRDATA.value)

        # Return to IDLE.
        await FallingEdge(self.dut.PCLK)
        self.dut.PSEL.value = 0
        self.dut.PENABLE.value = 0
        self.dut.PWRITE.value = 0
        return rdata

    # -- coroutines started by the pyuvm components ---------------------------
    async def driver_bfm(self):
        """Serialise sequencer commands onto the bus, one transfer at a time."""
        while True:
            addr, write, wdata = await self.driver_queue.get()
            rdata = await self._transfer(addr, write, wdata)
            await self.result_queue.put(rdata)

    async def monitor_bfm(self):
        """Record every completed transfer (ACCESS phase with PREADY high)."""
        while True:
            await RisingEdge(self.dut.PCLK)
            if (self.dut.PSEL.value == 1 and self.dut.PENABLE.value == 1
                    and self.dut.PREADY.value == 1):
                await self.monitor_queue.put((
                    int(self.dut.PADDR.value),
                    bool(self.dut.PWRITE.value),
                    int(self.dut.PWDATA.value),
                    int(self.dut.PRDATA.value),
                ))

    # -- driver-facing helpers ------------------------------------------------
    async def send_command(self, addr, write, wdata):
        await self.driver_queue.put((addr, write, wdata))

    async def get_result(self):
        return await self.result_queue.get()

    async def get_monitored(self):
        return await self.monitor_queue.get()

    def start_bfms(self):
        cocotb.start_soon(self.driver_bfm())
        cocotb.start_soon(self.monitor_bfm())
