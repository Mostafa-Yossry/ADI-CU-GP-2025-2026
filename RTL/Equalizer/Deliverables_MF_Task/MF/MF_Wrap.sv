// ============================================================
// Module      : matched_filter_pipe_wrap
// Description : Fully-parametric flat-bus wrapper around
//               matched_filter_pipe.
//
// Adapts the core's unpacked array ports to/from contiguous
// flat signed buses expected by the top-level interconnect:
//
//   y_re_flat  [N*WL_IN-1:0]   – y real,  element 0 in LSBs
//   y_im_flat  [N*WL_IN-1:0]   – y imag,  element 0 in LSBs
//   hh_re_flat [N*N*WL_IN-1:0] – H^H real, row-major, row 0 in LSBs
//   hh_im_flat [N*N*WL_IN-1:0] – H^H imag, row-major, row 0 in LSBs
//   x_re_flat  [N*WL_OUT-1:0]  – ŷ real,  element 0 in LSBs
//   x_im_flat  [N*WL_OUT-1:0]  – ŷ imag,  element 0 in LSBs
//
// Packing convention (LSB-first):
//   y    : flat[k*WL_IN  +: WL_IN]              = y[k]
//   hh   : flat[(r*N+c)*WL_IN +: WL_IN]         = hh[r][c]
//   x    : flat[k*WL_OUT +: WL_OUT]             = yhat[k]
//
// All parameters mirror matched_filter_pipe exactly so that a
// single parameter override at the wrapper level propagates
// everywhere.  N controls both ROWS and COLS (square system).
//
// ============================================================

module matched_filter_pipe_wrap #(

    // ---------------------------------------------------------------
    // System Dimension
    // ---------------------------------------------------------------
    parameter int  N                      = 8  ,  // Antennas / streams
                                                   // MF_ROWS = MF_COLS = N
                                                   // N MUST be a power of two

    // ---------------------------------------------------------------
    // Input Fixed-Point Format  (y and H^H)
    // Default: Q1.11  =>  12-bit signed, 0 int bits, 11 frac bits
    // ---------------------------------------------------------------
    parameter int  MF_WL_IN                  = 12 ,  // Total input word length
    parameter int  MF_INT_BITS_IN            = 0  ,  // Integer bits (excl. sign)
    parameter int  MF_FRAC_BITS_IN           = 11 ,  // Fractional bits

    // ---------------------------------------------------------------
    // Internal Widened Format  (before multiply)
    // Default: Q1.15  =>  16-bit signed, 0 int bits, 15 frac bits
    // ---------------------------------------------------------------
    parameter int  MF_INTERNAL_WL         = 16 ,  // Internal word length
    parameter int  MF_INTERNAL_INT_BITS     = 0  ,  // Internal integer bits
    parameter int  MF_INTERNAL_FRAC_BITS    = 15 ,  // Internal fractional bits

    // ---------------------------------------------------------------
    // Output Fixed-Point Format  (post-rounding, adder tree output)
    // Default: Q5.11  =>  16-bit signed, 4 int bits, 11 frac bits
    // ---------------------------------------------------------------
    parameter int  MF_WL_OUT                 = 16 ,  // Output word length
    parameter int  MF_INT_BITS_OUT           = 4  ,  // Output integer bits
    parameter int  MF_FRAC_BITS_OUT          = 11    // Output fractional bits

)(

    // ---------------------------------------------------------------
    // Clock, Reset, Enable
    // ---------------------------------------------------------------
    input  wire                              clk        ,  // System clock
    input  wire                              rst_n      ,  // Active-low async reset
    input  wire                              en         ,  // Pipeline enable

    // ---------------------------------------------------------------
    // H^H Coefficient Load  –  FLAT bus
    // Assert hh_load for exactly one rising edge; buses must be
    // stable on that posedge.
    // Packing: flat[(r*N + c)*WL_IN +: WL_IN] = hh[r][c]
    // ---------------------------------------------------------------
    input  wire                              hh_load    ,  // Latch strobe
    input  wire signed [N*N*MF_WL_IN-1:0]      hh_re_flat ,  // Real coefficients
    input  wire signed [N*N*MF_WL_IN-1:0]      hh_im_flat ,  // Imag coefficients

    // ---------------------------------------------------------------
    // Streaming y Vector Input  –  FLAT bus
    // Packing: flat[k*WL_IN +: WL_IN] = y[k]
    // ---------------------------------------------------------------
    input  wire                              y_valid    ,  // Input vector valid
    input  wire signed [N*MF_WL_IN-1:0]        y_re_flat  ,  // Real part of y
    input  wire signed [N*MF_WL_IN-1:0]        y_im_flat  ,  // Imag part of y

    // ---------------------------------------------------------------
    // Filtered Output  –  FLAT bus
    // valid_out asserts LATENCY = 1 + $clog2(N) cycles after y_valid.
    // gy_enable is a sticky "pipeline primed" flag (see core docs).
    // Packing: flat[k*WL_OUT +: WL_OUT] = yhat[k]
    // ---------------------------------------------------------------
    output wire                              valid_out  ,  // Output valid
    output wire                              gy_enable  ,  // Pipeline primed flag
    output wire signed [N*MF_WL_OUT-1:0]       x_re_flat  ,  // Real part of ŷ
    output wire signed [N*MF_WL_OUT-1:0]       x_im_flat     // Imag part of ŷ

);

