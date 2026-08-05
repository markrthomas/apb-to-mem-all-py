"""Verilator C++ coverage gate — the pytest form of `make coverage`.

Ports the root Makefile's coverage recipe: a Verilator ``--coverage`` build of
the RTL, linked against the sim/sim_main.cpp walker, run to emit coverage.dat,
converted to lcov, and gated on a line-coverage floor (``COV_MIN``, default
100%). Skips cleanly when Verilator is not installed.

Override the floor with the ``COV_MIN`` environment variable, mirroring
``make coverage COV_MIN=<n>``.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

from _sim import REPO

pytestmark = pytest.mark.coverage

COV_DIR = REPO / "sim" / "obj_dir_cov"
COV_INFO = REPO / "sim" / "coverage.info"
RTL = REPO / "rtl" / "apb_mem.sv"
SIM_MAIN = REPO / "sim" / "sim_main.cpp"
COV_MIN = float(os.environ.get("COV_MIN", "100"))


def _verilator_include() -> Path:
    """$(dirname $(command -v verilator))/../share/verilator/include — as the Makefile derives it."""
    vbin = Path(shutil.which("verilator")).resolve()
    return (vbin.parent / ".." / "share" / "verilator" / "include").resolve()


def _run(cmd, **kw):
    result = subprocess.run(cmd, capture_output=True, text=True, **kw)
    assert result.returncode == 0, (
        f"command failed: {' '.join(map(str, cmd))}\n{result.stdout}\n{result.stderr}"
    )
    return result


def _line_coverage_pct(info: Path) -> float:
    """Fraction of DA: (line) entries with a non-zero hit count, as a percentage."""
    found = hit = 0
    for line in info.read_text().splitlines():
        if line.startswith("DA:"):
            found += 1
            _, count = line[3:].split(",", 1)
            if int(count) > 0:
                hit += 1
    return (100.0 * hit / found) if found else 0.0


@pytest.mark.skipif(shutil.which("verilator") is None, reason="verilator not on PATH")
def test_line_coverage_floor():
    if COV_DIR.exists():
        shutil.rmtree(COV_DIR)
    vinc = _verilator_include()

    # 1. Verilator --coverage build of the RTL.
    _run([
        "verilator", "--coverage", "-cc", str(RTL), "--top-module", "apb_mem",
        "--Mdir", str(COV_DIR), "-Wall", "-Wno-DECLFILENAME",
    ])
    # 2. Compile the generated model.
    _run(["make", "-C", str(COV_DIR), "-f", "Vapb_mem.mk"])
    # 3. Link the coverage walker against the model + verilated runtime.
    sim_cov = COV_DIR / "sim_cov"
    _run([
        "g++", "-DVM_COVERAGE=1", "-o", str(sim_cov),
        str(SIM_MAIN), str(COV_DIR / "Vapb_mem__ALL.a"),
        f"-I{COV_DIR}", f"-I{vinc}", f"-I{vinc / 'vltstd'}",
        str(vinc / "verilated.cpp"), str(vinc / "verilated_cov.cpp"),
        str(vinc / "verilated_threads.cpp"),
        "-pthread", "-lm",
    ])
    # 4. Run it (writes coverage.dat into cwd = COV_DIR).
    _run(["./sim_cov"], cwd=COV_DIR)

    # 5. lcov export + floor check.
    if shutil.which("verilator_coverage") is None:
        pytest.skip("verilator_coverage not on PATH — coverage.dat produced but not scored")
    _run([
        "verilator_coverage", "--write-info", str(COV_INFO),
        str(COV_DIR / "coverage.dat"),
    ])
    pct = _line_coverage_pct(COV_INFO)
    assert pct >= COV_MIN, f"line coverage {pct:.1f}% below the {COV_MIN:.0f}% floor"
