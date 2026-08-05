// =============================================================================
// apb_tb_single.sv — single-file variant of the SystemVerilog UVM testbench.
//
// Identical in behaviour to the multi-file testbench (apb_if.sv + apb_pkg.sv +
// the class files + apb_tb_top.sv); every TB piece is gathered here into one
// file for drop-in use (e.g. EDA Playground) or a single -f entry. The DUT RTL
// (../rtl/apb_mem.sv) stays separate as the single source of truth.
//
// NOTE: this file and the multi-file set define the same names (apb_if,
// apb_pkg, apb_tb_top, the tests) — compile ONE or the OTHER, never both.
//
// Run:  <sim> ... ../rtl/apb_mem.sv apb_tb_single.sv +UVM_TESTNAME=<test>
//   apb_write_read_test | apb_random_test | apb_walking_test
// =============================================================================
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// APB3 signal bundle (interfaces must live outside a package).
// -----------------------------------------------------------------------------
interface apb_if #(
    parameter int ADDR_WIDTH = 15,
    parameter int DATA_WIDTH = 8
) (
    input logic PCLK
);
    logic                  PRESETn;
    // request channel
    logic                  PSEL;
    logic                  PENABLE;
    logic                  PWRITE;
    logic [ADDR_WIDTH-1:0] PADDR;
    logic [DATA_WIDTH-1:0] PWDATA;
    // response channel
    logic [DATA_WIDTH-1:0] PRDATA;
    logic                  PREADY;
    logic                  PSLVERR;
endinterface