// ================================================================
// Elaboration-time sanity checks
// ================================================================
generate
    // WL_IN  format consistency
    if (MF_WL_IN  != 1 + MF_INT_BITS_IN  + MF_FRAC_BITS_IN)
        $fatal(1, "matched_filter_pipe_wrap: MF_WL_IN != 1 + MF_INT_BITS_IN + MF_FRAC_BITS_IN");

    // WL_INT format consistency
    if (MF_INTERNAL_WL != 1 + MF_INTERNAL_INT_BITS + MF_INTERNAL_FRAC_BITS)
        $fatal(1, "matched_filter_pipe_wrap: MF_INTERNAL_WL != 1 + MF_INTERNAL_INT_BITS + MF_INTERNAL_FRAC_BITS ");

    // WL_OUT format consistency
    if (MF_WL_OUT != 1 + MF_INT_BITS_OUT + MF_FRAC_BITS_OUT)
        $fatal(1, "matched_filter_pipe_wrap: MF_WL_OUT != 1 + MF_INT_BITS_OUT + MF_FRAC_BITS_OUT");

    // Internal format must be at least as wide as input
    if (MF_INTERNAL_WL < MF_WL_IN)
        $fatal(1, "matched_filter_pipe_wrap: MF_INTERNAL_WL must be >= MF_WL_IN");

    if (MF_INTERNAL_INT_BITS < MF_INT_BITS_IN)
        $fatal(1, "matched_filter_pipe_wrap: MF_INTERNAL_INT_BITS must be >= MF_INT_BITS_IN");

    if (MF_INTERNAL_FRAC_BITS < MF_FRAC_BITS_IN)
        $fatal(1, "matched_filter_pipe_wrap: MF_INTERNAL_FRAC_BITS must be >= MF_FRAC_BITS_IN");

    // N must be a power of two (same constraint as MF_COLS in core)
    if ((N & (N - 1)) != 0)
        $fatal(1, "matched_filter_pipe_wrap: N must be a power of two");
endgenerate

// ================================================================
// Unpack flat → unpacked arrays
// ================================================================

// --- H^H coefficients -------------------------------------------
// Packing: flat[(r*N + c)*MF_WL_IN +: MF_WL_IN] = hh[r][c]
logic signed [MF_WL_IN-1:0]  hh_real_arr [0:N-1][0:N-1];
logic signed [MF_WL_IN-1:0]  hh_imag_arr [0:N-1][0:N-1];

generate
    for (genvar gr = 0; gr < N; gr++) begin : g_unpack_hh_row
        for (genvar gc = 0; gc < N; gc++) begin : g_unpack_hh_col
            assign hh_real_arr[gr][gc] =
                signed'(hh_re_flat[(gr*N + gc)*MF_WL_IN +: MF_WL_IN]);
            assign hh_imag_arr[gr][gc] =
                signed'(hh_im_flat[(gr*N + gc)*MF_WL_IN +: MF_WL_IN]);
        end
    end
endgenerate

// --- y input vector ---------------------------------------------
// Packing: flat[k*MF_WL_IN +: MF_WL_IN] = y[k]
logic signed [MF_WL_IN-1:0]  y_real_arr [0:N-1];
logic signed [MF_WL_IN-1:0]  y_imag_arr [0:N-1];

