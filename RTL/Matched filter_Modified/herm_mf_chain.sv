// =============================================================================
// herm_mf_chain.sv
// -----------------------------------------------------------------------------
// Top-level wrapper that connects hermitian_pipe to matched_filter_pipe,
// realising the full  z = H^H · y  pipeline from raw H and y inputs.
//
// Block diagram
// -------------
//
//   h_real/imag ──► hermitian_pipe ──► (hh_real/imag) ──► matched_filter_pipe ──► z_real/imag
//   h_valid_in  ──►       │                 hh_load ──►           │
//                    valid_out ─────────────────────               │
//   y_real/imag ─────────────────────────────────────────────────►│
//   y_valid_in  ─────────────────────────────────────────────────►│
//                                                            valid_out ──► z_valid_out
//
// Timing contract
// ---------------
//   The hermitian_pipe (REGISTER_OUTPUT=1) has 1-cycle latency:
//     Cycle N posedge : hermitian_pipe registers H^H from h_real/imag; valid_out=1
//     Cycle N negedge : hh_load = hermitian valid_out = 1, seen by matched_filter_pipe
//     Cycle N+1 posedge: matched_filter_pipe latches H^H coefficients
//
//   matched_filter_pipe requires hh_load exactly 1 cycle before the y valid_in
//   that uses those coefficients.  Therefore:
//
//     h_valid_in must be asserted exactly 1 cycle before y_valid_in.
//
//   For a streaming back-to-back burst with a new H and y every cycle:
//     - Assert h_valid_in for frame N on cycle N
//     - Assert y_valid_in for frame N on cycle N+1
//     The chain produces z for frame N on cycle N + 1 + MF_LATENCY.
//
//   Total chain latency = 1 (hermitian) + MF_LATENCY (matched filter)
//                       = 1 + 1 + $clog2(COLS) cycles
//                       = 5 cycles for the default 8×8 configuration.
//
// Port naming
// -----------
//   H input:  ROWS_H × COLS_H  (hermitian_pipe ROWS/COLS parameters)
//   y input:  COLS_H elements  (dot-product length = columns of H)
//   z output: COLS_H elements  (rows of H^H = columns of H)
//
//   For the default square case ROWS_H == COLS_H == 8:
//     H^H is 8×8, y is length-8, z is length-8.
//
// Parameters
// ----------
//   ROWS_H        – rows of H    (= columns of H^H = output length of z)
//   COLS_H        – columns of H (= rows of H^H = dot-product length)
//                   MUST be a power of two (matched filter constraint)
//   WL_IN         – word length for H, H^H, and y  (Q format input)
//   INT_BITS_IN   – integer bits of input format
//   FRAC_BITS_IN  – fractional bits of input format
//   WL_INT        – matched filter internal widened word length
//   INT_BITS_INT  – integer bits of internal format
//   FRAC_BITS_INT – fractional bits of internal format
//   WL_OUT        – matched filter output word length
//   INT_BITS_OUT  – integer bits of output format
//   FRAC_BITS_OUT – fractional bits of output format
// =============================================================================

module herm_mf_chain #(
    parameter int ROWS_H         = 8,
    parameter int COLS_H         = 8,

    parameter int WL_IN          = 12,
    parameter int INT_BITS_IN    =  0,
    parameter int FRAC_BITS_IN   = 11,

    parameter int WL_INT         = 16,
    parameter int INT_BITS_INT   =  0,
    parameter int FRAC_BITS_INT  = 15,

    parameter int WL_OUT         = 16,
    parameter int INT_BITS_OUT   =  4,
    parameter int FRAC_BITS_OUT  = 11
)(
    input  logic clk,
    input  logic rst_n,
    input  logic en,                   // matched-filter pipeline enable

    // -------------------------------------------------------------------------
    // H matrix input  (feeds hermitian_pipe)
    //   Assert h_valid_in for one cycle to latch a new channel matrix.
    //   Must be asserted exactly 1 cycle before the corresponding y_valid_in.
    // -------------------------------------------------------------------------
    input  logic                      h_valid_in,
    input  logic signed [WL_IN-1:0]  h_real [0:ROWS_H-1][0:COLS_H-1],
    input  logic signed [WL_IN-1:0]  h_imag [0:ROWS_H-1][0:COLS_H-1],

    // -------------------------------------------------------------------------
    // y vector input  (feeds matched_filter_pipe directly)
    //   Assert y_valid_in each cycle a new received vector is presented.
    // -------------------------------------------------------------------------
    input  logic                      y_valid_in,
    input  logic signed [WL_IN-1:0]  y_real [0:COLS_H-1],
    input  logic signed [WL_IN-1:0]  y_imag [0:COLS_H-1],

    // -------------------------------------------------------------------------
    // z output  (valid_out asserts 1 + MF_LATENCY cycles after y_valid_in)
    // -------------------------------------------------------------------------
    output logic                      z_valid_out,
    output logic signed [WL_OUT-1:0] z_real [0:COLS_H-1],
    output logic signed [WL_OUT-1:0] z_imag [0:COLS_H-1]
);

