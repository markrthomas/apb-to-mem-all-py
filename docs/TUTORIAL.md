# Tutorial: pytest + the APB-mem testbench

A hands-on walk through **driving this repo with pytest** and **using / extending the
pyuvm testbench**. If you just want the command table, see the [README](../README.md);
if you want the terse "gotchas" list, see [CLAUDE.md](../CLAUDE.md). This is the
learn-by-doing version.

Assumes the toolchain from the README is installed (apt Icarus 11, `/usr/bin/python3`
with cocotb 1.9.2 + pyuvm 4.0.1 + pytest). Verify with:

```bash
/usr/bin/python3 -m pytest        # expect 7 passed, 1 skipped (uvm self-skips)
```

**Contents**

1. [pytest in this repo](#part-1--pytest-in-this-repo)
2. [The testbench](#part-2--the-testbench)
3. [Add your own test (end-to-end)](#part-3--add-your-own-test-end-to-end)
4. [The other gates: lint, coverage, low-power, UVM](#part-4--the-other-gates)
5. [Debugging](#part-5--debugging)

---

## Part 1 — pytest in this repo

### 1.1 What pytest is doing here

pytest is *not* compiling the RTL itself, and it is not cocotb's Makefile flow. It owns
three things:

1. **Collection & selection** — each gate is a test function, tagged with a marker
   (`sim`/`lint`/`coverage`/`lp`/`uvm`). `pytest -m sim` selects a subset the way the old
   `make test` target did.
2. **The pass/fail contract** — a gate passes iff its test function returns without an
   `assert` firing (or `pytest.skip`ping).
3. **The one-sim-per-test loop** — `tests/_sim.py` calls cocotb's Python runner once per
   test, so every functional testcase gets its own `vvp` and a fresh, time-0-zeroed memory.

The actual simulation is done by the **system toolchain** (apt Icarus + `/usr/bin/python3`'s
cocotb), reached through `cocotb.runner`. The interpreter you launch pytest with *is* the
interpreter the sim embeds — see CLAUDE.md for the two pins that keep that reliable.

| pytest owns | The host owns |
|---|---|
| test collection, marker selection | `iverilog` / `vvp`, `verilator`, `g++` |
| pass/fail (assert / skip) | the Python interpreter (cocotb + pyuvm) |
| one sim per test, build dirs | the actual simulation |

### 1.2 The tests

```bash
pytest --collect-only -q                 # every test
pytest -m sim                            # everything marked 'sim'
pytest tests/test_functional.py -k random  # a single testcase by name
```

The important tests (in [`tests/`](../tests)):

| Test | What it runs |
|---|---|
| `test_functional.py` (parametrized ×3) | one cocotb testcase each: `write_read` / `random` / `walking` |
| `test_lint.py` | `iverilog -Wall` + `verilator --lint-only` (verilator part skips if absent) |
| `test_coverage.py` | Verilator coverage build, gated on a line-coverage floor |
| `test_lowpower.py` | low-power UPF-emulated cocotb test |
| `test_uvm.py` | SV/UVM flow (skips without vcs/xrun/qrun) |

### 1.3 Running things

```bash
pytest                                              # the full gate (7 pass, 1 skip)
pytest -m sim                                       # just the three functional tests
pytest tests/test_functional.py -k random          # a single testcase
pytest -m sim -rA                                   # include the captured sim log in the report
pytest -m "lint or sim"                             # marker expressions (the make check analog)
```

Two flags you'll reach for constantly:

- `-rA` (or `-s`) — surface the cocotb/pyuvm log. pytest captures stdout on a pass by default.
- `--waves` — dump an FST (into `tests/sim_build/<testcase>/`). It's a custom option added in
  `conftest.py`, exposed to the sim tests via the `waves` fixture.

```bash
pytest tests/test_functional.py -k random --waves
gtkwave tests/sim_build/random_test/apb_mem.fst tb/apb_mem.gtkw   # saved layout ships in tb/
```

> **Note:** `always=True` in `run_cocotb` means every run rebuilds and re-executes the sim —
> you never get a stale cached result. The functional tests take ~30 s each on this host.

### 1.4 What one `pytest` test actually does

```
pytest tests/test_functional.py -k random
        │
        ▼  test_apb(testcase="random_test") calls run_cocotb(...) in tests/_sim.py
  get_runner("icarus").build(...)   →  iverilog -g2012 (1ns/1ps)   into tests/sim_build/random_test/
        │
        ▼  runner.test(testcase="random_test", ...)
  vvp  →  loads tb/apb_test.py  →  @cocotb.test random_test  →  uvm_root().run_test("RandomTest")
        │                                                          └─ pyuvm takes over
        ▼
  results.xml  →  get_results()  →  assert failed == 0
```

One `@cocotb.test` runs per pytest invocation of `run_cocotb`, each in its own `vvp` process —
that's what gives every testcase a **fresh, time-0-zeroed memory**. `run_cocotb` pins the
timescale to `1ns/1ps` (apt Icarus defaults to 1 s precision otherwise) and builds with `-g2012`.

---

## Part 2 — The testbench

### 2.1 Layers

Only the **BFM** touches DUT pins. Everything above it is simulator-agnostic pyuvm.

```
Sequence  ── seq items ──▶  Sequencer ──▶  Driver ──▶  BFM ──▶  DUT pins (apb_mem)
(apb_seq.py)                             (apb_components.py)  (apb_bfm.py)
                                                               │
Scoreboard  ◀── analysis port ──  Monitor  ◀───────── samples completed transfers
(reference byte model)            (apb_components.py)
```

| File | Role |
|---|---|
| `tb/apb_seq_item.py` | `ApbSeqItem` — one APB transfer (addr/data/write + captured `rdata`) |
| `tb/apb_seq.py` | the three stimulus sequences |
| `tb/apb_components.py` | driver, monitor, agent, scoreboard, env |
| `tb/apb_bfm.py` | `ApbBfm` singleton — the only code that drives `PSEL/PENABLE/...` |
| `tb/apb_test.py` | the `uvm_test`s + the `@cocotb.test` entry points |

### 2.2 How a transfer flows

1. A **sequence** builds an `ApbSeqItem` and `start_item`/`finish_item`s it to the sequencer.
2. The **driver** (`ApbDriver.run_phase`) pulls the item, calls `bfm.send_command(...)`, then
   `bfm.get_result()`; on a read it stashes the returned byte into `item.rdata`.
3. The **BFM** (`_transfer`) drives one APB SETUP+ACCESS pair, waits for `PREADY`, samples
   `PRDATA`.
4. The **monitor** independently watches the bus (ACCESS phase with `PREADY` high) and writes
   an observed `ApbSeqItem` out its analysis port.
5. The **scoreboard** keeps a `dict` reference memory: writes update it, reads are checked
   against `model.get(addr, 0)`. Mismatches increment `errors`; `check_phase` asserts
   `errors == 0`.

That scoreboard assertion, plus cocotb's "0 failed" gate (`assert failed == 0` in
`run_cocotb`), is the whole pass/fail story.

### 2.3 The BFM's two-phase drive (the pin-level bit)

The BFM is the one place signal timing lives. It drives request signals **after** the clock
edge (on `FallingEdge`) so the DUT samples clean values on the next `RisingEdge` — no races.
A single transfer (`_transfer` in `apb_bfm.py`) is:

```
     ┌── FallingEdge ──┐   ┌── FallingEdge ──┐        ┌── FallingEdge ──┐
PCLK ─┘                └───┘                 └── ... ──┘                 └──
PSEL     0    │ 1 (SETUP)   │ 1 (ACCESS)              │ 0 (IDLE)
PENABLE  0    │ 0           │ 1  ← sample PRDATA here │ 0
PADDR    -    │ A           │ A                       │ -
         drive after edge ──┘   RisingEdge: wait PREADY, read PRDATA
```

- **SETUP** (after a falling edge): `PSEL=1`, `PENABLE=0`, address/control driven.
- **ACCESS** (next falling edge): `PENABLE=1`; on the following rising edge, wait for
  `PREADY` (tied high here, so one cycle) and sample `PRDATA`.
- **IDLE**: drop `PSEL`/`PENABLE`.

`ApbBfm` is a pyuvm `Singleton`, so the driver and monitor share one instance and its queues.
`start_bfms()` launches the `driver_bfm`/`monitor_bfm` coroutines that serialise commands onto
the bus and record every completed transfer.

### 2.4 The three sequences (in `apb_seq.py`)

| Sequence | Stimulus | Why |
|---|---|---|
| `ApbWriteReadSeq` | write a random byte, read the same address back (32×) | basic data integrity |
| `ApbRandomSeq` | random read/write mix (64×), reads biased 4:1 to already-written addresses | exercise stored data, not just never-written 0s |
| `ApbWalkingSeq` | `{0x0000,0x0001,0x7FFE,0x7FFF}` × `{0x00,0x01,0x55,0xAA,0xFF}` | directed corner cases |

Each `uvm_test` in `apb_test.py` is just `BaseTest` with a different `seq_cls`.

---

## Part 3 — Add your own test (end-to-end)

Goal: a **back-to-back writes then verify** sequence, wired up as the `burst_test` testcase.
Three edits, no runner changes.

```mermaid
flowchart LR
    A["1. new uvm_sequence<br/>tb/apb_seq.py"]:::s --> B["2. uvm_test + @cocotb.test<br/>tb/apb_test.py"]:::s --> C["3. add name to CASES<br/>tests/test_functional.py"]:::s --> D["pytest -k burst"]:::a
    classDef a fill:#1F4E79,stroke:#14385A,color:#FFFFFF;
    classDef s fill:#C9D4DF,stroke:#1F4E79,color:#1F4E79;
```

### Step 1 — write the sequence (`tb/apb_seq.py`)

```python
from apb_seq_item import ApbSeqItem, DATA_MASK   # already imported at top of the file

class ApbBurstSeq(uvm_sequence):
    """Write an ascending block, then read it all back."""

    def __init__(self, name="ApbBurstSeq", base=0x0100, num=16):
        super().__init__(name)
        self.base = base
        self.num = num

    async def body(self):
        for i in range(self.num):
            wr = ApbSeqItem("wr", addr=self.base + i, data=i & DATA_MASK, write=True)
            await self.start_item(wr)
            await self.finish_item(wr)
        for i in range(self.num):
            rd = ApbSeqItem("rd", addr=self.base + i, write=False)
            await self.start_item(rd)
            await self.finish_item(rd)
```

You get scoreboard checking for free — the monitor sees every transfer and the reference
model already knows what each address was written.

### Step 2 — expose it as a test (`tb/apb_test.py`)

Add the import and a `uvm_test` + a `@cocotb.test` entry point (the testcase name is what
pytest selects):

```python
from apb_seq import ApbBurstSeq, ApbRandomSeq, ApbWalkingSeq, ApbWriteReadSeq

class BurstTest(BaseTest):
    seq_cls = ApbBurstSeq

@cocotb.test()
async def burst_test(_dut):
    await uvm_root().run_test("BurstTest")
```

### Step 3 — add it to the parametrization (`tests/test_functional.py`)

`test_apb` is parametrized over `CASES`; add the cocotb testcase name:

```python
CASES = ["write_read_test", "random_test", "walking_test", "burst_test"]  # ← new
```

That's it — pytest now collects `test_apb[burst_test]`, which builds a fresh sim and runs the
new `@cocotb.test`.

### Step 4 — run it

```bash
pytest tests/test_functional.py -k burst -rA     # your test alone, with the log
pytest -m sim                                    # confirm it joined the suite (now 4)
pytest                                            # full gate still green
```

That's the whole loop: **sequence → uvm_test + `@cocotb.test` → `CASES` entry**. No touching
`_sim.py` unless you're changing *how* tests are built (new define, new source, a different
top module) — for that, see the low-power test, which passes `defines=` and extra `sources=`.

### Variations

- **Extra Verilog define / source** → write a new `test_*.py` that calls `run_cocotb(...)` with
  `defines={...}` / a longer `sources=[...]` and its own marker (see `tests/test_lowpower.py`).
  Register any new marker in `pyproject.toml`.
- **New RTL edge in the DUT** → add sources to the relevant `run_cocotb` call and, for the
  SV/UVM flow, to `SOURCES` in `tests/test_uvm.py`.

---

## Part 4 — The other gates

The functional tests aren't the whole story. Four more gates run alongside them.

### 4.1 Lint — `pytest -m lint`

`tests/test_lint.py` runs two checks over `rtl/apb_mem.sv`:

1. `iverilog -g2012 -Wall` compile check — a **hard failure** if it errors (uses the
   `ICARUS_BIN_DIR` Icarus so lint and sim agree on the compiler).
2. `verilator --lint-only -Wall -Wno-DECLFILENAME` — **skips cleanly** (`@pytest.mark.skipif`)
   if Verilator isn't on `PATH`.

### 4.2 Coverage — `pytest -m coverage`

`tests/test_coverage.py` does a Verilator `--coverage` build of the RTL, links it against
`sim/sim_main.cpp`, runs it to emit `coverage.dat`, converts to lcov, and gates on a
**line-coverage floor** (`COV_MIN`, default 100%). It skips if Verilator is absent.

```bash
pytest -m coverage -rA                     # see the run
COV_MIN=90 pytest -m coverage              # relax the floor
```

> The DUT's `PSLVERR` tie-off is wrapped in `// verilator coverage_off/on` so the constant
> has no uncoverable point dragging the number below 100%.

### 4.3 Low-power — `pytest -m lp`

`lp/apb_mem_lp.sv` splits the array into a switchable child (`PD_MEM`) to demo a UPF flow
(switch + isolation + retention), hand-modeled behind `` `ifdef LP_EMULATE `` because the
sims aren't UPF-aware. `tests/test_lowpower.py` builds it with `LP_EMULATE=1` and runs
`lp/test_lp.py`'s `power_cycle_test`, which drives the power pins directly (a minimal APB
master, not the pyuvm stack) and asserts:

| Step | Property | Check |
|---|---|---|
| 1 | powered-on read-back | pattern reads back correctly |
| 2 | isolation | while off, `PREADY=0` and `PRDATA` clamps to `0` (never X on the AON boundary) |
| 3 | retention | power cycle with `ret=1` preserves contents |
| 4 | corruption | power cycle with `ret=0` loses them (reads X) — proves retention did work |
| 5 | recovery | array is writable again after re-init |

```bash
pytest -m lp -rA      # watch the "[...] OK" log lines
```

### 4.4 UVM — `pytest -m uvm`

The `uvm/` tree is a full SystemVerilog UVM testbench, plus `uvm/apb_sva.sv` — a checker
`bind`-ed to every `apb_mem` (protocol rules + this slave's tie-offs; see the README table).
`tests/test_uvm.py` looks for `vcs` / `xrun` / `qrun` and **`pytest.skip`s** if none is
licensed, which is the case on the dev host. On a licensed host:

```bash
UVM_TEST=apb_random_test pytest -m uvm
```

---

## Part 5 — Debugging

Re-run the one test with output surfaced, read the scoreboard line, then look at waves.

1. Re-run with `-rA` (or `-s`) to see the pyuvm log.
2. Look for the scoreboard line: `MISMATCH @0xADDR: got 0xXX exp 0xYY` — it names the
   address and both bytes.
3. Re-run with `--waves` and open the FST to see the pins around that address.

```bash
pytest tests/test_functional.py -k random --waves -rA
gtkwave tests/sim_build/random_test/apb_mem.fst tb/apb_mem.gtkw   # a saved layout ships in tb/
```

### Common gotchas

| Symptom | Cause / fix |
|---|---|
| cocotb import error or hang | wrong Python — run `/usr/bin/python3 -m pytest` so pytest, cocotb 1.9.2, and the Icarus VPI share one interpreter (not the oss-cad-suite cocotb 2.x on `PATH`). |
| No sim log on a pass | pytest captures stdout — add `-rA` or `-s`. |
| `test_uvm` "passes" instantly | it's skipping — no licensed UVM simulator. Expected here. |
| `test_verilator_lint` / `test_coverage` skip | no Verilator on `PATH`. Install it to enable them. |
| `iverilog: command not found` in the runner | `ICARUS_BIN_DIR` doesn't point at a real Icarus; `conftest.py` defaults it to `/usr/bin`. |
| Wrong-precision timing / clock never ticks | the timescale pin (`1ns/1ps`) in `_sim.py` was dropped — apt Icarus defaults to 1 s precision. |