generate
    for (genvar gk = 0; gk < N; gk++) begin : g_unpack_y
        assign y_real_arr[gk] = signed'(y_re_flat[gk*MF_WL_IN +: MF_WL_IN]);
        assign y_imag_arr[gk] = signed'(y_im_flat[gk*MF_WL_IN +: MF_WL_IN]);
    end
endgenerate

// ================================================================
// Output array wires from core
// ================================================================
wire signed [MF_WL_OUT-1:0]  yhat_real_arr [0:N-1];
wire signed [MF_WL_OUT-1:0]  yhat_imag_arr [0:N-1];

// ================================================================
// matched_filter_pipe core instantiation
// ================================================================
matched_filter_pipe #(
    .MF_ROWS               ( N            ),
    .MF_COLS               ( N            ),
    .MF_WL_IN              ( MF_WL_IN        ),
    .MF_INT_BITS_IN        ( MF_INT_BITS_IN  ),
    .MF_FRAC_BITS_IN       ( MF_FRAC_BITS_IN ),
    .MF_INTERNAL_WL        ( MF_INTERNAL_WL       ),
    .MF_INTERNAL_INT_BITS  ( MF_INTERNAL_INT_BITS ),
    .MF_INTERNAL_FRAC_BITS ( MF_INTERNAL_FRAC_BITS),
    .MF_WL_OUT             ( MF_WL_OUT       ),
    .MF_INT_BITS_OUT       ( MF_INT_BITS_OUT ),
    .MF_FRAC_BITS_OUT      ( MF_FRAC_BITS_OUT)
) u_mf (
    .clk        ( clk          ),
    .rst_n      ( rst_n        ),
    .en         ( en           ),
    .hh_load    ( hh_load      ),
    .hh_real    ( hh_real_arr  ),
    .hh_imag    ( hh_imag_arr  ),
    .valid_in   ( y_valid      ),   // name mapping: y_valid → valid_in
    .y_real     ( y_real_arr   ),
    .y_imag     ( y_imag_arr   ),
    .valid_out  ( valid_out    ),
    .gy_enable  ( gy_enable    ),
    .yhat_real  ( yhat_real_arr),
    .yhat_imag  ( yhat_imag_arr)
);

// ================================================================
// Pack unpacked arrays → flat output buses
// Packing: flat[k*MF_WL_OUT +: MF_WL_OUT] = yhat[k]
// ================================================================
generate
    for (genvar gk = 0; gk < N; gk++) begin : g_pack_x
        assign x_re_flat[gk*MF_WL_OUT +: MF_WL_OUT] = yhat_real_arr[gk];
        assign x_im_flat[gk*MF_WL_OUT +: MF_WL_OUT] = yhat_imag_arr[gk];
    end
endgenerate

endmodule
// ============================================================
// matched_filter_pipe_wrap.sv
// ------------------------------------------------------------
//
// Parameter summary
// -----------------
//   N             – system dimension (ROWS = COLS = N, power of 2)
//   WL_IN         – input word length (bits)              default 12
//   INT_BITS_IN   – input integer bits (excl. sign)       default  0
//   FRAC_BITS_IN  – input fractional bits                 default 11
//   WL_INT        – internal word length after widening   default 16
//   INT_BITS_INT  – internal integer bits                 default  0
//   FRAC_BITS_INT – internal fractional bits              default 15
//   WL_OUT        – output word length                    default 16
//   INT_BITS_OUT  – output integer bits                   default  4
//   FRAC_BITS_OUT – output fractional bits                default 11
//
// Bus widths inferred from parameters
// ------------------------------------
//   hh_re_flat / hh_im_flat :  N * N * WL_IN  bits
//   y_re_flat  / y_im_flat  :  N     * WL_IN  bits
//   x_re_flat  / x_im_flat  :  N     * WL_OUT bits
//
// Note: WL_OUT >= WL_IN in all default configurations.  If the
// consuming logic expects x_*_flat at N*WL_IN width (i.e. WL_OUT
// equals WL_IN), set WL_OUT = WL_IN and adjust INT/FRAC_BITS_OUT
// accordingly — the core's convergent rounding will truncate to
// fit.  No RTL changes to this wrapper are required.
//
// Pipeline latency (inherited from core)
// ---------------------------------------
//   LATENCY = 1 + $clog2(N) cycles
//   Default (N=8): LATENCY = 4 cycles
//   Access from testbench: u_wrap.u_mf.LATENCY
//
// ============================================================