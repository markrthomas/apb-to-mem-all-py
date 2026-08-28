// Diagnostic round 2: pinpoint the inline-constraint randomize failure.
`timescale 1ns/1ps
module rand_probe;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // field named 'write' (collides with uvm_subscriber::write)
  class si_write extends uvm_sequence_item;
    rand bit [14:0] addr; rand bit write;
    `uvm_object_utils(si_write)
    function new(string n="si_write"); super.new(n); endfunction
  endclass
  // field renamed to 'dir' (no UVM collision)
  class si_dir extends uvm_sequence_item;
    rand bit [14:0] addr; rand bit dir;
    `uvm_object_utils(si_dir)
    function new(string n="si_dir"); super.new(n); endfunction
  endclass
  // class-level constraint instead of inline
  class si_cls extends uvm_sequence_item;
    rand bit [14:0] addr; rand bit write;
    constraint c_wr { write == 1'b1; }
    `uvm_object_utils(si_cls)
    function new(string n="si_cls"); super.new(n); endfunction
  endclass

  initial begin
    si_write a = new(); si_dir b = new(); si_cls d = new();
    int r;
    r=0; repeat(10) if (a.randomize() with { write == 1'b1; }) r++;
    $display("PROBE E write  inline{write==1}      ok=%0d/10", r);
    r=0; repeat(10) if (a.randomize() with { this.write == 1'b1; }) r++;
    $display("PROBE F write  inline{this.write==1} ok=%0d/10", r);
    r=0; repeat(10) if (b.randomize() with { dir == 1'b1; }) r++;
    $display("PROBE G dir    inline{dir==1}        ok=%0d/10", r);
    r=0; repeat(10) if (a.randomize() with { addr < 100; }) r++;
    $display("PROBE H write  inline{addr<100}      ok=%0d/10", r);
    r=0; repeat(10) if (d.randomize()) r++;
    $display("PROBE I cls    class-constraint      ok=%0d/10", r);
    $finish;
  end
endmodule
