// -----------------------------------------------------------------------------
// apb_mem_array : the switchable memory block — power domain PD_MEM.
//
// This is the storage array pulled out of apb_mem into its own instance so a
// power domain can be placed on it (see apb_mem.upf). The always-on APB
// interface lives one level up in apb_mem_lp (PD_AON).
//
// IEEE-1801 (UPF) note
// --------------------
// In a real low-power flow this module has ONLY its functional ports. The
// simulator reads apb_mem.upf and *automatically*:
//   * corrupts this domain's state to X when its supply switches off, and
//   * holds it across a power cycle where a retention strategy applies.
// None of the engines in this repo (Icarus, Verilator) are UPF-aware, so the
// `LP_EMULATE` block below hand-models that behavior with two extra ports
// (pwr_good, ret) purely so the demo is runnable here. Compile WITHOUT
// -DLP_EMULATE and hand apb_mem.upf to a UPF-aware tool for the real thing.
// -----------------------------------------------------------------------------
module apb_mem_array #(
    parameter int ADDR_WIDTH = 15,
    parameter int DATA_WIDTH = 8
) (
    input  logic                  PCLK,
    input  logic                  PRESETn,
    input  logic                  we,       // write-enable (ACCESS-phase write)
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic [DATA_WIDTH-1:0] rdata
`ifdef LP_EMULATE
    ,
    // Emulation-only controls — do NOT exist in a real UPF flow.
    input  logic                  pwr_good, // PD_MEM primary supply is on
    input  logic                  ret       // retention hold (save/restore)
`endif
);

    localparam int DEPTH = 1 << ADDR_WIDTH;
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Power up to a known all-zero state (mirrors the baseline apb_mem).
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = '0;
    end

    // Clocked write. Under emulation, a powered-down array cannot capture.
    always @(posedge PCLK) begin
        if (PRESETn && we
`ifdef LP_EMULATE
            && pwr_good
`endif
        )
            mem[addr] <= wdata;
    end

    // Combinational read of the raw array (selection/isolation handled above).
    always_comb rdata = mem[addr];

`ifdef LP_EMULATE
    // Emulate UPF power-down corruption: when the domain supply drops and the
    // array is not retained, its sequential state becomes unknown (X). A
    // retained power-down (ret=1) holds the contents — this is the retention
    // strategy in apb_mem.upf.
    always @(negedge pwr_good) begin
        if (!ret) begin
            for (int j = 0; j < DEPTH; j = j + 1)
                mem[j] <= 'x;
        end
    end
`endif

endmodule
