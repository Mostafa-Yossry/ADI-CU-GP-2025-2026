// ============================================================
// Module      : hermitian_mf_chain
// Description : Integration wrapper that chains
//
//                   hermitian_pipe  →  matched_filter_pipe_wrap
//
//               to compute:
//
//                   g_y = H^H · y
//
//               where  H^H = conj(H)^T  (Hermitian transpose).
//
// Both sub-blocks are treated as verified IP; this wrapper adds
// only glue logic (flat-bus packing, hh_load sequencing, and
// the coefficient-hold register).
//
// ============================================================
// Interface Compatibility Analysis
// ============================================================
//
// hermitian_pipe output ports (square N×N case, REGISTER_OUTPUT=1):
//
//   hh_real [0:COLS-1][0:ROWS-1]   – unpacked array,  Q1.11, 12-bit
//   hh_imag [0:COLS-1][0:ROWS-1]
//   valid_out                       – 1 cycle after valid_in
//
// matched_filter_pipe_wrap (MF_Wrap) coefficient input ports:
//
//   hh_re_flat [N*N*WL_IN-1:0]     – flat bus, packing:
//   hh_im_flat [N*N*WL_IN-1:0]       flat[(r*N+c)*WL_IN +: WL_IN] = hh[r][c]
//   hh_load                         – single-cycle strobe
//
// For the square N=8 case hermitian_pipe produces hh[c][r] in a
// [0:7][0:7] unpacked array (outer index = column of H^H = row of H).
// The MF_Wrap unpacks its flat bus as hh_arr[r][c] where r and c are
// the row and column of H^H.
//
// Because  H^H  is square (8×8) and is addressed uniformly as [r][c]
// by both blocks, the two index spaces are IDENTICAL after flattening.
// No element reordering is required — we just need to flatten the
// hermitian_pipe output array into the MF_Wrap flat bus using the
// same row-major convention:
//
//   flat[(r*N+c)*WL_IN +: WL_IN]  ←  hh_out[r][c]
//
// ============================================================
// Latency Analysis
// ============================================================
//
//  Cycle  Event
//  -----  ---------------------------------------------------
//    0    H presented at hermitian_pipe input; valid_in asserted
//    1    H^H appears at hermitian_pipe output; valid_out asserted
//         (REGISTER_OUTPUT=1 latency = 1 cycle)
//         → wrapper detects valid_out, latches H^H into hold registers,
//           asserts hh_load to MF_Wrap for one cycle
//    2    MF coef registers updated on this posedge (hh_load was high
//         during cycle 1→2 posedge).  y vectors may be streamed from
//         this cycle onward.
//    2    First y_valid presented.
//   12    First g_y valid_out from MF (MF pipeline latency = 10 cycles).
//
//  Total chain latency from H valid to g_y valid:
//    1 (hermitian) + 1 (coef load posedge) + 10 (MF) = 12 cycles
//
//  Note: hh_load is asserted for exactly ONE cycle coinciding with the
//  hermitian valid_out.  The coef hold registers ensure the flat buses
//  remain stable from that cycle onward, satisfying the MF requirement
//  that coefficients be held while valid_in is asserted (the MF reads
//  coefficients only at the multiply stage, one cycle per row-group, so
//  holding them for the full burst is the safe and correct approach).

module hermitian_mf_chain #(

    // -------------------------------------------------------
    // Dimension — must equal 8 (MF core is fixed 8×8)
    // -------------------------------------------------------
    parameter int  N          = 8,

    // -------------------------------------------------------
    // Fixed-point format (shared by Hermitian and MF input)
    // Default: Q1.11 → 12-bit signed
    // -------------------------------------------------------
    parameter int  WL_IN      = 12,
    parameter int  FL_IN      = 11,
    parameter int  INT_BITS   = 0,          // WL_IN = 1 + INT_BITS + FL_IN

    // -------------------------------------------------------
    // MF internal / output format parameters
    // (passed straight through to MF_Wrap)
    // -------------------------------------------------------
    parameter int  MF_WL_W    = 16,
    parameter int  MF_FL_W    = 15,
    parameter int  MF_WL_PROD = 32,
    parameter int  MF_FL_PROD = 30,
    parameter int  MF_FL_Q2   = 14,
    parameter int  MF_FL_Q3   = 13,
    parameter int  MF_FL_Q4   = 12,
    parameter int  MF_FL_Q5   = 11,
    parameter int  MF_WL_OUT  = 16,
    parameter int  MF_FL_OUT  = 11,

    // -------------------------------------------------------
    // hermitian_pipe output register mode
    // 1 = registered (1-cycle latency, recommended)
    // 0 = combinational (0-cycle latency)
    // -------------------------------------------------------
    parameter bit  HERM_REG   = 1

)(
    // -------------------------------------------------------
    // Clock / Reset
    // -------------------------------------------------------
    input  logic                              clk,
    input  logic                              rst_n,

    // -------------------------------------------------------
    // MF pipeline enable (does not affect Hermitian or coef load)
    // -------------------------------------------------------
    input  logic                              en,

    // -------------------------------------------------------
    // H matrix input
    // -------------------------------------------------------
    input  logic                              h_valid,
    input  logic signed [WL_IN-1:0]           h_real [0:N-1][0:N-1],
    input  logic signed [WL_IN-1:0]           h_imag [0:N-1][0:N-1],

    // -------------------------------------------------------
    // y vector input
    // -------------------------------------------------------
    input  logic                              y_valid,
    input  logic signed [N*WL_IN-1:0]         y_re_flat,
    input  logic signed [N*WL_IN-1:0]         y_im_flat,

    // -------------------------------------------------------
    // g_y = H^H y output
    // -------------------------------------------------------
    output logic                              x_valid,
    output logic signed [N*MF_WL_OUT-1:0]     x_re_flat,
    output logic signed [N*MF_WL_OUT-1:0]     x_im_flat
);

