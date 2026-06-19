// ============================================================
// Module      : matched_filter_pipe_wrap
// Description : Fully-parametric flat-bus wrapper around
//               matched_filter_pipe.
//
// Adapts the core's unpacked array ports to/from contiguous
// flat signed buses expected by the top-level interconnect.
//
// Dimensional model (rectangular H):
//
//   H      : H_ROWS × H_COLS
//   H^H    : H_COLS × H_ROWS    (shape consumed by the core)
//
// Within the core:
//   HH_ROWS = H_COLS   (rows of H^H = output vector length)
//   HH_COLS = H_ROWS   (columns of H^H = dot-product length K)
//
// Flat bus widths:
//   hh_re_flat / hh_im_flat : HH_ROWS * HH_COLS * WL_IN  bits
//   y_re_flat  / y_im_flat  : HH_COLS            * WL_IN  bits
//   x_re_flat  / x_im_flat  : HH_ROWS            * WL_OUT bits
//
// Packing conventions (LSB-first, row-major for 2-D):
//   H^H : flat[(r*HH_COLS + c)*WL_IN +: WL_IN]  = hh[r][c]
//   y   : flat[k*WL_IN  +: WL_IN]               = y[k]
//   g   : flat[k*WL_OUT +: WL_OUT]              = g[k]
//
// For the default square 8×8 system set HH_ROWS=HH_COLS=8.
// Both parameters must independently be power-of-two? No —
// only HH_COLS must be a power of two (adder-tree constraint).
//
// All arithmetic parameters mirror matched_filter_pipe exactly.
// ============================================================

module ref_matched_filter_pipe_wrap #(

    // ---------------------------------------------------------------
    // H^H Matrix Dimensions
    // ---------------------------------------------------------------
    parameter int  HH_ROWS                = 8  ,  // Rows of H^H    = COLS of H
                                                   // = length of output vector g
    parameter int  HH_COLS                = 8  ,  // Columns of H^H = ROWS of H
                                                   // = dot-product length K
                                                   // HH_COLS MUST be a power of two

    // ---------------------------------------------------------------
    // Input Fixed-Point Format  (y and H^H)
    // Default: Q1.11  =>  12-bit signed, 0 int bits, 11 frac bits
    // ---------------------------------------------------------------
    parameter int  MF_WL_IN               = 12 ,  // Total input word length
    parameter int  MF_INT_BITS_IN         = 0  ,  // Integer bits (excl. sign)
    parameter int  MF_FRAC_BITS_IN        = 11 ,  // Fractional bits

    // ---------------------------------------------------------------
    // Internal Widened Format  (before multiply)
    // Default: Q1.15  =>  16-bit signed, 0 int bits, 15 frac bits
    // ---------------------------------------------------------------
    parameter int  MF_INTERNAL_WL         = 16 ,  // Internal word length
    parameter int  MF_INTERNAL_INT_BITS   = 0  ,  // Internal integer bits
    parameter int  MF_INTERNAL_FRAC_BITS  = 15 ,  // Internal fractional bits

    // ---------------------------------------------------------------
    // Output Fixed-Point Format  (post-rounding, adder tree output)
    // Default: Q5.11  =>  16-bit signed, 4 int bits, 11 frac bits
    // ---------------------------------------------------------------
    parameter int  MF_WL_OUT              = 16 ,  // Output word length
    parameter int  MF_INT_BITS_OUT        = 4  ,  // Output integer bits
    parameter int  MF_FRAC_BITS_OUT       = 11    // Output fractional bits

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
    // Packing: flat[(r*HH_COLS + c)*WL_IN +: WL_IN] = hh[r][c]
    //   r in [0, HH_ROWS-1],  c in [0, HH_COLS-1]
    // ---------------------------------------------------------------
    input  wire                                           hh_load    ,  // Latch strobe
    input  wire signed [HH_ROWS*HH_COLS*MF_WL_IN-1:0]   hh_re_flat ,  // Real part of H^H
    input  wire signed [HH_ROWS*HH_COLS*MF_WL_IN-1:0]   hh_im_flat ,  // Imag part of H^H

    // ---------------------------------------------------------------
    // Streaming y Vector Input  –  FLAT bus
    // y has HH_COLS elements (columns of H^H = rows of H)
    // Packing: flat[k*WL_IN +: WL_IN] = y[k],  k in [0, HH_COLS-1]
    // ---------------------------------------------------------------
    input  wire                              y_valid    ,  // Input vector valid
    input  wire signed [HH_COLS*MF_WL_IN-1:0]  y_re_flat  ,  // Real part of y
    input  wire signed [HH_COLS*MF_WL_IN-1:0]  y_im_flat  ,  // Imag part of y

    // ---------------------------------------------------------------
    // Filtered Output  –  FLAT bus
    // g has HH_ROWS elements (rows of H^H = columns of H)
    // valid_out asserts LATENCY = 1 + $clog2(HH_COLS) cycles after y_valid.
    // gy_enable is a sticky "pipeline primed" flag (see core docs).
    // Packing: flat[k*WL_OUT +: WL_OUT] = g[k],  k in [0, HH_ROWS-1]
    // ---------------------------------------------------------------
    output wire                              valid_out  ,  // Output valid
    output wire                              gy_enable  ,  // Pipeline primed flag
    output wire signed [HH_ROWS*MF_WL_OUT-1:0] x_re_flat  ,  // Real part of g
    output wire signed [HH_ROWS*MF_WL_OUT-1:0] x_im_flat     // Imag part of g

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

    // HH_COLS must be a power of two (adder-tree constraint from core)
    if ((HH_COLS & (HH_COLS - 1)) != 0)
        $fatal(1, "matched_filter_pipe_wrap: HH_COLS must be a power of two");
