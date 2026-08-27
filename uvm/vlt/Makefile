# Verilator UVM flow for the APB memory UVM environment (../, ../../rtl).
#
# Runs the *same* SystemVerilog UVM env as a commercial simulator would, but
# under open-source Verilator (>= 5.050, which can elaborate/run UVM) using the
# Accellera UVM 2020.3.1 library bundled in the Verilator source tree
# (test_regress/t/uvm), mirror: chipsalliance/uvm-verilator.
#
# Quick start (local lint is RAM-safe; the full --binary build belongs in CI):
#   V=~/verilator/bin/verilator ; U=~/verilator/test_regress/t/uvm
#   ( unset VERILATOR_ROOT; make -C uvm/vlt lint    VERILATOR=$V UVM_HOME=$U )
#   ( unset VERILATOR_ROOT; make -C uvm/vlt write_read VERILATOR=$V UVM_HOME=$U )

VERILATOR ?= verilator

UVM_HOME ?= $(error Set UVM_HOME to the bundled Verilator UVM dir, e.g. \
  ~/verilator/test_regress/t/uvm)
UVM_HDR := $(UVM_HOME)/uvm_pkg_all_v2020_3_1_dpi.svh
UVM_DPI := $(UVM_HOME)/v2020_3_1/dpi/uvm_dpi.cc

# The generated UVM C++ is large; more jobs build faster but use more RAM.
# BUILD_JOBS=1 is the RAM-safe default; CI raises it to $(nproc).
BUILD_JOBS ?= 1

# --binary: self-contained exe; --timing: UVM needs event/#delay; --vpi: UVM DPI.
# -O0 keeps the (large) UVM C++ compile within a modest RAM budget; -Wno-fatal
# keeps library-side width/timescale warnings non-fatal.
VFLAGS ?= --binary --timing --vpi -j $(BUILD_JOBS) --build-jobs $(BUILD_JOBS) \
          -Wno-fatal -Wno-COVERIGN -Wno-TIMESCALEMOD --CFLAGS -O0

UVM_PLUSARGS ?= +UVM_NO_RELNOTES

VLT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
UVM     := $(abspath $(VLT_DIR)/..)
RTL     := $(abspath $(VLT_DIR)/../../rtl)
OBJ     := $(VLT_DIR)/obj

INCS := +incdir+$(UVM) +incdir+$(VLT_DIR) +incdir+$(UVM_HOME)

# Order: interface, RTL, package (pulls in the env via `include), then top.
SRCS := $(UVM)/apb_if.sv $(RTL)/apb_mem.sv $(UVM)/apb_pkg.sv $(UVM)/apb_tb_top.sv

# $(call build) -> compile apb_tb_top into $(OBJ)/apb_tb_top/Vapb_tb_top
define build
	rm -rf $(OBJ)/apb_tb_top
	mkdir -p $(OBJ)/apb_tb_top
	$(VERILATOR) $(VFLAGS) --top-module apb_tb_top --Mdir $(OBJ)/apb_tb_top \
	  $(INCS) $(UVM_HDR) $(UVM_DPI) $(SRCS)
endef
# $(call run,<uvm_test_name>)
define run
	$(OBJ)/apb_tb_top/Vapb_tb_top $(UVM_PLUSARGS) +UVM_TESTNAME=$(1)
endef

.PHONY: all build write_read random walking lint clean

# One --binary build; the top selects the test at run time via +UVM_TESTNAME.
# `build` is phony but make runs it once per invocation, so `make all` builds once.
all: write_read random walking

build:
	$(build)

write_read: build
	$(call run,apb_write_read_test)

random: build
	$(call run,apb_random_test)

walking: build
	$(call run,apb_walking_test)

# RAM-safe elaborate-only smoke check (~330 MB, seconds). No C++ build.
LINTFLAGS ?= --lint-only --timing -Wno-fatal -Wno-COVERIGN -Wno-TIMESCALEMOD
lint:
	$(VERILATOR) $(LINTFLAGS) --top-module apb_tb_top $(INCS) \
	  $(UVM_HDR) $(SRCS)

clean:
	rm -rf $(OBJ)
