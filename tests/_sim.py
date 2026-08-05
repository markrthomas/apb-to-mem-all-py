"""Shared cocotb-runner helper for the pytest DV flow.

This module is the pytest replacement for cocotb's ``Makefile.sim`` include and
the root Makefile's ``run_one_test`` recipe. It drives cocotb's experimental
Python runner API (``cocotb.runner``, available in cocotb 1.9.2) to build the
DUT with Icarus and run a single ``@cocotb.test`` per call.

Running exactly one cocotb test per invocation — in its own ``vvp`` process —
reproduces the "fresh memory per test" property the Makefile hand-rolled: the
RTL only zeroes its array at time 0, so one sim per test avoids the seed-
dependent scoreboard flake where a later test reads a location an earlier test
wrote.

Deliberately named with a leading underscore so pytest does NOT collect it as a
test module; the cocotb testbench modules it launches (``apb_test``, ``test_lp``)
are imported by the sim process, not by pytest.
"""

from __future__ import annotations

import contextlib
import os
import sys
from pathlib import Path
from typing import Iterator, Mapping, Sequence

from cocotb.runner import get_results, get_runner

REPO = Path(__file__).resolve().parent.parent
RTL = REPO / "rtl"
TB = REPO / "tb"
LP = REPO / "lp"
BUILD_ROOT = REPO / "tests" / "sim_build"


def _prepend_pythonpath(module_dir: Path) -> None:
    """Ensure the sim process can import the cocotb testbench modules.

    cocotb launches the simulator as a subprocess that imports ``test_module``;
    it must find the testbench package. The runner rebuilds the child's
    PYTHONPATH from the parent's ``sys.path`` (see ``Simulator._set_env``), so
    the testbench directory has to be on ``sys.path`` here — mutating
    ``os.environ["PYTHONPATH"]`` alone would be overwritten. Mirrors the
    sub-Makefiles' ``export PYTHONPATH := $(PWD):$(PYTHONPATH)``.
    """
    module_dir = str(module_dir)
    if module_dir not in sys.path:
        sys.path.insert(0, module_dir)


@contextlib.contextmanager
def _pinned_icarus_on_path() -> Iterator[None]:
    """Temporarily front-load ICARUS_BIN_DIR on PATH for the runner subprocess.

    The cocotb Python runner invokes a bare ``iverilog``/``vvp`` from PATH and
    does not honor ICARUS_BIN_DIR the way cocotb's Makefile flow does. Scope the
    change to the build+run so it does not shadow the PATH-default Verilator used
    by the lint/coverage gates. Restored on exit regardless of outcome.
    """
    icarus_dir = os.environ.get("ICARUS_BIN_DIR")
    old_path = os.environ.get("PATH", "")
    if icarus_dir and os.path.isdir(icarus_dir):
        os.environ["PATH"] = icarus_dir + os.pathsep + old_path
    try:
        yield
    finally:
        os.environ["PATH"] = old_path


def run_cocotb(
    *,
    sources: Sequence[Path],
    hdl_toplevel: str,
    test_module: str,
    module_dir: Path,
    testcase: str,
    defines: Mapping[str, object] | None = None,
    build_name: str,
    waves: bool = False,
) -> None:
    """Build + run a single cocotb testcase under Icarus; assert it passed.

    Each call uses its own ``build_dir`` (``tests/sim_build/<build_name>``) so
    parametrized tests never clobber one another's compiled sim or results.xml.
    """
    _prepend_pythonpath(module_dir)
    build_dir = BUILD_ROOT / build_name

    # Icarus defaults to a 1-second precision when no `timescale is present;
    # the testbench drives a 10 ns clock, so pin 1ns/1ps (matches the SV/UVM TB).
    timescale = ("1ns", "1ps")

    runner = get_runner("icarus")
    with _pinned_icarus_on_path():
        runner.build(
            verilog_sources=[str(s) for s in sources],
            hdl_toplevel=hdl_toplevel,
            build_args=["-g2012"],
            defines=dict(defines or {}),
            build_dir=str(build_dir),
            always=True,
            waves=waves,
            timescale=timescale,
        )
        results_xml = runner.test(
            test_module=test_module,
            hdl_toplevel=hdl_toplevel,
            hdl_toplevel_lang="verilog",
            testcase=testcase,
            plusargs=(["-fst"] if waves else []),
            build_dir=str(build_dir),
            test_dir=str(build_dir),
            timescale=timescale,
            extra_env={"PYGPI_PYTHON_BIN": sys.executable, "PYTHON_BIN": sys.executable},
        )
    total, failed = get_results(results_xml)
    assert failed == 0, f"{testcase}: {failed}/{total} cocotb test(s) failed (see log above)"
