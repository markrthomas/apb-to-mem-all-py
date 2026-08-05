// -----------------------------------------------------------------------------
// apb_agent : sequencer + driver + monitor (active agent), matching
// tb/apb_components.py ApbAgent.
// -----------------------------------------------------------------------------
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