// =============================================================================
// Internal wires between hermitian_pipe and matched_filter_pipe
// =============================================================================

    // hermitian_pipe output → matched_filter_pipe coefficient input
    // Shape: [0:COLS_H-1][0:ROWS_H-1]
    // For the square case (COLS_H == ROWS_H) this matches matched_filter_pipe's
    // [0:ROWS-1][0:COLS-1] port directly.
    logic signed [WL_IN-1:0] hh_real_w [0:COLS_H-1][0:ROWS_H-1];
    logic signed [WL_IN-1:0] hh_imag_w [0:COLS_H-1][0:ROWS_H-1];

    // hermitian valid_out drives matched_filter hh_load directly
    logic hh_load_w;


// =============================================================================
// hermitian_pipe instance
// =============================================================================

    hermitian_pipe #(
        .ROWS            (ROWS_H       ),
        .COLS            (COLS_H       ),
        .WL              (WL_IN        ),
        .INT_BITS        (INT_BITS_IN  ),
        .FRAC_BITS       (FRAC_BITS_IN ),
        .REGISTER_OUTPUT (1            )   // 1-cycle latency; fills hh_load timing gap
    ) u_hermitian (
        .clk      (clk        ),
        .rst_n    (rst_n      ),
        .valid_in (h_valid_in ),
        .h_real   (h_real     ),
        .h_imag   (h_imag     ),
        .valid_out(hh_load_w  ),
        .hh_real  (hh_real_w  ),
        .hh_imag  (hh_imag_w  )
    );


// =============================================================================
// matched_filter_pipe instance
// =============================================================================

    matched_filter_pipe #(
        .ROWS          (COLS_H        ),   // H^H has COLS_H rows  (= columns of H)
        .COLS          (ROWS_H        ),   // H^H has ROWS_H cols  (= rows of H)
                                           // MUST be power of two
        .WL_IN         (WL_IN        ),
        .INT_BITS_IN   (INT_BITS_IN  ),
        .FRAC_BITS_IN  (FRAC_BITS_IN ),
        .WL_INT        (WL_INT       ),
        .INT_BITS_INT  (INT_BITS_INT ),
        .FRAC_BITS_INT (FRAC_BITS_INT),
        .WL_OUT        (WL_OUT       ),
        .INT_BITS_OUT  (INT_BITS_OUT ),
        .FRAC_BITS_OUT (FRAC_BITS_OUT)
    ) u_matched_filter (
        .clk      (clk       ),
        .rst_n    (rst_n     ),
        .en       (en        ),
        .hh_load  (hh_load_w ),
        .hh_real  (hh_real_w ),
        .hh_imag  (hh_imag_w ),
        .valid_in (y_valid_in),
        .y_real   (y_real    ),
        .y_imag   (y_imag    ),
        .valid_out(z_valid_out),
        .yhat_real(z_real    ),
        .yhat_imag(z_imag    )
    );


// =============================================================================
// Simulation-only: chain latency display
// =============================================================================
`ifdef SIMULATION
    localparam int MF_LEVELS  = $clog2(ROWS_H);
    localparam int MF_LATENCY = 1 + MF_LEVELS;
    localparam int CHAIN_LAT  = 1 + MF_LATENCY;   // 1 hermitian + matched filter

    initial begin
        $display("[herm_mf_chain] ROWS_H=%0d COLS_H=%0d WL_IN=%0d WL_OUT=%0d",
                 ROWS_H, COLS_H, WL_IN, WL_OUT);
        $display("[herm_mf_chain] MF_LATENCY=%0d  CHAIN_LATENCY=%0d cycles",
                 MF_LATENCY, CHAIN_LAT);
        $display("[herm_mf_chain] Timing: h_valid_in[N] must precede y_valid_in[N] by 1 cycle");
    end
`endif

endmodule

// =============================================================================
// End of herm_mf_chain.sv
// =============================================================================