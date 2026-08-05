// -----------------------------------------------------------------------------
// apb_sva : SystemVerilog assertion checker for the APB3 slave protocol.
//
// A standalone module bound to every apb_mem instance (see the `bind` at the
// bottom), so it needs no changes to the DUT or the testbench and is reusable.
// It captures both the generic APB3 protocol rules and this slave's specific
// tie-offs (zero-wait PREADY, never-error PSLVERR). Failures fire $error;
// cover properties record that the key transactions were exercised.
//
// Compile it alongside the UVM testbench (the multi-file set lists it in
// SOURCES; the single-file variant inlines an identical module). It is NOT
// added to the Icarus/cocotb flow, whose simulator has weak SVA support.
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

    // All protocol checks are synchronous to PCLK and inactive during reset.
    default clocking cb @(posedge PCLK); endclocking
    default disable iff (!PRESETn);

    // ---- APB3 protocol -------------------------------------------------------

    // PENABLE may only be high when the slave is selected.
    a_enable_needs_sel: assert property (PENABLE |-> PSEL)
        else $error("APB-SVA: PENABLE asserted without PSEL");

    // A SETUP phase (PSEL & !PENABLE) must advance to ACCESS (PSEL & PENABLE)
    // on the next cycle — a started transfer cannot be aborted.
    a_setup_to_access: assert property ((PSEL && !PENABLE) |=> (PSEL && PENABLE))
        else $error("APB-SVA: SETUP not followed by ACCESS");

    // Once a transfer completes (ACCESS with PREADY) PENABLE must deassert.
    a_enable_drops: assert property ((PSEL && PENABLE && PREADY) |=> !PENABLE)
        else $error("APB-SVA: PENABLE not deasserted after PREADY");

    // Address/direction stay stable from SETUP into the ACCESS cycle.
    a_setup_stable: assert property (
        (PSEL && !PENABLE) |=> ($stable(PADDR) && $stable(PWRITE)))
        else $error("APB-SVA: PADDR/PWRITE changed between SETUP and ACCESS");

    // Write data stays stable from SETUP into ACCESS.
    a_wdata_stable_setup: assert property (
        (PSEL && !PENABLE && PWRITE) |=> $stable(PWDATA))
        else $error("APB-SVA: PWDATA changed between SETUP and ACCESS");

    // While stalled in ACCESS (waiting for PREADY) the whole request holds.
    a_access_stable: assert property (
        (PSEL && PENABLE && !PREADY) |=>
            ($stable(PADDR) && $stable(PWRITE) &&
             $stable(PSEL)  && $stable(PENABLE)))
        else $error("APB-SVA: request changed while waiting for PREADY");

    a_access_wdata_stable: assert property (
        (PSEL && PENABLE && !PREADY && PWRITE) |=> $stable(PWDATA))
        else $error("APB-SVA: PWDATA changed while waiting for PREADY");

    // ---- this slave's tie-offs ----------------------------------------------

    // Zero-wait-state slave: PREADY is high whenever it is selected.
    a_pready_tied_high: assert property (PSEL |-> PREADY)
        else $error("APB-SVA: PREADY not high while selected (zero-wait slave)");

    // The slave never signals an error.
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

    // The master must hold the bus idle while PRESETn is asserted. The explicit
    // disable overrides the module default so this is checked during reset.
    a_reset_idle: assert property (
        disable iff (1'b0) ((!PRESETn) |-> (!PSEL && !PENABLE)))
        else $error("APB-SVA: bus not idle during reset");

    // ---- functional cover ---------------------------------------------------

    c_write: cover property (PSEL && PENABLE && PWRITE  && PREADY);
    c_read:  cover property (PSEL && PENABLE && !PWRITE && PREADY);

endmodule

// Attach the checker to every apb_mem instance, matching the DUT's parameters
// and connecting the identically-named ports (.*). One line here covers both
// testbench variants.
bind apb_mem apb_sva #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) u_apb_sva (.*);