endgenerate

// ================================================================
// Unpack flat → unpacked arrays
// ================================================================

// --- H^H coefficients -------------------------------------------
// Shape: [HH_ROWS][HH_COLS]
// Packing: flat[(r*HH_COLS + c)*MF_WL_IN +: MF_WL_IN] = hh[r][c]
logic signed [MF_WL_IN-1:0]  hh_real_arr [0:HH_ROWS-1][0:HH_COLS-1];
logic signed [MF_WL_IN-1:0]  hh_imag_arr [0:HH_ROWS-1][0:HH_COLS-1];

generate
    for (genvar gr = 0; gr < HH_ROWS; gr++) begin : g_unpack_hh_row
        for (genvar gc = 0; gc < HH_COLS; gc++) begin : g_unpack_hh_col
            assign hh_real_arr[gr][gc] =
                signed'(hh_re_flat[(gr*HH_COLS + gc)*MF_WL_IN +: MF_WL_IN]);
            assign hh_imag_arr[gr][gc] =
                signed'(hh_im_flat[(gr*HH_COLS + gc)*MF_WL_IN +: MF_WL_IN]);
        end
    end
endgenerate

// --- y input vector ---------------------------------------------
// y has HH_COLS elements
// Packing: flat[k*MF_WL_IN +: MF_WL_IN] = y[k]
logic signed [MF_WL_IN-1:0]  y_real_arr [0:HH_COLS-1];
logic signed [MF_WL_IN-1:0]  y_imag_arr [0:HH_COLS-1];

generate
    for (genvar gk = 0; gk < HH_COLS; gk++) begin : g_unpack_y
        assign y_real_arr[gk] = signed'(y_re_flat[gk*MF_WL_IN +: MF_WL_IN]);
        assign y_imag_arr[gk] = signed'(y_im_flat[gk*MF_WL_IN +: MF_WL_IN]);
    end
endgenerate

// ================================================================
// Output array wires from core
// g has HH_ROWS elements
// ================================================================
wire signed [MF_WL_OUT-1:0]  yhat_real_arr [0:HH_ROWS-1];
wire signed [MF_WL_OUT-1:0]  yhat_imag_arr [0:HH_ROWS-1];

// ================================================================
// ref_matched_filter_pipe core instantiation
// ================================================================
ref_matched_filter_pipe #(
    .HH_ROWS               ( HH_ROWS              ),
    .HH_COLS               ( HH_COLS              ),
    .MF_WL_IN              ( MF_WL_IN             ),
    .MF_INT_BITS_IN        ( MF_INT_BITS_IN       ),
    .MF_FRAC_BITS_IN       ( MF_FRAC_BITS_IN      ),
    .MF_INTERNAL_WL        ( MF_INTERNAL_WL       ),
    .MF_INTERNAL_INT_BITS  ( MF_INTERNAL_INT_BITS ),
    .MF_INTERNAL_FRAC_BITS ( MF_INTERNAL_FRAC_BITS),
    .MF_WL_OUT             ( MF_WL_OUT            ),
    .MF_INT_BITS_OUT       ( MF_INT_BITS_OUT      ),
    .MF_FRAC_BITS_OUT      ( MF_FRAC_BITS_OUT     )
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
// g has HH_ROWS elements
// Packing: flat[k*MF_WL_OUT +: MF_WL_OUT] = g[k]
// ================================================================
generate
    for (genvar gk = 0; gk < HH_ROWS; gk++) begin : g_pack_x
        assign x_re_flat[gk*MF_WL_OUT +: MF_WL_OUT] = yhat_real_arr[gk];
        assign x_im_flat[gk*MF_WL_OUT +: MF_WL_OUT] = yhat_imag_arr[gk];
    end
endgenerate

endmodule
// ============================================================
// matched_filter_pipe_wrap.sv  —  Dimensionally-general version
// ------------------------------------------------------------
//
// Parameter summary
// -----------------
//   HH_ROWS       – rows    of H^H = COLS of H (output length)  default 8
//   HH_COLS       – columns of H^H = ROWS of H (dot-product K)  default 8
//                   MUST be a power of two
//   MF_WL_IN      – input word length (bits)                     default 12
//   MF_INT_BITS_IN   – input integer bits (excl. sign)           default  0
//   MF_FRAC_BITS_IN  – input fractional bits                     default 11
//   MF_INTERNAL_WL   – internal word length after widening       default 16
//   MF_INTERNAL_INT_BITS  – internal integer bits                default  0
//   MF_INTERNAL_FRAC_BITS – internal fractional bits             default 15
//   MF_WL_OUT     – output word length                           default 16
//   MF_INT_BITS_OUT  – output integer bits                       default  4
//   MF_FRAC_BITS_OUT – output fractional bits                    default 11
//
// Bus widths inferred from parameters
// ------------------------------------
//   hh_re_flat / hh_im_flat :  HH_ROWS * HH_COLS * WL_IN  bits
//   y_re_flat  / y_im_flat  :  HH_COLS            * WL_IN  bits
//   x_re_flat  / x_im_flat  :  HH_ROWS            * WL_OUT bits
//
// Default square 8×8 equivalence (HH_ROWS=8, HH_COLS=8):
//   Bus widths are identical to the original N=8 wrapper.
//   The testbench is fully backward-compatible when N=HH_ROWS=HH_COLS.
//
// Pipeline latency (inherited from core)
// ---------------------------------------
//   LATENCY = 1 + $clog2(HH_COLS) cycles
//   Default (HH_COLS=8): LATENCY = 4 cycles
//   Access from testbench: u_wrap.u_mf.LATENCY
//
// ============================================================