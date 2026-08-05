"""Pytest configuration and the environment shim for the cocotb DV flow.

This replaces the environment pinning the source repo's sub-Makefiles did with
``ICARUS_BIN_DIR``, ``env -u VIRTUAL_ENV -u PYTHONHOME`` and the
``PYGPI_PYTHON_BIN``/``PYTHON_BIN`` exports. It must run *before* any cocotb
runner call, so it lives at import time in conftest.
"""

from __future__ import annotations

import os
import sys

import pytest

# --- environment shim (runs at collection import, before any sim build) -------

# Pin the apt Icarus so the cocotb VPI is built against the same interpreter
# that imports the testbench. On this host, `iverilog` on PATH is the
# OSS-CAD-Suite build, whose bundled Python differs from the cocotb interpreter;
# pointing ICARUS_BIN_DIR at /usr/bin selects the apt Icarus that matches. The
# pin is applied narrowly around the cocotb runner calls in _sim.py (NOT to the
# global PATH) so it does not also shadow the PATH-default Verilator that the
# lint/coverage gates rely on — mirroring the source repo's mixed toolchain.
os.environ.setdefault("ICARUS_BIN_DIR", "/usr/bin")

# A stray VIRTUAL_ENV / PYTHONHOME leaks the wrong interpreter into the sim
# subprocess (the Makefiles used `env -u` for the same reason).
os.environ.pop("VIRTUAL_ENV", None)
os.environ.pop("PYTHONHOME", None)

# Bind cocotb's GPI + embed Python to the interpreter running pytest.
os.environ["PYGPI_PYTHON_BIN"] = sys.executable
os.environ["PYTHON_BIN"] = sys.executable


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--waves",
        action="store_true",
        default=False,
        help="dump an FST waveform (tests/sim_build/<test>/*.fst) during sim tests",
    )


@pytest.fixture
def waves(request: pytest.FixtureRequest) -> bool:
    """Whether the current run should dump waveforms (``--waves``)."""
    return bool(request.config.getoption("--waves"))