// ================================================================
// Elaboration guards
// ================================================================
generate
    if (N != 8)
        $fatal(1, "hermitian_mf_chain: N must be 8");
    if (WL_IN != 1 + INT_BITS + FL_IN)
        $fatal(1, "hermitian_mf_chain: WL_IN (%0d) != 1+INT_BITS+FL_IN (%0d+%0d+%0d)",
               WL_IN, 1, INT_BITS, FL_IN);
    if (MF_FL_OUT != MF_FL_Q5)
        $fatal(1, "hermitian_mf_chain: MF_FL_OUT must equal MF_FL_Q5");
endgenerate

// ================================================================
// Hermitian block outputs (unpacked arrays)
// ================================================================
logic                       herm_valid_out;
logic signed [WL_IN-1:0]    hh_out_real [0:N-1][0:N-1];  // [col_of_HH][row_of_HH]
logic signed [WL_IN-1:0]    hh_out_imag [0:N-1][0:N-1];

// ================================================================
// Coefficient hold registers
// (latched when herm_valid_out fires; held stable during y burst)
// ================================================================
logic signed [WL_IN-1:0]    coef_hold_real [0:N-1][0:N-1];
logic signed [WL_IN-1:0]    coef_hold_imag [0:N-1][0:N-1];

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                coef_hold_real[r][c] <= '0;
                coef_hold_imag[r][c] <= '0;
            end
    end else if (herm_valid_out) begin
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                coef_hold_real[r][c] <= hh_out_real[r][c];
                coef_hold_imag[r][c] <= hh_out_imag[r][c];
            end
    end
end

// hh_load timing
// --------------
// coef_hold is updated via non-blocking assignment (NBA) on the posedge
// where herm_valid_out=1.  At that same posedge, hh_re_flat_int is still
// combinationally presenting the OLD coef_hold values (pre-NBA).
// If hh_load were asserted on that same cycle the MF would latch zeros.
//
// Fix: register hh_load one cycle after herm_valid_out.  By the time
// hh_load fires, coef_hold has already settled to the correct H^H values,
// so the MF samples valid data.  This adds 1 cycle to the chain latency
// (total: HERM_LAT + 1_coef_hold_settle + 1_hh_load_reg + MF_LAT = 13).
logic hh_load_int;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) hh_load_int <= 1'b0;
    else        hh_load_int <= herm_valid_out;
end

// ================================================================
// Flatten hold registers → MF_Wrap flat buses
// Convention (matches MF_Wrap unpack):
//   flat[(r*N + c)*WL_IN +: WL_IN]  =  hh[r][c]
// hermitian_pipe delivers hh_out[r][c] with the same r/c semantics
// for the square case.
// ================================================================
logic signed [N*N*WL_IN-1:0] hh_re_flat_int;
logic signed [N*N*WL_IN-1:0] hh_im_flat_int;

generate
    for (genvar gr = 0; gr < N; gr++) begin : g_flat_row
        for (genvar gc = 0; gc < N; gc++) begin : g_flat_col
            assign hh_re_flat_int[(gr*N + gc)*WL_IN +: WL_IN] = coef_hold_real[gr][gc];
            assign hh_im_flat_int[(gr*N + gc)*WL_IN +: WL_IN] = coef_hold_imag[gr][gc];
        end
    end
endgenerate

// ================================================================
// hermitian_pipe instantiation
// ================================================================
hermitian_pipe #(
    .ROWS            ( N        ),
    .COLS            ( N        ),
    .WL              ( WL_IN    ),
    .INT_BITS        ( INT_BITS ),
    .FRAC_BITS       ( FL_IN    ),
    .REGISTER_OUTPUT ( HERM_REG )
) u_herm (
    .clk       ( clk            ),
    .rst_n     ( rst_n          ),
    .valid_in  ( h_valid        ),
    .h_real    ( h_real         ),
    .h_imag    ( h_imag         ),
    .valid_out ( herm_valid_out ),
    .hh_real   ( hh_out_real    ),
    .hh_imag   ( hh_out_imag    )
);

// ================================================================
// matched_filter_pipe_wrap instantiation
// ================================================================
matched_filter_pipe_wrap #(
    .N          ( N           ),
    .MF_WL_IN   ( WL_IN       ),
    .MF_FL_IN   ( FL_IN       ),
    .MF_WL_W    ( MF_WL_W     ),
    .MF_FL_W    ( MF_FL_W     ),
    .MF_WL_PROD ( MF_WL_PROD  ),
    .MF_FL_PROD ( MF_FL_PROD  ),
    .MF_FL_Q2   ( MF_FL_Q2    ),
    .MF_FL_Q3   ( MF_FL_Q3    ),
    .MF_FL_Q4   ( MF_FL_Q4    ),
    .MF_FL_Q5   ( MF_FL_Q5    ),
    .MF_WL_OUT  ( MF_WL_OUT   ),
    .MF_FL_OUT  ( MF_FL_OUT   )
) u_mf (
    .clk        ( clk            ),
    .rst_n      ( rst_n          ),
    .en         ( en             ),
    .hh_load    ( hh_load_int    ),
    .hh_re_flat ( hh_re_flat_int ),
    .hh_im_flat ( hh_im_flat_int ),
    .y_valid    ( y_valid        ),
    .y_re_flat  ( y_re_flat      ),
    .y_im_flat  ( y_im_flat      ),
    .valid_out  ( x_valid       ),
    .x_re_flat  ( x_re_flat     ),
    .x_im_flat  ( x_im_flat     )
);

endmodule
// ============================================================
// hermitian_mf_chain.sv — end of file
// ============================================================