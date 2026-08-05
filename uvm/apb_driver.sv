// -----------------------------------------------------------------------------
// apb_driver : serialises sequence items onto the APB bus, one transfer at a
// time, and writes captured PRDATA back into the read item.
//
// Timing mirrors the pyuvm BFM (tb/apb_bfm.py): request is driven on the
// falling edge so the DUT samples clean values on the rising edge; PRDATA is
// sampled once PREADY is seen high in the ACCESS phase.
// -----------------------------------------------------------------------------
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
