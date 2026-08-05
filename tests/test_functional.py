"""Functional cocotb/pyuvm regression — the pytest form of `make test-all`.

Each parametrized case runs a single cocotb test in its own Icarus simulation
(fresh, time-0-zeroed memory), mirroring the root Makefile's `run_one_test`.

  * write_read  -> `make test-write-read`
  * random      -> `make test-random`
  * walking     -> `make test-walking`
  * all three   -> `make test` / `make test-all`
"""

import pytest

from _sim import RTL, TB, run_cocotb

# cocotb testcase name (in tb/apb_test.py) -> pytest-friendly short id.
CASES = ["write_read_test", "random_test", "walking_test"]


@pytest.mark.sim
@pytest.mark.parametrize("testcase", CASES)
def test_apb(testcase, waves):
    run_cocotb(
        sources=[RTL / "apb_mem.sv"],
        hdl_toplevel="apb_mem",
        test_module="apb_test",
        module_dir=TB,
        testcase=testcase,
        build_name=testcase,
        waves=waves,
    )
