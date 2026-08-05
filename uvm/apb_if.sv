// -----------------------------------------------------------------------------
// apb_if : APB3 signal bundle shared by the UVM driver, monitor and DUT.
//
// The clock (PCLK) is generated in the top module and passed in; every other
// signal lives here so the class-based components only ever touch a virtual
// interface handle (the SV analogue of the pyuvm BFM/cocotb.top boundary).
// -----------------------------------------------------------------------------
interface apb_if #(
    parameter int ADDR_WIDTH = 15,
    parameter int DATA_WIDTH = 8
) (
    input logic PCLK
);
    logic                  PRESETn;
    // request channel
    logic                  PSEL;
    logic                  PENABLE;
    logic                  PWRITE;
    logic [ADDR_WIDTH-1:0] PADDR;
    logic [DATA_WIDTH-1:0] PWDATA;
    // response channel
    logic [DATA_WIDTH-1:0] PRDATA;
    logic                  PREADY;
    logic                  PSLVERR;
endinterface
