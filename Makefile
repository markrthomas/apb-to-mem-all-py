# =============================================================================
# apb-to-mem-all-py — OPTIONAL convenience wrapper.
#
# The canonical interface for this repo is pytest (see README). This Makefile is
# a thin, optional shim that maps the familiar `make` verbs from the source
# uvm_review repo onto the equivalent pytest invocations — nothing here does
# work of its own, it just shells out to pytest.
#
#   PYTHON   interpreter that has cocotb 1.9.2 + pyuvm + (for `make`) pytest,
#            and matches the apt Icarus VPI. Defaults to /usr/bin/python3.
#   TEST     single testcase for test-one/waves/wave (e.g. TEST=random_test)
#   ARGS     extra flags appended to the pytest command (e.g. ARGS="-v -x")
# =============================================================================

PYTHON ?= /usr/bin/python3
PYTEST := $(PYTHON) -m pytest
FUNC   := tests/test_functional.py

.PHONY: default help \
	test test-all test-write-read test-random test-walking test-one \
	lp lint coverage uvm check regress ci \
	waves wave clean

default: help

help:
	@echo "apb-to-mem-all-py — optional make wrapper (delegates to pytest)"
	@echo ""
	@echo "  Tests (cocotb / pyuvm):"
	@echo "    make test / test-all     # pytest -m sim (all three functional tests)"
	@echo "    make test-write-read     # single: write-then-read-back"
	@echo "    make test-random         # single: constrained-random mix"
	@echo "    make test-walking        # single: directed edge cases"
	@echo "    make test-one TEST=<name># single: any cocotb testcase by name"
	@echo ""
	@echo "  Other gates:"
	@echo "    make lp                  # pytest -m lp  (low-power UPF demo)"
	@echo "    make lint                # pytest -m lint  (iverilog + verilator)"
	@echo "    make coverage            # pytest -m coverage  (verilator floor)"
	@echo "    make uvm                 # pytest -m uvm  (skips w/o a UVM sim)"
	@echo ""
	@echo "  Aggregates:"
	@echo "    make check               # lint + functional        (-m 'lint or sim')"
	@echo "    make regress             # lint + functional + lp   (-m 'lint or sim or lp')"
	@echo "    make ci                  # everything (plain pytest; uvm self-skips)"
	@echo ""
	@echo "  Waves / housekeeping:"
	@echo "    make waves [TEST=<name>] # dump FST(s) via --waves"
	@echo "    make wave [TEST=<name>]  # dump then open in GTKWave (default: random_test)"
	@echo "    make clean               # remove build/sim/coverage artifacts"
	@echo ""
	@echo "  Vars: PYTHON=$(PYTHON)  TEST=<testcase>  ARGS=<extra pytest flags>"

# --- functional --------------------------------------------------------------

test: test-all

test-all:
	$(PYTEST) -m sim $(ARGS)

test-write-read:
	$(PYTEST) $(FUNC) -k write_read $(ARGS)

test-random:
	$(PYTEST) $(FUNC) -k random $(ARGS)

test-walking:
	$(PYTEST) $(FUNC) -k walking $(ARGS)

# Run a single cocotb testcase by name, e.g. `make test-one TEST=random_test`.
test-one:
	@if [ -z "$(TEST)" ]; then echo "usage: make test-one TEST=<testcase>"; exit 2; fi
	$(PYTEST) $(FUNC) -k $(TEST) $(ARGS)

# --- other gates -------------------------------------------------------------

lp:
	$(PYTEST) -m lp $(ARGS)

lint:
	$(PYTEST) -m lint $(ARGS)

coverage:
	$(PYTEST) -m coverage $(ARGS)

uvm:
	$(PYTEST) -m uvm $(ARGS)

# --- aggregates --------------------------------------------------------------

check:
	$(PYTEST) -m "lint or sim" $(ARGS)

regress:
	$(PYTEST) -m "lint or sim or lp" $(ARGS)

ci:
	$(PYTEST) $(ARGS)

# --- waves -------------------------------------------------------------------

# Dump FST waveform(s). With TEST=<name> only that testcase runs; otherwise all
# three functional tests dump into tests/sim_build/<testcase>/apb_mem.fst.
waves:
	$(PYTEST) $(FUNC) $(if $(TEST),-k $(TEST),) --waves $(ARGS)

# Regenerate a fresh dump for one testcase and open it in GTKWave with the
# curated layout. Skips cleanly if GTKWave is not installed. Defaults to the
# random test when TEST is not given (`make wave`); override with TEST=<name>.
WAVE_TEST := $(if $(TEST),$(TEST),random_test)

wave:
	$(PYTEST) $(FUNC) -k $(WAVE_TEST) --waves $(ARGS)
	@if command -v gtkwave >/dev/null 2>&1; then \
		echo "[WAVE] opening tests/sim_build/$(WAVE_TEST)/apb_mem.fst"; \
		exec gtkwave tests/sim_build/$(WAVE_TEST)/apb_mem.fst tb/apb_mem.gtkw; \
	else \
		echo "[WAVE] gtkwave not on PATH — dump is at tests/sim_build/$(WAVE_TEST)/apb_mem.fst"; \
	fi

# --- clean -------------------------------------------------------------------

clean:
	rm -rf tests/sim_build sim/obj_dir_cov sim/coverage.info sim/coverage.dat \
		.pytest_cache tests/__pycache__ tb/__pycache__ lp/__pycache__ \
		uvm/simv uvm/simv.daidir uvm/csrc uvm/*.log
	@echo "[CLEAN] removed build/sim/coverage artifacts"
