// -----------------------------------------------------------------------------
// apb_tb_top : simulation top. Generates PCLK, binds the DUT to the APB
// interface, publishes the virtual interface to the UVM config DB, and launches
// UVM via run_test (the test is selected with +UVM_TESTNAME=<name>).
//
// This is the SV analogue of the cocotb entry points in tb/apb_test.py; the
// three tests map as:
//   +UVM_TESTNAME=apb_write_read_test   <-  write_read_test
//   +UVM_TESTNAME=apb_random_test       <-  random_test
//   +UVM_TESTNAME=apb_walking_test      <-  walking_test
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module apb_tb_top;

    import uvm_pkg::*;
    import apb_pkg::*;
    `include "uvm_macros.svh"

    // 10 ns clock, matching the pyuvm BFM's 10 ns period.
    logic PCLK = 1'b0;
    always #5 PCLK = ~PCLK;

    apb_if #(.ADDR_WIDTH(15), .DATA_WIDTH(8)) apb (.PCLK(PCLK));

    apb_mem #(.ADDR_WIDTH(15), .DATA_WIDTH(8)) dut (
        .PCLK    (apb.PCLK),
        .PRESETn (apb.PRESETn),
        .PSEL    (apb.PSEL),
        .PENABLE (apb.PENABLE),
        .PWRITE  (apb.PWRITE),
        .PADDR   (apb.PADDR),
        .PWDATA  (apb.PWDATA),
        .PRDATA  (apb.PRDATA),
        .PREADY  (apb.PREADY),
        .PSLVERR (apb.PSLVERR)
    );

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb);
        // Default to the write-read test; +UVM_TESTNAME overrides it when given
        // (so it "just runs" on EDA Playground with no run-option set).
        run_test("apb_write_read_test");
    end

    // Optional waves: +define+DUMP (or a per-tool flag) enables an FSDB/VCD dump.
`ifdef DUMP
    initial begin
        $dumpfile("apb_tb_top.vcd");
        $dumpvars(0, apb_tb_top);
    end
`endif

endmodule
