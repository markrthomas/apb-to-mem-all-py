// -----------------------------------------------------------------------------
// apb_scoreboard : keeps a reference byte memory and checks every read against
// the last write to that address — the SV analogue of tb/apb_components.py
// ApbScoreboard. Writes update the model; reads are checked (default 0 for a
// never-written location, matching the zero-initialised RTL array).
// -----------------------------------------------------------------------------
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
            bit [7:0] expected = model.exists(tr.addr) ? model[tr.addr] : 8'h00;
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
