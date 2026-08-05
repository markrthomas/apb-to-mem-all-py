// -----------------------------------------------------------------------------
// apb_monitor : records every completed transfer (ACCESS phase with PREADY
// high) and broadcasts it on an analysis port — the SV analogue of the pyuvm
// monitor_bfm + uvm_analysis_port.
// -----------------------------------------------------------------------------
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
                `uvm_info("MON", $sformatf("observed %s", tr.convert2string()),
                          UVM_MEDIUM)
                ap.write(tr);
            end
        end
    endtask

endclass
