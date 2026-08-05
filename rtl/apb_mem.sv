// -----------------------------------------------------------------------------
// apb_mem : APB3 slave wrapping a byte-wide memory (32K x 8-bit).
//
//  * Address space : 2**ADDR_WIDTH bytes  (default 32768 = 32K)
//  * Data width    : DATA_WIDTH bits      (default 8 = byte-wide)
//  * Wait states   : none  (PREADY tied high -> single-cycle ACCESS phase)
//  * Error resp    : none  (PSLVERR tied low)
//
// APB transfer phases:
//   IDLE   : PSEL=0
//   SETUP  : PSEL=1, PENABLE=0            (1 cycle)
//   ACCESS : PSEL=1, PENABLE=1, PREADY=1  (transfer completes here)
// -----------------------------------------------------------------------------
module apb_mem #(
    parameter int ADDR_WIDTH = 15,          // 2**15 = 32768 byte locations
    parameter int DATA_WIDTH = 8            // byte-wide data
) (
    input  logic                  PCLK,
    input  logic                  PRESETn,
    // APB request channel
    input  logic                  PSEL,
    input  logic                  PENABLE,
    input  logic                  PWRITE,
    input  logic [ADDR_WIDTH-1:0] PADDR,
    input  logic [DATA_WIDTH-1:0] PWDATA,
    // APB response channel
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PREADY,
    // verilator coverage_off
    // PSLVERR is a constant tie-off (this slave never errors) -> no logic to
    // cover; waive its point so `make coverage` can hold a 100% floor.
    output logic                  PSLVERR
    // verilator coverage_on
);

    localparam int DEPTH = 1 << ADDR_WIDTH; // 32768

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Power up to a known (all-zero) state so reads of un-written locations
    // return 0 rather than X.
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = '0;
    end

    // Zero-wait-state slave that never errors.
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // Write commits in the ACCESS phase (PSEL & PENABLE & PWRITE & PREADY).
    // Plain `always @(posedge)` (not `always_ff`): the memory is preloaded to
    // zero in the initial block above, and SystemVerilog forbids an `always_ff`
    // variable from having any second driver (VCS flags this as ICPD; Icarus
    // and Verilator are lenient). A clocked `always` is the portable idiom for a
    // sim memory model with an initial preload.
    always @(posedge PCLK) begin
        if (PRESETn && PSEL && PENABLE && PWRITE && PREADY)
            mem[PADDR] <= PWDATA;
    end

    // Combinational read: PRDATA is valid throughout the ACCESS phase and is
    // sampled by the master on the completing PCLK edge.
    always_comb begin
        if (PSEL && !PWRITE)
            PRDATA = mem[PADDR];
        else
            PRDATA = '0;
    end

endmodule
