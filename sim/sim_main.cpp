// Verilator coverage harness for apb_mem.
//
// Single clock (PCLK, period 10 time-units). This driver does not self-check
// (the pyuvm testbench in ../tb owns correctness); its only job is to walk the
// RTL through every line so `make coverage` emits meaningful coverage:
//   * a write attempted while PRESETn=0 (reset-gated: no commit)
//   * committed writes (PSEL & PENABLE & PWRITE & PREADY) to edge/interior addrs
//   * reads (PSEL & !PWRITE) of written and un-written locations
//   * idle cycles (PSEL=0) that exercise the PRDATA='0 default branch
//
// Run from the Verilator --Mdir (cwd holds coverage.dat); the root Makefile
// then feeds coverage.dat to verilator_coverage --write-info.

#include "Vapb_mem.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>

static Vapb_mem* dut = nullptr;

// One PCLK cycle: settle inputs/comb with the clock low, then a rising edge.
static void tick() {
    dut->PCLK = 0;
    dut->eval();
    dut->PCLK = 1;
    dut->eval();
}

static void idle() {
    dut->PSEL = 0;
    dut->PENABLE = 0;
    dut->PWRITE = 0;
    tick();
}

// APB write transfer: SETUP (PENABLE=0) then ACCESS (PENABLE=1) then IDLE.
static void apb_write(uint32_t addr, uint8_t data) {
    dut->PSEL = 1; dut->PENABLE = 0; dut->PWRITE = 1;
    dut->PADDR = addr; dut->PWDATA = data;
    tick();                     // SETUP
    dut->PENABLE = 1;
    tick();                     // ACCESS — commit on this edge
    idle();
}

// APB read transfer; returns PRDATA sampled at the end of the ACCESS phase.
static uint8_t apb_read(uint32_t addr) {
    dut->PSEL = 1; dut->PENABLE = 0; dut->PWRITE = 0;
    dut->PADDR = addr;
    tick();                     // SETUP
    dut->PENABLE = 1;
    tick();                     // ACCESS
    uint8_t d = dut->PRDATA;
    idle();
    return d;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vapb_mem;

    const uint32_t LAST = 0x7FFF;   // top of the 32K byte space
    long cycles = 0;

    // --- reset: hold PRESETn low and attempt a write (must NOT commit) --------
    dut->PRESETn = 0;
    dut->PSEL = 0; dut->PENABLE = 0; dut->PWRITE = 0;
    dut->PADDR = 0; dut->PWDATA = 0;
    dut->eval();
    dut->PSEL = 1; dut->PENABLE = 1; dut->PWRITE = 1;
    dut->PADDR = 0x1234; dut->PWDATA = 0xEE;
    tick(); tick();                 // reset-gated write window
    idle();
    dut->PRESETn = 1;
    tick();

    // --- edge + interior addresses, all-0 / all-1 / patterned payloads --------
    const uint32_t addrs[] = {0x0000, 0x0001, 0x0002, 0x4000, LAST - 1, LAST};
    const uint8_t  data[]  = {0x00, 0xFF, 0x55, 0xAA, 0x5A, 0xA5};
    const int N = sizeof(addrs) / sizeof(addrs[0]);

    for (int i = 0; i < N; ++i) { apb_write(addrs[i], data[i]); cycles += 3; }
    for (int i = 0; i < N; ++i) { (void)apb_read(addrs[i]);     cycles += 3; }

    // read of an un-written location (reset-gated write above must be absent) ->
    // exercises the zero-initialised array path.
    (void)apb_read(0x1234);
    cycles += 3;

    // a stretch of idle to exercise the PRDATA='0 default branch.
    for (int i = 0; i < 8; ++i) { idle(); ++cycles; }

    dut->final();
    VerilatedCov::write("coverage.dat");
    printf("[sim_cov] done: %ld cycles\n", cycles);
    delete dut;
    return 0;
}
