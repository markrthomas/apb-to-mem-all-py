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

## UVM on open-source Verilator (`uvm/vlt`)

License-free way to run this repo's UVM env under **Verilator 5.050** (no
VCS/Xcelium/Questa), added 2026-08-28. **Passing** in CI
(`.github/workflows/verilator-uvm.yml`): builds Verilator from source, installs
**z3** (Verilator's SMT solver for `randomize()` — without it constrained
randomize returns 0) + `ccache`, then lint + the `--binary` `write_read` smoke test.

Local (lint is RAM-safe; the `--binary` build wants a big-RAM host or CI):
```sh
V=~/verilator/bin/verilator ; U=~/verilator/test_regress/t/uvm
( unset VERILATOR_ROOT; make -C uvm/vlt lint   VERILATOR=$V UVM_HOME=$U )
( unset VERILATOR_ROOT; make -C uvm/vlt write_read VERILATOR=$V UVM_HOME=$U )
```
In an OSS-off shell (`OSS_CAD=0` / `oss-cad-off`) Verilator 5.050 is on `PATH`,
`VERILATOR_ROOT` is unset, and `UVM_HOME` is exported — the vars/`unset` above are
then optional. Details: `uvm/vlt/README.md`.

## Agent swarms (repo notes)
The swarm itself is the shared kit described in the block below; this repo's profile is `.claude/swarm.env`
(envs: `sim cocotb uvm`; gate: `make check`; RTL in `rtl/`; no cross-check target). There is no random regression yet:
`RR_STATUS=bootstrap`, so the first Swarm B run builds `make rr-build/rr/rr-triage/rr-replay` under `tests/random/`
(rr-bootstrap skill) and opens a PR for it.

<!-- swarm-kit:begin (managed by markrthomas/dv-swarm-kit sync.sh — edit the kit, not this block) -->
## Agent swarms, run targets and tokens (swarm-kit)

This repo carries the shared **DV swarm kit** (`markrthomas/dv-swarm-kit`, version in `.claude/swarm-kit.version`).
Its repo-specific settings are **`.claude/swarm.env`** (`make swarm-profile` prints them); everything else in the
kit is identical across repos — change it in the kit and re-sync, never fork it here.

- **Swarm A** — end-to-end re-verification: `make swarm` (`docker/swarm-task.md`; swarm-manager + one
  dv-env-tester per `DV_ENVS` entry + infra-agent + dv-runner).
- **Swarm B** — random regression: `make swarm-rr` (`docker/rr-swarm-task.md`; rr-manager + rr-runner / rr-triage /
  rr-debugger / rr-test-author). With `RR_STATUS=bootstrap` it first builds `make rr-build/rr/rr-triage/rr-replay`
  (the `rr-bootstrap` skill), then flips the flag to `present`.
- **Plan-driven swarm** — write `docs/SWARM_PLAN.md` with front-matter `status: ready` and push it to `main`
  (`.github/workflows/plan-swarm.yml` runs `docker/plan-swarm-task.md`; reset to `status: draft` after it lands).
- Model provider: `SWARM_MODEL_PROVIDER=anthropic` (default) or `kimi` (`docker/provider-env.sh`; kimi sends repo
  contents to Moonshot - never for proprietary IP). One-off headless task: `docker/entrypoint.sh agent "<task>"`.
- Status board: `make board`; workers report via `python3 tools/swarm/board.py` (the `board-report` skill).
- Heavy targets (`HEAVY_TARGETS`) run one at a time: `make heavy T=<target>`. Headless Bash is limited to
  `.claude/settings.json`. `make swarm-dry` shows what a swarm run would execute; `make swarm-kit-check` checks drift.

Doctrine (all agents): verify every claim against a real artifact ("no artifact = not verified"); never weaken or skip
a checker to get green; a skip is "not run", not a pass; keep the RTL assertion-free; DUT behaviour changes are the
owner's call (write them up, don't merge them); branches `swarm/<date>-<topic>`; never push to `main`, never force-push.
Return findings as verdict + evidence (file:line / command + 3-10 line excerpt) + next step — no log dumps.

**Where it runs** (same image everywhere: the Dockerfile `tools` stage, plus the repo for `full`):
| where | how | credentials |
|---|---|---|
| GitHub Actions | Actions → **swarm** → Run workflow (task: Swarm A or B) | repo secret `CLAUDE_CODE_OAUTH_TOKEN` |
| Codespaces | open a Codespace (`.devcontainer/`), then `make swarm`, `make swarm-rr` or `make batch` | Codespaces secret `CLAUDE_CODE_OAUTH_TOKEN`; `GITHUB_TOKEN` is injected |
| Railway | batch service built from `railway.toml` (weekly cron); swarm service: start command `docker/entrypoint.sh swarm [--task docker/rr-swarm-task.md]` | service variables `CLAUDE_CODE_OAUTH_TOKEN` (swarm only) and `GITHUB_TOKEN` (fine-grained PAT: this repo, Contents read+write) |

Batch results go to the `metrics-data` branch (`runs/<UTC>-<sha>/`), never to `main`: automatically on Railway
(when `GITHUB_TOKEN` is set), elsewhere only with `PUBLISH_METRICS=1`. Tokens live only in
GitHub/Codespaces/Railway secret stores — never in the repo, the image, a log or a chat.
<!-- swarm-kit:end -->
