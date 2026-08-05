// -----------------------------------------------------------------------------
// apb_mem_lp : low-power top for the APB memory — always-on domain PD_AON.
//
// Same APB3 slave behavior as rtl/apb_mem.sv, but the storage array is split
// into a switchable child instance (u_array, power domain PD_MEM) so the design
// can demonstrate a UPF power-management flow: a power switch, an isolation
// strategy, and a retention strategy. See apb_mem.upf for the golden intent.
//
// IEEE-1801 (UPF) note
// --------------------
// In a real flow the power-control signals (switch enable, isolation enable,
// retention save/restore) are supplied by a power controller and wired through
// UPF supply nets — NOT RTL ports, and the isolation clamp cells are inserted
// by the tool from apb_mem.upf. The `LP_EMULATE` ports and the clamp logic
// below exist only so this repo's non-UPF simulators can run the demo. Compile
// without -DLP_EMULATE for a clean functional model.
// -----------------------------------------------------------------------------
module apb_mem_lp #(
    parameter int ADDR_WIDTH = 15,
    parameter int DATA_WIDTH = 8
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
    output logic                  PSLVERR
`ifdef LP_EMULATE
    ,
    // Power-management controls for PD_MEM (emulation-only; see header note).
    input  logic                  pwr_on,   // PD_MEM power-switch enable
    input  logic                  iso_en,   // isolation clamp enable (active high)
    input  logic                  ret       // PD_MEM retention hold
`endif
);

    // Always-on APB decode: commit a write only in the ACCESS phase.
    logic                  we;
    logic [DATA_WIDTH-1:0] array_rdata;

    assign we = PRESETn && PSEL && PENABLE && PWRITE;

    // Switchable memory array (PD_MEM).
    apb_mem_array #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_array (
        .PCLK   (PCLK),
        .PRESETn(PRESETn),
        .we     (we),
        .addr   (PADDR),
        .wdata  (PWDATA),
        .rdata  (array_rdata)
`ifdef LP_EMULATE
        ,
        .pwr_good(pwr_on),
        .ret     (ret)
`endif
    );

    // Raw (pre-isolation) read value: 0 unless this is a read ACCESS.
    logic [DATA_WIDTH-1:0] rdata_raw;
    always_comb rdata_raw = (PSEL && !PWRITE) ? array_rdata : '0;

`ifdef LP_EMULATE
    // Isolation strategy (apb_mem.upf: set_isolation ... -clamp_value 0):
    // while PD_MEM is powered down its outputs are clamped to a known value so
    // its X's never leak into the always-on APB master. PREADY clamps low so a
    // master that tries to transact while the memory is off simply waits.
    assign PRDATA = iso_en ? '0   : rdata_raw;
    assign PREADY = iso_en ? 1'b0 : 1'b1;
`else
    assign PRDATA = rdata_raw;
    assign PREADY = 1'b1;
`endif

    assign PSLVERR = 1'b0;

endmodule
