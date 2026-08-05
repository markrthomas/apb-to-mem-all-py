"""Low-power (UPF-emulated) power-cycle test — the pytest form of `make lp`.

Builds the two-file LP model with -DLP_EMULATE and runs the single cocotb test
in lp/test_lp.py, which exercises isolation / retention / corruption the way a
real IEEE-1801 flow would derive from lp/apb_mem.upf.
"""

import pytest

from _sim import LP, run_cocotb


@pytest.mark.lp
def test_power_cycle(waves):
    run_cocotb(
        sources=[LP / "apb_mem_array.sv", LP / "apb_mem_lp.sv"],
        hdl_toplevel="apb_mem_lp",
        test_module="test_lp",
        module_dir=LP,
        testcase="power_cycle_test",
        defines={"LP_EMULATE": 1},
        build_name="lp",
        waves=waves,
    )
