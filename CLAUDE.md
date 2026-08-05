# CLAUDE.md

An repo derived from ../uvm_review Git repo that replaces make commands with pytest.

Orientation for working in this repo. The [README](README.md) has the full narrative
and diagrams; [docs/TUTORIAL.md](docs/TUTORIAL.md) is the learn-by-doing version. This
file is the fast path + the things that are easy to trip over.

## What this is

APB3 byte-wide 32K memory (`rtl/apb_mem.sv`) with a self-checking pyuvm/cocotb
testbench, orchestrated by **pytest** instead of a Makefile. Derived from the sibling
`uvm_review` repo: same RTL and testbench, Make targets re-expressed as pytest markers,
each test calling cocotb's Python runner (`cocotb.runner`) once per sim.

## Commands

| Goal | Command |
|---|---|
| Full health check (7 pass, 1 skip) | `pytest` (or `pytest -ra`) |
| The three functional tests | `pytest -m sim` |
| One testcase | `pytest tests/test_functional.py -k random` |
| See the sim log | add `-s` / `-rA` (pytest captures output by default) |
| Dump waves (FST) | add `--waves` |
| Marker selection | `pytest -m "lint or sim"` |
| List tests | `pytest --collect-only -q` |
| Familiar verbs | `make help` (thin shim over the above) |

Use the interpreter that has the apt Icarus VPI + cocotb 1.9.2, i.e.
`/usr/bin/python3 -m pytest`. `pytest` alone is the canonical "is it healthy" check —
expect **7 passed, 1 skipped** (`test_uvm` passes by *skipping* when no UVM simulator is
present; that's correct, not a gap). Verified green on this host 2026-08-05.

## The one thing to understand: the interpreter/toolchain must match

cocotb builds a VPI against a specific Python; the sim subprocess embeds that same
interpreter to import the testbench. So the interpreter running pytest, the cocotb it
imports, and the Icarus whose VPI is loaded must all agree. Two pins in
`tests/conftest.py` / `tests/_sim.py` make that reliable — **do not remove them:**

### Toolchain pins (do NOT assume the `PATH` versions)

| Pin | Where | Why |
|---|---|---|
| `ICARUS_BIN_DIR=/usr/bin` | `conftest.py:25` (`setdefault`) | forces the **apt Icarus 11** even when an oss-cad-suite `iverilog` shadows it on `PATH`. `_sim.py` front-loads this dir on `PATH` only around the runner call, so it does not also shadow Verilator. |
| `PYGPI_PYTHON_BIN` / `PYTHON_BIN` = `sys.executable` | `conftest.py:33-34`, re-passed in `_sim.py` `extra_env` | binds cocotb's GPI + embedded Python to the interpreter running pytest (cocotb 1.9.2 on Python 3.10). |
| drop `VIRTUAL_ENV` / `PYTHONHOME` | `conftest.py:29-30` | a stray venv leaks the wrong interpreter into the sim subprocess (the Makefiles used `env -u` for this). |

Run pytest with the matching interpreter (`/usr/bin/python3 -m pytest`); there is no
env override to point at a different one — pick the interpreter you invoke.

## One sim per test (the fresh-memory contract)

`tests/_sim.py` `run_cocotb()` runs **one `@cocotb.test` per call**, each in its own
`vvp` process with its own `build_dir` (`tests/sim_build/<build_name>`). That's what
gives each testcase a **fresh, time-0-zeroed memory** — the RTL only zeroes its array
at time 0, so sharing a sim across tests causes a seed-dependent scoreboard flake. The
functional tests get one sim each via `@pytest.mark.parametrize`. Don't collapse them
into a shared sim.

## Gates & skip behavior

| Test (marker) | Runner | Skips when… | Passing = |
|---|---|---|---|
| `test_functional.py` (`sim`, ×3) | `run_cocotb` | — | cocotb reports 0 failed |
| `test_lint.py` (`lint`, ×2) | `subprocess` | Verilator absent → verilator part skips (iverilog still runs) | both lints clean |
| `test_coverage.py` (`coverage`) | `subprocess` | Verilator absent → whole gate skips | `line_pct ≥ COV_MIN` (default 100) |
| `test_lowpower.py` (`lp`) | `run_cocotb` (`LP_EMULATE=1`) | — | power-cycle asserts hold |
| `test_uvm.py` (`uvm`) | `subprocess` | no vcs/xrun/qrun → `pytest.skip` | UVM sim exits 0 |

A "skip" is the graceful-degradation path (matches the source Makefile) — the run is
still green.

## Where to make change X

| Task | Touch |
|---|---|
| New functional test | add a sequence (`tb/apb_seq.py`) → `uvm_test` + `@cocotb.test` (`tb/apb_test.py`) → add the name to `CASES` in `tests/test_functional.py` |
| One-off test w/ a define or extra source | a new `test_*.py` that calls `run_cocotb(...)` with `defines=` / extra `sources=` (see `tests/test_lowpower.py`) |
| Change how tests are built/run | `tests/_sim.py` (`run_cocotb`) |
| Change the env/toolchain pinning | `tests/conftest.py` |
| Register a new marker | `pyproject.toml` `[tool.pytest.ini_options].markers` |
| DUT behavior | `rtl/apb_mem.sv` (+ `uvm/` for the SV flow, `lp/` for low-power) |

## Layout

- `rtl/apb_mem.sv` — the DUT.
- `tb/*.py` — pyuvm testbench (`apb_test.py` is the cocotb module; bfm/components/seq/item).
- `tests/*.py` — the pytest layer. **Start at `_sim.py` (`run_cocotb`) and `conftest.py`**
  before touching how tests are built/run.
- `uvm/*.sv` — SV/UVM flow + bound `apb_sva` assertions; only `-m uvm`, skips w/o a license.
- `lp/` — low-power UPF-emulated variant (`-m lp`). `sim/sim_main.cpp` — coverage harness.
- `pyproject.toml` — pytest config + markers; `Makefile` — optional `make`→`pytest` shim.

## Conventions

- Only the BFM (`tb/apb_bfm.py`) touches DUT pins; keep pyuvm components simulator-agnostic.
- `COV_MIN=<n> pytest -m coverage` overrides the 100% line-coverage floor.
  `UVM_TEST=<name> pytest -m uvm` picks the UVM test.
- The `filterwarnings` entry in `pyproject.toml` silences cocotb's "experimental Python
  runner" `UserWarning` — the API use is intentional. Keep it.