// -----------------------------------------------------------------------------
// UVM environment (sequence item, sequences, components, tests).
// -----------------------------------------------------------------------------
package apb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // -- transaction ----------------------------------------------------------
    // One APB read or write transfer. convert2string reports the observable
    // transfer; the `uvm_field_int macros provide copy / compare / print.
    class apb_seq_item extends uvm_sequence_item;

        rand bit [14:0] addr;   // ADDR_MASK = 0x7FFF
        rand bit [7:0]  data;   // DATA_MASK = 0xFF
        rand bit        write;
        bit [7:0]       rdata;

        `uvm_object_utils_begin(apb_seq_item)
            `uvm_field_int(addr,  UVM_ALL_ON)
            `uvm_field_int(data,  UVM_ALL_ON)
            `uvm_field_int(write, UVM_ALL_ON)
            `uvm_field_int(rdata, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "apb_seq_item");
            super.new(name);
        endfunction

        // Payload that actually matters for this direction.
        function bit [7:0] payload();
            return write ? data : rdata;
        endfunction

        function string convert2string();
            return $sformatf("%s @0x%04X = 0x%02X",
                             write ? "WR" : "RD", addr, payload());
        endfunction

    endclass

    // -- sequences ------------------------------------------------------------
    // Write a value, then read it back from the same address.
    class apb_write_read_seq extends uvm_sequence #(apb_seq_item);
        `uvm_object_utils(apb_write_read_seq)

        int unsigned num = 32;

        function new(string name = "apb_write_read_seq");
            super.new(name);
        endfunction

        task body();
            apb_seq_item wr, rd;
            for (int unsigned i = 0; i < num; i++) begin
                // Random write: solver picks addr/data, direction constrained.
                wr = apb_seq_item::type_id::create("wr");
                start_item(wr);
                if (!wr.randomize() with { write == 1'b1; })
                    `uvm_error("RAND", "apb_seq_item randomize failed")
                finish_item(wr);

                // Read back the same address (constrained to the write's addr).
                rd = apb_seq_item::type_id::create("rd");
                start_item(rd);
                if (!rd.randomize() with { write == 1'b0; addr == wr.addr; })
                    `uvm_error("RAND", "apb_seq_item randomize failed")
                finish_item(rd);
            end
        endtask
    endclass

    // Random mix of reads and writes. Reads are biased 4:1 toward addresses
    // that have already been written, so they mostly check stored data instead
    // of reading never-written locations (which return 0); writes stay fully
    // random to populate the set. All randomization is constraint-based.
    class apb_random_seq extends uvm_sequence #(apb_seq_item);
        `uvm_object_utils(apb_random_seq)

        int unsigned num = 64;

        function new(string name = "apb_random_seq");
            super.new(name);
        endfunction

        task body();
            apb_seq_item item;
            bit [14:0]   written[$];
            for (int unsigned i = 0; i < num; i++) begin
                item = apb_seq_item::type_id::create("item");
                start_item(item);
                if (!item.randomize())
                    `uvm_error("RAND", "apb_seq_item randomize failed")
                // For reads, re-pick the address 4:1 in favour of a written one.
                if (!item.write && written.size() > 0) begin
                    bit        hit_written;
                    int        idx;
                    bit [14:0] target;
                    if (!std::randomize(hit_written) with {
                            hit_written dist { 1 := 4, 0 := 1 }; })
                        `uvm_error("RAND", "bias randomize failed")
                    if (hit_written) begin
                        if (!std::randomize(idx) with {
                                idx inside { [0:written.size()-1] }; })
                            `uvm_error("RAND", "index randomize failed")
                        target = written[idx];
                        if (!item.randomize() with {
                                write == 1'b0; addr == target; })
                            `uvm_error("RAND", "apb_seq_item randomize failed")
                    end
                end
                finish_item(item);
                if (item.write) written.push_back(item.addr);
            end
        endtask
    endclass

    // Directed edge cases: first/last address and all-0 / all-1 payloads.
    class apb_walking_seq extends uvm_sequence #(apb_seq_item);
        `uvm_object_utils(apb_walking_seq)

        function new(string name = "apb_walking_seq");
            super.new(name);
        endfunction

        task body();
            apb_seq_item wr, rd;
            bit [14:0] edge_addrs[] = '{15'h0000, 15'h0001, 15'h7FFE, 15'h7FFF};
            bit [7:0]  edge_data[]  = '{8'h00, 8'h01, 8'h55, 8'hAA, 8'hFF};
            foreach (edge_addrs[ai]) begin
                foreach (edge_data[di]) begin
                    wr = apb_seq_item::type_id::create("wr");
                    start_item(wr);
                    wr.addr = edge_addrs[ai]; wr.data = edge_data[di];
                    wr.write = 1'b1;
                    finish_item(wr);

                    rd = apb_seq_item::type_id::create("rd");
                    start_item(rd);
                    rd.addr = edge_addrs[ai]; rd.write = 1'b0;
                    finish_item(rd);
                end
            end
        endtask
    endclass

    // -- driver ---------------------------------------------------------------
    // Serialises items onto the bus; writes captured PRDATA into read items.
    // Timing mirrors the pyuvm BFM: drive on the falling edge, sample PREADY on
    // the rising edge of the ACCESS phase.
    class apb_driver extends uvm_driver #(apb_seq_item);
        `uvm_component_utils(apb_driver)

        virtual apb_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "no virtual interface set for apb_driver")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                seq_item_port.get_next_item(req);
                drive_transfer(req);
                seq_item_port.item_done();
            end
        endtask

        // SETUP (PENABLE=0) -> ACCESS (PENABLE=1, wait PREADY) -> IDLE.
        task automatic drive_transfer(apb_seq_item item);
            @(negedge vif.PCLK);
            vif.PSEL    <= 1'b1;
            vif.PENABLE <= 1'b0;
            vif.PWRITE  <= item.write;
            vif.PADDR   <= item.addr;
            vif.PWDATA  <= item.data;

            @(negedge vif.PCLK);
            vif.PENABLE <= 1'b1;

            @(posedge vif.PCLK);
            while (vif.PREADY !== 1'b1) @(posedge vif.PCLK);
            if (!item.write)
                item.rdata = vif.PRDATA;   // return read data to the sequence

            @(negedge vif.PCLK);
            vif.PSEL    <= 1'b0;
            vif.PENABLE <= 1'b0;
            vif.PWRITE  <= 1'b0;
        endtask

    endclass

    // -- monitor --------------------------------------------------------------
    // Broadcasts every completed transfer (ACCESS phase with PREADY high).
    class apb_monitor extends uvm_monitor;
        `uvm_component_utils(apb_monitor)

        virtual apb_if vif;
        uvm_analysis_port #(apb_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "no virtual interface set for apb_monitor")
        endfunction

        task run_phase(uvm_phase phase);
            apb_seq_item tr;
            forever begin
                @(posedge vif.PCLK);
                if (vif.PSEL === 1'b1 && vif.PENABLE === 1'b1 &&
                        vif.PREADY === 1'b1) begin
                    tr = apb_seq_item::type_id::create("mon");
                    tr.addr  = vif.PADDR;
                    tr.write = vif.PWRITE;
                    tr.data  = vif.PWDATA;
                    tr.rdata = vif.PRDATA;
                    `uvm_info("MON",
                              $sformatf("observed %s", tr.convert2string()),
                              UVM_MEDIUM)
                    ap.write(tr);
                end
            end
        endtask

    endclass

    // -- agent ----------------------------------------------------------------
    typedef uvm_sequencer #(apb_seq_item) apb_sequencer;

    class apb_agent extends uvm_agent;
        `uvm_component_utils(apb_agent)

        apb_sequencer seqr;
        apb_driver    driver;
        apb_monitor   monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            seqr    = apb_sequencer::type_id::create("seqr", this);
            driver  = apb_driver::type_id::create("driver", this);
            monitor = apb_monitor::type_id::create("monitor", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            driver.seq_item_port.connect(seqr.seq_item_export);
        endfunction

    endclass

    // -- scoreboard -----------------------------------------------------------
    // Reference byte memory; checks every read against the last write.
    class apb_scoreboard extends uvm_component;
        `uvm_component_utils(apb_scoreboard)

        uvm_analysis_imp #(apb_seq_item, apb_scoreboard) analysis_export;

        bit [7:0] model [bit [14:0]];   // reference memory
        int       reads  = 0;
        int       errors = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            analysis_export = new("analysis_export", this);
        endfunction

        // Called for every monitored transfer, in bus order.
        function void write(apb_seq_item tr);
            if (tr.write) begin
                model[tr.addr] = tr.data;
            end else begin
                bit [7:0] expected = model.exists(tr.addr) ? model[tr.addr]
                                                           : 8'h00;
                reads++;
                if (tr.rdata !== expected) begin
                    errors++;
                    `uvm_error("MISMATCH", $sformatf(
                        "@0x%04X: got 0x%02X exp 0x%02X",
                        tr.addr, tr.rdata, expected))
                end else begin
                    `uvm_info("MATCH", tr.convert2string(), UVM_MEDIUM)
                end
            end
        endfunction

        function void check_phase(uvm_phase phase);
            `uvm_info("SCOREBOARD", $sformatf(
                "%0d reads checked, %0d errors", reads, errors), UVM_LOW)
            if (errors != 0)
                `uvm_error("SCOREBOARD",
                    $sformatf("%0d scoreboard mismatch(es)", errors))
        endfunction

    endclass

    // -- env ------------------------------------------------------------------
    class apb_env extends uvm_env;
        `uvm_component_utils(apb_env)

        apb_agent      agent;
        apb_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = apb_agent::type_id::create("agent", this);
            scoreboard = apb_scoreboard::type_id::create("scoreboard", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.monitor.ap.connect(scoreboard.analysis_export);
        endfunction

    endclass

    // -- tests ----------------------------------------------------------------
    // Each derived test overrides create_seq(); returning the derived handle as
    // the base type is an implicit upcast (no $cast). The base test owns reset.
    class apb_base_test extends uvm_test;
        `uvm_component_utils(apb_base_test)

        apb_env        env;
        virtual apb_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = apb_env::type_id::create("env", this);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "no virtual interface set for apb_base_test")
        endfunction

        virtual function uvm_sequence #(apb_seq_item) create_seq();
            apb_write_read_seq seq = apb_write_read_seq::type_id::create("seq");
            return seq;
        endfunction

        task reset();
            vif.PRESETn <= 1'b0;
            vif.PSEL    <= 1'b0;
            vif.PENABLE <= 1'b0;
            vif.PWRITE  <= 1'b0;
            vif.PADDR   <= '0;
            vif.PWDATA  <= '0;
            repeat (3) @(posedge vif.PCLK);
            @(negedge vif.PCLK);
            vif.PRESETn <= 1'b1;
            @(posedge vif.PCLK);
        endtask

        task run_phase(uvm_phase phase);
            uvm_sequence #(apb_seq_item) seq;
            phase.raise_objection(this);
            reset();
            seq = create_seq();
            seq.start(env.agent.seqr);
            phase.drop_objection(this);
        endtask

    endclass

    class apb_write_read_test extends apb_base_test;
        `uvm_component_utils(apb_write_read_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual function uvm_sequence #(apb_seq_item) create_seq();
            apb_write_read_seq seq = apb_write_read_seq::type_id::create("seq");
            return seq;
        endfunction
    endclass

    class apb_random_test extends apb_base_test;
        `uvm_component_utils(apb_random_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual function uvm_sequence #(apb_seq_item) create_seq();
            apb_random_seq seq = apb_random_seq::type_id::create("seq");
            return seq;
        endfunction
    endclass

    class apb_walking_test extends apb_base_test;
        `uvm_component_utils(apb_walking_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual function uvm_sequence #(apb_seq_item) create_seq();
            apb_walking_seq seq = apb_walking_seq::type_id::create("seq");
            return seq;
        endfunction
    endclass

endpackage


// -----------------------------------------------------------------------------
// Simulation top: clock, DUT<->interface bind, config DB, run_test.
// -----------------------------------------------------------------------------
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

`ifdef DUMP
    initial begin
        $dumpfile("apb_tb_top.vcd");
        $dumpvars(0, apb_tb_top);
    end
`endif

endmodule


// -----------------------------------------------------------------------------
// APB3 assertion checker, bound to the DUT (identical to uvm/apb_sva.sv).
// Kept inline so this variant remains a single self-contained TB file.
// -----------------------------------------------------------------------------
module apb_sva #(
    parameter int ADDR_WIDTH = 15,
    parameter int DATA_WIDTH = 8
) (
    input logic                  PCLK,
    input logic                  PRESETn,
    input logic                  PSEL,
    input logic                  PENABLE,
    input logic                  PWRITE,
    input logic [ADDR_WIDTH-1:0] PADDR,
    input logic [DATA_WIDTH-1:0] PWDATA,
    input logic [DATA_WIDTH-1:0] PRDATA,
    input logic                  PREADY,
    input logic                  PSLVERR
);

    default clocking cb @(posedge PCLK); endclocking
    default disable iff (!PRESETn);

    // ---- APB3 protocol -------------------------------------------------------
    a_enable_needs_sel: assert property (PENABLE |-> PSEL)
        else $error("APB-SVA: PENABLE asserted without PSEL");

    a_setup_to_access: assert property ((PSEL && !PENABLE) |=> (PSEL && PENABLE))
        else $error("APB-SVA: SETUP not followed by ACCESS");

    a_enable_drops: assert property ((PSEL && PENABLE && PREADY) |=> !PENABLE)
        else $error("APB-SVA: PENABLE not deasserted after PREADY");

    a_setup_stable: assert property (
        (PSEL && !PENABLE) |=> ($stable(PADDR) && $stable(PWRITE)))
        else $error("APB-SVA: PADDR/PWRITE changed between SETUP and ACCESS");

    a_wdata_stable_setup: assert property (
        (PSEL && !PENABLE && PWRITE) |=> $stable(PWDATA))
        else $error("APB-SVA: PWDATA changed between SETUP and ACCESS");

    a_access_stable: assert property (
        (PSEL && PENABLE && !PREADY) |=>
            ($stable(PADDR) && $stable(PWRITE) &&
             $stable(PSEL)  && $stable(PENABLE)))
        else $error("APB-SVA: request changed while waiting for PREADY");

    a_access_wdata_stable: assert property (
        (PSEL && PENABLE && !PREADY && PWRITE) |=> $stable(PWDATA))
        else $error("APB-SVA: PWDATA changed while waiting for PREADY");

    // ---- this slave's tie-offs ----------------------------------------------
    a_pready_tied_high: assert property (PSEL |-> PREADY)
        else $error("APB-SVA: PREADY not high while selected (zero-wait slave)");

    a_pslverr_low: assert property (!PSLVERR)
        else $error("APB-SVA: PSLVERR asserted (slave never errors)");

    // ---- no unknowns on active signals --------------------------------------
    a_known_ctrl: assert property (
        PSEL |-> !$isunknown({PENABLE, PWRITE, PADDR}))
        else $error("APB-SVA: X/Z on control/address while selected");

    a_known_wdata: assert property (
        (PSEL && PWRITE) |-> !$isunknown(PWDATA))
        else $error("APB-SVA: X/Z on PWDATA during a write");

    a_known_rdata: assert property (
        (PSEL && PENABLE && !PWRITE && PREADY) |-> !$isunknown(PRDATA))
        else $error("APB-SVA: X/Z on PRDATA during a read");

    // ---- reset behaviour (evaluated even during reset) ----------------------
    a_reset_idle: assert property (
        disable iff (1'b0) ((!PRESETn) |-> (!PSEL && !PENABLE)))
        else $error("APB-SVA: bus not idle during reset");

    // ---- functional cover ---------------------------------------------------
    c_write: cover property (PSEL && PENABLE && PWRITE  && PREADY);
    c_read:  cover property (PSEL && PENABLE && !PWRITE && PREADY);

endmodule

bind apb_mem apb_sva #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) u_apb_sva (.*);
