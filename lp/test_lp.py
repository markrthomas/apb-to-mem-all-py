"""Power-cycle test for the UPF-emulated APB memory (apb_mem_lp).

Runs on plain Icarus + cocotb. It exercises the behavior that a real IEEE-1801
flow derives from apb_mem.upf, but which is hand-modeled here (see the LP_EMULATE
notes in the RTL):

  * isolation  — PD_MEM outputs clamp to 0 (PREADY low) while the domain is off,
                 so the array's X's never reach the always-on APB master;
  * retention  — a power cycle with ret=1 preserves the stored contents;
  * corruption — a power cycle with ret=0 loses them (array reads back X).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

# A handful of known (addr, data) pairs to write and later check.
PATTERN = [(0x0000, 0xA5), (0x0001, 0x5A), (0x1234, 0xF0), (0x7FFF, 0x0F)]


class ApbLpDriver:
    """Minimal APB master with power-management pokes for PD_MEM."""

    def __init__(self, dut):
        self.dut = dut

    async def start(self):
        cocotb.start_soon(Clock(self.dut.PCLK, 10, units="ns").start())
        # Powered on, isolation off, no retention hold.
        self.dut.pwr_on.value = 1
        self.dut.iso_en.value = 0
        self.dut.ret.value = 0
        self.dut.PSEL.value = 0
        self.dut.PENABLE.value = 0
        self.dut.PWRITE.value = 0
        self.dut.PADDR.value = 0
        self.dut.PWDATA.value = 0
        self.dut.PRESETn.value = 0
        await ClockCycles(self.dut.PCLK, 3)
        await FallingEdge(self.dut.PCLK)
        self.dut.PRESETn.value = 1
        await RisingEdge(self.dut.PCLK)

    async def _access(self, addr, write, wdata=0):
        """One SETUP+ACCESS transfer; waits for PREADY. Returns raw PRDATA."""
        await FallingEdge(self.dut.PCLK)
        self.dut.PSEL.value = 1
        self.dut.PENABLE.value = 0
        self.dut.PWRITE.value = 1 if write else 0
        self.dut.PADDR.value = addr
        self.dut.PWDATA.value = wdata
        await FallingEdge(self.dut.PCLK)
        self.dut.PENABLE.value = 1
        await RisingEdge(self.dut.PCLK)
        while self.dut.PREADY.value != 1:
            await RisingEdge(self.dut.PCLK)
        rdata = self.dut.PRDATA.value               # keep as BinaryValue (may be X)
        await FallingEdge(self.dut.PCLK)
        self.dut.PSEL.value = 0
        self.dut.PENABLE.value = 0
        self.dut.PWRITE.value = 0
        return rdata

    async def write(self, addr, data):
        await self._access(addr, write=True, wdata=data)

    async def read(self, addr):
        return await self._access(addr, write=False)

    async def power_down(self, retain):
        """UPF sequence: isolate, then drop the switch (optionally retaining)."""
        self.dut.ret.value = 1 if retain else 0
        await RisingEdge(self.dut.PCLK)
        self.dut.iso_en.value = 1                    # clamp outputs first
        await RisingEdge(self.dut.PCLK)
        self.dut.pwr_on.value = 0                    # then open the switch
        await ClockCycles(self.dut.PCLK, 2)

    async def power_up(self):
        """UPF sequence: restore the switch, then release isolation."""
        self.dut.pwr_on.value = 1
        await ClockCycles(self.dut.PCLK, 2)
        self.dut.ret.value = 0                        # restore retained state
        self.dut.iso_en.value = 0
        await RisingEdge(self.dut.PCLK)


@cocotb.test()
async def power_cycle_test(dut):
    drv = ApbLpDriver(dut)
    await drv.start()

    # 1. Write the pattern and confirm it reads back while powered on.
    for addr, data in PATTERN:
        await drv.write(addr, data)
    for addr, data in PATTERN:
        got = int(await drv.read(addr))
        assert got == data, f"pre-power-down @0x{addr:04X}: got 0x{got:02X} exp 0x{data:02X}"
    dut._log.info("powered-on read-back OK for %d locations", len(PATTERN))

    # 2. Isolation: while PD_MEM is down, its outputs must be clamped (PREADY
    #    low, PRDATA driven to the clamp value 0 — never X on the AON boundary).
    await drv.power_down(retain=True)
    assert dut.PREADY.value == 0, "PREADY not clamped low during power-down"
    dut.PSEL.value = 1
    dut.PWRITE.value = 0
    dut.PADDR.value = PATTERN[0][0]
    await RisingEdge(dut.PCLK)
    assert dut.PRDATA.value.is_resolvable, "PRDATA is X during power-down (isolation failed)"
    assert int(dut.PRDATA.value) == 0, "PRDATA not clamped to 0 during power-down"
    dut.PSEL.value = 0
    dut._log.info("isolation OK: outputs clamped (PREADY=0, PRDATA=0) while off")

    # 3. Retention: powering back up (ret was high) restores the contents.
    await drv.power_up()
    for addr, data in PATTERN:
        got = int(await drv.read(addr))
        assert got == data, f"post-retention @0x{addr:04X}: got 0x{got:02X} exp 0x{data:02X}"
    dut._log.info("retention OK: contents survived a retained power cycle")

    # 4. Corruption: a power cycle WITHOUT retention loses the state — the array
    #    reads back X (unknown), proving the retention above did real work.
    await drv.power_down(retain=False)
    await drv.power_up()
    corrupted = await drv.read(PATTERN[0][0])
    assert not corrupted.is_resolvable, (
        f"expected X after a non-retained power cycle, got 0x{int(corrupted):02X}")
    dut._log.info("corruption OK: non-retained power cycle lost the data (read X)")

    # 5. The array is fully usable again after re-initialization.
    await drv.write(PATTERN[0][0], 0x3C)
    got = int(await drv.read(PATTERN[0][0]))
    assert got == 0x3C, f"post-recovery @0x{PATTERN[0][0]:04X}: got 0x{got:02X} exp 0x3C"
    dut._log.info("recovery OK: array writable again after corruption")
