//==============================================================================
// mac_array.sv
//------------------------------------------------------------------------------
// N_LANES parallel copies of the single-element `mac`. Each lane computes one
// lower-triangle element of G in the same ~9 cycles, so a "round" of up to
// N_LANES elements finishes together.
//
// With N_LANES = 8 and 36 elements:  ceil(36/8) = 5 rounds.
//   round 0 : elements  0.. 7   (8 lanes)
//   round 1 : elements  8..15   (8 lanes)
//   round 2 : elements 16..23   (8 lanes)
//   round 3 : elements 24..31   (8 lanes)
//   round 4 : elements 32..35   (4 lanes -> lanes 4..7 idle)
// 5 rounds x 9 cycles ~= 45 cycles.
//
// The controller hands each lane its own (row, col, is_diag) and a lane_valid
// flag. Idle lanes (lane_valid = 0) are simply not started and are treated as
// already done, so they never stall the round or write garbage.
//
// Every lane has its OWN read ports into the HH and H memories, so those
// memories must support N_LANES*2 simultaneous reads -> keep them in flip-flops.
//==============================================================================
module mac_array #(
    parameter int N_LANES = 8,
    parameter int DATA_W  = 12,
    parameter int MAT_DIM = 8,
    parameter int IDX_W   = 3,
    parameter int G_W     = 16,
    parameter int MEM_AW  = 2*IDX_W
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ---- control (broadcast start + per-lane work) ----
    input  logic                     mac_start,                 // start the round
    input  logic [IDX_W-1:0]         row        [N_LANES],      // each lane's row
    input  logic [IDX_W-1:0]         col        [N_LANES],      // each lane's col
    input  logic                     is_diag    [N_LANES],      // each lane: row==col ?
    input  logic                     lane_valid [N_LANES],      // 1 = lane has real work

    // ---- per-lane read ports to the HH and H memories ----
    output logic [MEM_AW-1:0]        hh_addr    [N_LANES],
    output logic [MEM_AW-1:0]        h_addr     [N_LANES],
    input  logic signed [DATA_W-1:0] hh_real    [N_LANES],
    input  logic signed [DATA_W-1:0] hh_imag    [N_LANES],
    input  logic signed [DATA_W-1:0] h_real     [N_LANES],
    input  logic signed [DATA_W-1:0] h_imag     [N_LANES],

    // ---- per-lane results ----
    output logic signed [G_W-1:0]    g_real     [N_LANES],
    output logic signed [G_W-1:0]    g_imag     [N_LANES],

    output logic                     mac_done                   // all valid lanes finished
);

    logic               lane_done [N_LANES];
    logic [N_LANES-1:0] done_ok;                                // per-lane "finished or idle"

    genvar l;
    generate
        for (l = 0; l < N_LANES; l++) begin : gen_lane
            mac #(
                .DATA_W (DATA_W),
                .MAT_DIM(MAT_DIM),
                .IDX_W  (IDX_W),
                .G_W    (G_W),
                .MEM_AW (MEM_AW)
            ) u_mac (
                .clk      (clk),
                .rst_n    (rst_n),
                .mac_start(mac_start & lane_valid[l]),           // only real lanes run
                .row      (row[l]),
                .col      (col[l]),
                .is_diag  (is_diag[l]),
                .hh_addr  (hh_addr[l]),
                .h_addr   (h_addr[l]),
                .hh_real  (hh_real[l]),
                .hh_imag  (hh_imag[l]),
                .h_real   (h_real[l]),
                .h_imag   (h_imag[l]),
                .g_real   (g_real[l]),
                .g_imag   (g_imag[l]),
                .mac_done (lane_done[l])
            );

            // A valid lane counts only when it asserts done; an idle lane is
            // considered done immediately so it cannot hold up the round.
            assign done_ok[l] = lane_done[l] | ~lane_valid[l];
        end
    endgenerate

    // All lanes share the same latency, so the valid lanes pulse done on the
    // same cycle -> this AND is a clean one-cycle "round complete" pulse.
    assign mac_done = &done_ok;

endmodule