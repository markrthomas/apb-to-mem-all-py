"""RTL lint gate — the pytest form of `make lint`.

  * iverilog -g2012 -Wall compile check (always run; the sim toolchain is a
    hard dependency of this repo).
  * Verilator --lint-only (skipped cleanly when Verilator is absent, matching
    the Makefile's graceful degradation).
"""

import os
import shutil
import subprocess

import pytest

from _sim import RTL

APB_MEM = str(RTL / "apb_mem.sv")

# Use the apt Icarus that ICARUS_BIN_DIR pins for the sim, so lint and sim agree
# on the same compiler. Falls back to whatever `iverilog` is on PATH.
_IVERILOG = os.path.join(os.environ.get("ICARUS_BIN_DIR", ""), "iverilog")
if not os.path.exists(_IVERILOG):
    _IVERILOG = shutil.which("iverilog") or "iverilog"


@pytest.mark.lint
def test_iverilog_compile():
    """RTL must pass a -Wall compile check with SystemVerilog enabled."""
    result = subprocess.run(
        [_IVERILOG, "-g2012", "-Wall", "-o", os.devnull, APB_MEM],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"iverilog compile check failed:\n{result.stdout}\n{result.stderr}"
    )


@pytest.mark.lint
@pytest.mark.skipif(shutil.which("verilator") is None, reason="verilator not on PATH")
def test_verilator_lint():
    """RTL must pass Verilator's linter (DECLFILENAME waived, as in the Makefile)."""
    result = subprocess.run(
        ["verilator", "--lint-only", "-Wall", "-Wno-DECLFILENAME", APB_MEM],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"verilator lint failed:\n{result.stdout}\n{result.stderr}"
    )
