// ============================================================
// Module      : matched_filter_pipe_wrap
// Description : Fully-parametric flat-bus wrapper around
//               matched_filter_unrolled.
//
// Adapts the core's unpacked array ports to/from contiguous
// flat signed buses expected by the top-level interconnect:
//
//   y_re_flat  [N*WL_IN-1:0]       – y real,  element 0 in LSBs
//   y_im_flat  [N*WL_IN-1:0]       – y imag,  element 0 in LSBs
//   hh_re_flat [N*N*WL_IN-1:0]     – H^H real, row-major, row 0 in LSBs
//   hh_im_flat [N*N*WL_IN-1:0]     – H^H imag, row-major, row 0 in LSBs
//   x_re_flat  [N*WL_OUT-1:0]      – Z real,  element 0 in LSBs
//   x_im_flat  [N*WL_OUT-1:0]      – Z imag,  element 0 in LSBs
//
// Packing convention (LSB-first):
//   y    : flat[k*WL_IN  +: WL_IN]              = y[k]
//   hh   : flat[(r*N+c)*WL_IN +: WL_IN]         = hh[r][c]
//   x    : flat[k*WL_OUT +: WL_OUT]             = z[k]
//
// All parameters mirror matched_filter_unrolled exactly so that a
// single parameter override at the wrapper level propagates
// everywhere.  N controls both ROWS and COLS (square system).
//
// ------------------------------------------------------------
// Parameter mapping to core (matched_filter_unrolled):
//
//   Wrapper param       Core param      Default  Notes
//   ----------------    -----------     -------  --------------------------
//   N                   MF_ROWS/COLS    8        Square; must equal 8
//   MF_WL_IN            MF_WL_IN        12       Input Q1.11
//   MF_FL_IN            MF_FL_IN        11       Input fraction bits
//   MF_WL_W             MF_WL_W         16       Widened Q1.15
//   MF_FL_W             MF_FL_W         15       Widened fraction bits
//   MF_WL_PROD          MF_WL_PROD      32       Product Q2.30
//   MF_FL_PROD          MF_FL_PROD      30       Product fraction bits
//   MF_FL_Q2            MF_FL_Q2        14       Acc stage Q2.14 (k=1)
//   MF_FL_Q3            MF_FL_Q3        13       Acc stage Q3.13 (k=2)
//   MF_FL_Q4            MF_FL_Q4        12       Acc stage Q4.12 (k=3,4)
//   MF_FL_Q5            MF_FL_Q5        11       Acc stage Q5.11 (k=5..8)
//   MF_WL_OUT           MF_WL_OUT       16       Output Q5.11
//   MF_FL_OUT           MF_FL_OUT       11       Output fraction bits
//
// Pipeline latency (inherited from core):
//   LATENCY = 10 cycles  (spatially unrolled, 8 MAC steps × 2 stages
//             with sequential accumulator chain + output register)
//   Throughput: 1 output vector/cycle (steady state)
//
// ============================================================

module matched_filter_pipe_wrap #(

    // ---------------------------------------------------------------
    // System dimension — must equal 8 (enforced by core)
    // ---------------------------------------------------------------
    parameter int  N            = 8  ,

    // ---------------------------------------------------------------
    // Input Fixed-Point Format  (H^H and Y at module boundary)
    // Default: Q1.11  =>  12-bit signed
    // ---------------------------------------------------------------
    parameter int  MF_WL_IN    = 12 ,
    parameter int  MF_FL_IN    = 11 ,

    // ---------------------------------------------------------------
    // Internal Widened Format  (after zero-pad, before multiply)
    // Default: Q1.15  =>  16-bit signed
    // ---------------------------------------------------------------
    parameter int  MF_WL_W     = 16 ,
    parameter int  MF_FL_W     = 15 ,

    // ---------------------------------------------------------------
    // Product Format  (full-precision 32-bit multiply result)
    // Default: Q2.30
    // ---------------------------------------------------------------
    parameter int  MF_WL_PROD  = 32 ,
    parameter int  MF_FL_PROD  = 30 ,

    // ---------------------------------------------------------------
    // Accumulator Stage Fraction Bits  (16-bit accumulators throughout)
    // ---------------------------------------------------------------
    parameter int  MF_FL_Q2    = 14 ,
    parameter int  MF_FL_Q3    = 13 ,
    parameter int  MF_FL_Q4    = 12 ,
    parameter int  MF_FL_Q5    = 11 ,

    // ---------------------------------------------------------------
    // Output Fixed-Point Format  (Z = H^H * Y result)
    // Default: Q5.11  =>  16-bit signed
    // ---------------------------------------------------------------
    parameter int  MF_WL_OUT   = 16 ,
    parameter int  MF_FL_OUT   = 11

)(
    // ---------------------------------------------------------------
    // Clock, Reset, Enable
    // ---------------------------------------------------------------
    input  wire                              clk        ,
    input  wire                              rst_n      ,
    input  wire                              en         ,

    // ---------------------------------------------------------------
    // H^H Coefficient Load  –  FLAT bus
    // Packing: flat[(r*N + c)*MF_WL_IN +: MF_WL_IN] = hh[r][c]
    // ---------------------------------------------------------------
    input  wire                              hh_load    ,
    input  wire signed [N*N*MF_WL_IN-1:0]   hh_re_flat ,
    input  wire signed [N*N*MF_WL_IN-1:0]   hh_im_flat ,

    // ---------------------------------------------------------------
    // Streaming Y Vector Input  –  FLAT bus
    // Packing: flat[k*MF_WL_IN +: MF_WL_IN] = y[k]
    // ---------------------------------------------------------------
    input  wire                              y_valid    ,
    input  wire signed [N*MF_WL_IN-1:0]     y_re_flat  ,
    input  wire signed [N*MF_WL_IN-1:0]     y_im_flat  ,

    // ---------------------------------------------------------------
    // Z Vector Output  –  FLAT bus
    // Packing: flat[k*MF_WL_OUT +: MF_WL_OUT] = z[k]
    // ---------------------------------------------------------------
    output wire                              valid_out  ,
    output wire signed [N*MF_WL_OUT-1:0]    x_re_flat  ,
    output wire signed [N*MF_WL_OUT-1:0]    x_im_flat

);

