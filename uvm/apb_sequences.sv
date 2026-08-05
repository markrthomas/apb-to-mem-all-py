// -----------------------------------------------------------------------------
// Stimulus sequences — one-for-one with tb/apb_seq.py.
//
//   apb_write_read_seq : write a value, then read it back (32 pairs)
//   apb_random_seq     : random mix; reads biased 4:1 to written addrs (64 items)
//   apb_walking_seq    : directed first/last address and all-0/all-1 payloads
// -----------------------------------------------------------------------------

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


// Random mix of reads and writes. Reads are biased 4:1 toward addresses that
// have already been written, so they mostly check stored data instead of
// reading never-written locations (which return 0); writes stay fully random to
// populate the address set. All randomization is constraint-based (no $urandom).
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
                    if (!item.randomize() with { write == 1'b0; addr == target; })
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
