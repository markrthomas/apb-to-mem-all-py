// -----------------------------------------------------------------------------
// apb_pkg : bundles the UVM environment (sequence item, sequences, components,
// tests) into a single package. Include order follows the dependency chain.
// The interface (apb_if) lives outside the package, as interfaces must.
// -----------------------------------------------------------------------------
package apb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "apb_seq_item.sv"
    `include "apb_sequences.sv"
    `include "apb_driver.sv"
    `include "apb_monitor.sv"
    `include "apb_agent.sv"
    `include "apb_scoreboard.sv"
    `include "apb_env.sv"
    `include "apb_test.sv"

endpackage
