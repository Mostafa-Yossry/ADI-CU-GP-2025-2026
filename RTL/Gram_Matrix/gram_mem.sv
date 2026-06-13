//==============================================================================
// gram_mem.sv   (PARALLEL version)
//------------------------------------------------------------------------------
// Stores the 36 lower-triangle elements of G, with N_LANES write ports so a
// whole round of lanes can store on the same cycle.
//
// The N lanes of a round always target DISTINCT addresses (the round's N
// distinct triangle indices), so there is never a write conflict and no
// arbitration is needed.
//
// Read: single combinational port (Cholesky walks the lower triangle in order).
//==============================================================================
module gram_mem #(
    parameter int N_LANES   = 8,
    parameter int G_W       = 16,
    parameter int NUM_ELEMS = 36,
    parameter int ADDR_W    = 6
)(
    input  logic                     clk,

    // ---- N write ports (one per lane, from controller + mac_array) ----
    input  logic                     wr_en   [N_LANES],
    input  logic [ADDR_W-1:0]        wr_addr [N_LANES],
    input  logic signed [G_W-1:0]    g_real  [N_LANES],
    input  logic signed [G_W-1:0]    g_imag  [N_LANES],

    // ---- single combinational read port ----
    input  logic [ADDR_W-1:0]        rd_addr,
    output logic signed [G_W-1:0]    rd_real,
    output logic signed [G_W-1:0]    rd_imag
);

    logic signed [G_W-1:0] mem_real [0:NUM_ELEMS-1];
    logic signed [G_W-1:0] mem_imag [0:NUM_ELEMS-1];

    // Each lane writes its own address. Distinct addresses -> no conflict.
    always_ff @(posedge clk) begin
        for (int l = 0; l < N_LANES; l++) begin
            if (wr_en[l]) begin
                mem_real[wr_addr[l]] <= g_real[l];
                mem_imag[wr_addr[l]] <= g_imag[l];
            end
        end
    end

    assign rd_real = mem_real[rd_addr];
    assign rd_imag = mem_imag[rd_addr];

endmodule