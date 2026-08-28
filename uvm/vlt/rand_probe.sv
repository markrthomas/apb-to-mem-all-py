// Diagnostic: isolate why item.randomize() fails on UVM objects under Verilator.
// Tests several variants in one run. (First comment word avoids "verilator".)
`timescale 1ns/1ps
module rand_probe;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // A) uvm_sequence_item + uvm_field automation (matches apb_seq_item exactly)
  class si_field extends uvm_sequence_item;
    rand bit [14:0] addr; rand bit [7:0] data; rand bit write;
    `uvm_object_utils_begin(si_field)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(write, UVM_ALL_ON)
    `uvm_object_utils_end
    function new(string n="si_field"); super.new(n); endfunction
  endclass

  // B) uvm_sequence_item, NO field automation
  class si_nofield extends uvm_sequence_item;
    rand bit [14:0] addr; rand bit [7:0] data; rand bit write;
    `uvm_object_utils(si_nofield)
    function new(string n="si_nofield"); super.new(n); endfunction
  endclass

  // C) plain uvm_object with field automation
  class obj_field extends uvm_object;
    rand bit [14:0] addr; rand bit [7:0] data; rand bit write;
    `uvm_object_utils_begin(obj_field)
      `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_object_utils_end
    function new(string n="obj_field"); super.new(n); endfunction
  endclass

  initial begin
    si_field   a = new();
    si_nofield b = new();
    obj_field  c = new();
    int r;
    r=0; repeat(10) if (a.randomize() with { write==1'b1; }) r++;
    $display("PROBE A si_field   with-constraint  ok=%0d/10", r);
    r=0; repeat(10) if (a.randomize()) r++;
    $display("PROBE A si_field   no-constraint    ok=%0d/10", r);
    r=0; repeat(10) if (b.randomize() with { write==1'b1; }) r++;
    $display("PROBE B si_nofield with-constraint  ok=%0d/10", r);
    r=0; repeat(10) if (c.randomize() with { write==1'b1; }) r++;
    $display("PROBE C obj_field  with-constraint  ok=%0d/10", r);
    r=0; repeat(10) if (std::randomize(a.addr, a.data, a.write) with { a.write==1'b1; }) r++;
    $display("PROBE D std::randomize(fields)      ok=%0d/10", r);
    $finish;
  end
endmodule