// ================================================================
// Elaboration-time sanity checks
// ================================================================
generate
    if (MF_WL_W < MF_WL_IN)
        $fatal(1, "matched_filter_pipe_wrap: MF_WL_W (%0d) must be >= MF_WL_IN (%0d)",
               MF_WL_W, MF_WL_IN);
    if (MF_FL_W < MF_FL_IN)
        $fatal(1, "matched_filter_pipe_wrap: MF_FL_W (%0d) must be >= MF_FL_IN (%0d)",
               MF_FL_W, MF_FL_IN);
    if (MF_FL_OUT != MF_FL_Q5)
        $fatal(1, "matched_filter_pipe_wrap: MF_FL_OUT (%0d) must equal MF_FL_Q5 (%0d)",
               MF_FL_OUT, MF_FL_Q5);
    if (N != 8)
        $fatal(1, "matched_filter_pipe_wrap: N must be 8 (core is fixed 8x8)");
endgenerate

// ================================================================
// Unpack flat → unpacked arrays
// ================================================================

// --- H^H coefficients -------------------------------------------
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

// --- Y input vector ---------------------------------------------
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
wire signed [MF_WL_OUT-1:0]  z_real_arr [0:N-1];
wire signed [MF_WL_OUT-1:0]  z_imag_arr [0:N-1];

// ================================================================
// matched_filter_unrolled core instantiation
// ================================================================
matched_filter_unrolled #(
    .MF_ROWS    ( N           ),
    .MF_COLS    ( N           ),
    .MF_WL_IN   ( MF_WL_IN   ),
    .MF_FL_IN   ( MF_FL_IN   ),
    .MF_WL_W    ( MF_WL_W    ),
    .MF_FL_W    ( MF_FL_W    ),
    .MF_WL_PROD ( MF_WL_PROD ),
    .MF_FL_PROD ( MF_FL_PROD ),
    .MF_FL_Q2   ( MF_FL_Q2   ),
    .MF_FL_Q3   ( MF_FL_Q3   ),
    .MF_FL_Q4   ( MF_FL_Q4   ),
    .MF_FL_Q5   ( MF_FL_Q5   ),
    .MF_WL_OUT  ( MF_WL_OUT  ),
    .MF_FL_OUT  ( MF_FL_OUT  )
) u_mf (
    .clk        ( clk         ),
    .rst_n      ( rst_n       ),
    .en         ( en          ),
    .hh_load    ( hh_load     ),
    .hh_real    ( hh_real_arr ),
    .hh_imag    ( hh_imag_arr ),
    .valid_in   ( y_valid     ),
    .y_real     ( y_real_arr  ),
    .y_imag     ( y_imag_arr  ),
    .valid_out  ( valid_out   ),
    .z_real     ( z_real_arr  ),
    .z_imag     ( z_imag_arr  )
);

// ================================================================
// Pack unpacked arrays → flat output buses
// Packing: flat[k*MF_WL_OUT +: MF_WL_OUT] = z[k]
// ================================================================
generate
    for (genvar gk = 0; gk < N; gk++) begin : g_pack_x
        assign x_re_flat[gk*MF_WL_OUT +: MF_WL_OUT] = z_real_arr[gk];
        assign x_im_flat[gk*MF_WL_OUT +: MF_WL_OUT] = z_imag_arr[gk];
    end
endgenerate

endmodule
// ============================================================
// matched_filter_pipe_wrap.sv — end of file
// ============================================================