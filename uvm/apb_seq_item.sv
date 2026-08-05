// -----------------------------------------------------------------------------
// apb_seq_item : one APB read or write transfer.
//
// Mirrors tb/apb_seq_item.py:
//   * addr  — 15-bit address (32K byte space)
//   * data  — 8-bit write payload (PWDATA)
//   * write — 1 = write, 0 = read
//   * rdata — captured read data (PRDATA), filled in by the driver on reads
//
// convert2string reports the *observable* transfer (direction, address, and
// the payload relevant to that direction). The `uvm_field_int macros provide
// copy / compare / print automatically.
// -----------------------------------------------------------------------------
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
