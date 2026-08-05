"""SystemVerilog UVM flow — the pytest form of `make uvm`.

The uvm/ testbench needs a UVM-capable commercial simulator (VCS, Xcelium, or
Questa). None is licensed on this host, so — exactly like the source Makefile —
this test DEGRADES GRACEFULLY: it detects an available simulator and, finding
none, skips. On a licensed host it runs the multi-file TB for real.

Select the UVM test with the UVM_TEST env var (default apb_write_read_test).
"""

import os
import shutil
import subprocess

import pytest

from _sim import REPO

pytestmark = pytest.mark.uvm

UVM = REPO / "uvm"
RTL = REPO / "rtl" / "apb_mem.sv"
UVM_TEST = os.environ.get("UVM_TEST", "apb_write_read_test")

# Multi-file compile order (matches uvm/Makefile MULTI_SRC): interface, DUT,
# assertion checker, package, top.
SOURCES = [
    str(UVM / "apb_if.sv"),
    str(RTL),
    str(UVM / "apb_sva.sv"),
    str(UVM / "apb_pkg.sv"),
    str(UVM / "apb_tb_top.sv"),
]


def _run(cmd, **kw):
    result = subprocess.run(cmd, cwd=str(UVM), capture_output=True, text=True, **kw)
    assert result.returncode == 0, (
        f"UVM sim failed: {' '.join(cmd)}\n{result.stdout}\n{result.stderr}"
    )
    return result


def test_uvm():
    if shutil.which("vcs"):
        _run(["vcs", "-full64", "-sverilog", "-ntb_opts", "uvm-1.2",
              "-timescale=1ns/1ps", "+incdir+.", *SOURCES, "-o", "simv"])
        _run(["./simv", f"+UVM_TESTNAME={UVM_TEST}"])
    elif shutil.which("xrun"):
        _run(["xrun", "-64bit", "-sv", "-uvm", "-timescale", "1ns/1ps",
              "-incdir", ".", *SOURCES, f"+UVM_TESTNAME={UVM_TEST}"])
    elif shutil.which("qrun"):
        _run(["qrun", "-64", "-sv", "-uvm", "-timescale", "1ns/1ps", "+incdir+.",
              *SOURCES, "-top", "apb_tb_top", f"+UVM_TESTNAME={UVM_TEST}"])
    else:
        pytest.skip(
            "no UVM simulator (vcs/xrun/qrun) on PATH — this host has no "
            "SystemVerilog/UVM license; run on a licensed host to execute."
        )
