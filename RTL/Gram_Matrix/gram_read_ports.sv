//==============================================================================
// gram_read_ports.sv
//------------------------------------------------------------------------------
// Bridges the full HH and H matrices to the MAC lanes' ADDRESS-based reads.
//
// The lanes ask for elements by linear address:
//        hh_addr = row*MAT_DIM + k   -> wants HH[row][k]
//        h_addr  = k  *MAT_DIM + col -> wants H[k][col]
//
// but `hermitian_pipe` exposes HH as a full 2D array (and H is a full 2D
// array too). This module flattens each matrix row-major and gives every lane
// its own combinational read port -- i.e. N_LANES*2 simultaneous reads.
//
// Pure combinational: it muxes already-registered data (HH from hermitian_pipe,
// H from the buffer in top), so the lanes see their operands the same cycle,
// exactly as `mac` assumes. This is where the 16-reads/cycle bandwidth lives,
// which is why HH and H must be held in flip-flops upstream.
//
// NOTE: HH 2D indexing matches mac's expectation -- hermitian_pipe stores
//       HH_mat[a][b] = (H^H)[a][b], so HH[row][k] = hh_*_mat[row][k].
//==============================================================================
module gram_read_ports #(
    parameter int N_LANES = 8,
    parameter int MAT_DIM = 8,
    parameter int DATA_W  = 12,
    parameter int MEM_AW  = 2*$clog2(MAT_DIM)            // 6 for an 8x8
)(
    // ---- full matrices (registered upstream) ----
    input  logic signed [DATA_W-1:0] hh_real_mat [0:MAT_DIM-1][0:MAT_DIM-1],
    input  logic signed [DATA_W-1:0] hh_imag_mat [0:MAT_DIM-1][0:MAT_DIM-1],
    input  logic signed [DATA_W-1:0] h_real_mat  [0:MAT_DIM-1][0:MAT_DIM-1],
    input  logic signed [DATA_W-1:0] h_imag_mat  [0:MAT_DIM-1][0:MAT_DIM-1],

    // ---- per-lane addresses from the MAC lanes ----
    input  logic [MEM_AW-1:0]        hh_addr [N_LANES],
    input  logic [MEM_AW-1:0]        h_addr  [N_LANES],

    // ---- per-lane operands back to the lanes ----
    output logic signed [DATA_W-1:0] hh_real [N_LANES],
    output logic signed [DATA_W-1:0] hh_imag [N_LANES],
    output logic signed [DATA_W-1:0] h_real  [N_LANES],
    output logic signed [DATA_W-1:0] h_imag  [N_LANES]
);

    localparam int NUM = MAT_DIM*MAT_DIM;                // 64 elements

    // Flatten row-major: flat[i*MAT_DIM + j] = mat[i][j].
    logic signed [DATA_W-1:0] hh_real_flat [0:NUM-1];
    logic signed [DATA_W-1:0] hh_imag_flat [0:NUM-1];
    logic signed [DATA_W-1:0] h_real_flat  [0:NUM-1];
    logic signed [DATA_W-1:0] h_imag_flat  [0:NUM-1];

    genvar i, j;
    generate
        for (i = 0; i < MAT_DIM; i++) begin : g_row
            for (j = 0; j < MAT_DIM; j++) begin : g_col
                assign hh_real_flat[i*MAT_DIM + j] = hh_real_mat[i][j];
                assign hh_imag_flat[i*MAT_DIM + j] = hh_imag_mat[i][j];
                assign h_real_flat [i*MAT_DIM + j] = h_real_mat [i][j];
                assign h_imag_flat [i*MAT_DIM + j] = h_imag_mat [i][j];
            end
        end
    endgenerate

    // Each lane picks its element by address -- one 64:1 mux per read port.
    genvar l;
    generate
        for (l = 0; l < N_LANES; l++) begin : g_lane
            assign hh_real[l] = hh_real_flat[hh_addr[l]];
            assign hh_imag[l] = hh_imag_flat[hh_addr[l]];
            assign h_real [l] = h_real_flat [h_addr[l]];
            assign h_imag [l] = h_imag_flat [h_addr[l]];
        end
    endgenerate

endmodule