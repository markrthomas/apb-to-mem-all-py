# UVM on open-source Verilator (`uvm/vlt`)

Runs the same UVM environment as a commercial simulator, but under open-source
**Verilator 5.050** (the first Verilator that can elaborate/run UVM) with the
Accellera UVM 2020.3.1 library bundled in the Verilator source tree
(`test_regress/t/uvm`). License-free CI path; the repo's `make uvm` (pyuvm)
otherwise self-skips without a licensed UVM simulator.

## Prerequisites
- **Verilator >= 5.050, UVM-capable** (the OSS CAD Suite one is not). Local
  reference: `~/verilator/bin/verilator`.
- **`unset VERILATOR_ROOT`** after sourcing the OSS CAD Suite env (a stale value
  makes `~/verilator` hard-error).
- **`UVM_HOME`** = `~/verilator/test_regress/t/uvm`.
- **In an OSS-off shell** (`OSS_CAD=0` at start, or `oss-cad-off`) `~/.bashrc`
  already puts Verilator 5.050 on `PATH`, unsets `VERILATOR_ROOT`, and exports
  `UVM_HOME` — so the explicit `VERILATOR=`/`UVM_HOME=` and `unset` below are
  optional there.

## Usage
```sh
V=~/verilator/bin/verilator ; U=~/verilator/test_regress/t/uvm
( unset VERILATOR_ROOT; make -C uvm/vlt lint       VERILATOR=$V UVM_HOME=$U )  # RAM-safe (~290 MB)
( unset VERILATOR_ROOT; make -C uvm/vlt write_read  VERILATOR=$V UVM_HOME=$U )  # build + run
```
Targets: `lint`; `write_read` (default), `random`, `walking`, `all`; `clean`.
One `--binary` build serves all three tests (selected via `+UVM_TESTNAME`).

## RAM note — build in CI, not on a small box
`--lint-only` is cheap (~290 MB). The full `--binary` build (large generated
C++) OOMs a RAM-constrained host. Run it in CI
(`.github/workflows/verilator-uvm.yml` builds Verilator 5.050 from source and
runs lint + `write_read` on a GitHub runner), or locally only with
`BUILD_JOBS=1` under a `ulimit -v` guard.

## `uvm_macros.svh`
A required, tracked empty include-shim: the sources `` `include "uvm_macros.svh" ``
and the monolithic UVM header (first on the command line) already defines the
macros. Do not delete.
