// UVM macro include shim for the open-source (Verilator) UVM flow.
//
// The env packages `include "uvm_macros.svh"; under a commercial simulator that
// resolves to $UVM_HOME/src/uvm_macros.svh. This flow instead compiles the
// Accellera library as the single monolithic header uvm_pkg_all_v2020_3_1_dpi.svh
// (listed first on the tool command line), which already defines every `uvm_*
// macro. This stub just satisfies the `include so the same sources compile
// unchanged; it deliberately defines nothing. Only ever on the OSS flow's
// +incdir (see uvm/vlt/Makefile).
//
// (First comment word avoids "verilator", which the tool parses as a pragma.)
