// =============================================================================
// herm_mf_chain.sv
// -----------------------------------------------------------------------------
// Integration wrapper: hermitian_pipe → matched_filter_pipe
//
// Implements the sub-chain:
//
//   H (from channel estimator / top port)
//        │
//        ▼
//   hermitian_pipe          H^H = conj(H)^T
//        │  hh_load (1-cycle pulse on valid_out)
//        ▼
//   matched_filter_pipe     z = H^H · y
//        │
//        ▼
//   z (→ Phase 2 forward substitution)
//   gy_enable (sticky pipeline-primed flag → Phase 2 input enable)
//
// -----------------------------------------------------------------------------
// Interface contract with the parent top module
// -----------------------------------------------------------------------------
// This module is designed to slot into top_mimo_linear_solver_complex_pipelined.
// It matches that module's port conventions exactly:
//
//   clk, rst         — parent uses active-high rst; we invert internally
//   y_re_flat / y_im_flat — N*WIDTH-bit flat buses, 16-bit elements, Q0.11 data
//   H ports           — N*WIDTH-bit flat buses added here (Risk 7 resolution);
//                       16-bit elements, Q0.11 data (same convention as y)
//   h_valid           — 1-cycle pulse: "new H matrix available"
//   y_valid           — per-vector strobe from upstream
//   z_re_flat / z_im_flat — N*16-bit flat output buses (Q4.11 elements)
//   z_valid           — output valid strobe
//   gy_enable         — sticky flag; route to Phase 2 input enable in parent
//
// -----------------------------------------------------------------------------
// Fixed-point format summary (verified, must not change — see handoff §3)
// -----------------------------------------------------------------------------
//   Input H, y   Q0.11   WL_IN=12   (12-bit signed; packed in 16-bit slots)
//   Internal     Q0.15   WL_INT=16
//   Product      Q0.30   WL_PROD=32
//   Output z     Q4.11   WL_OUT=16
//
// -----------------------------------------------------------------------------
// WIDTH vs WL_IN resolution (handoff Risk 1)
// -----------------------------------------------------------------------------
// The parent's flat buses carry WIDTH=16-bit slots.  The sub-modules need
// WL_IN=12-bit Q0.11 values.  A 16-bit signed word holding a Q0.11 value has
// its useful content in [11:0]; bits [15:12] are sign extension.  Therefore
// the slice [i*WIDTH +: 12] (equivalently [i*WIDTH+11 : i*WIDTH]) extracts
// the correct 12-bit Q0.11 word without any numerical conversion.  No rounding,
// no saturation.  This is a pure width slice.
//
// -----------------------------------------------------------------------------
// Pipeline latency (REGISTER_OUTPUT=1, N=8)
// -----------------------------------------------------------------------------
//   u_herm  LATENCY = 1 cycle
//   u_mf    LATENCY = 1 + $clog2(N) = 4 cycles   (for N=8)
//   TOTAL           = 5 cycles from h_valid (= herm_valid_in) to z_valid
//
// -----------------------------------------------------------------------------
// Flow controller rules (handoff §6e)
// -----------------------------------------------------------------------------
//   Rule 1: herm_valid_in = h_valid_req & mf_en
//           (herm has no en; gating valid_in is the only backpressure)
//   Rule 2: mf_valid_in = herm_valid_in delayed 1 cycle
//           (fires on same posedge as hh_load_w = herm.valid_out)
//   Rule 3: h_valid_req must be a 1-cycle pulse; no overlap with in-flight y
//   Rule 4: mf_en=0 propagates to both modules via Rule 1
//
// =============================================================================

module herm_mf_chain #(
    // -------------------------------------------------------------------------
    // Sizing — must match parent top_mimo_linear_solver_complex_pipelined
    // -------------------------------------------------------------------------
    parameter int N     = 8,    // Matrix dimension (NxN); MUST be power of two
    parameter int WIDTH = 16    // Slot width of parent flat buses (bits)
                                // Sub-module WL_IN=12 is fixed; see note above
)(
    input  logic                         clk,
    input  logic                         rst,          // active-HIGH (matches parent)

    // -------------------------------------------------------------------------
    // H matrix input  (new channel estimate; assert h_valid for exactly 1 cycle)
    // No H port exists on the parent top — added here per handoff Risk 7.
    // In silicon this connects to the channel estimator output.
    // In the integration TB it is driven from H_real.txt / H_imag.txt.
    // -------------------------------------------------------------------------
    input  logic                         h_valid,      // 1-cycle load pulse
    input  logic signed [N*WIDTH-1:0]    h_re_flat,    // row-major, 16-bit slots
    input  logic signed [N*WIDTH-1:0]    h_im_flat,    // Q0.11 data in [11:0]

    // -------------------------------------------------------------------------
    // y vector streaming input  (one N-element vector per valid cycle)
    // Same bus format as parent's y_re_flat / y_im_flat.
    // -------------------------------------------------------------------------
    input  logic                         y_valid,
    input  logic signed [N*WIDTH-1:0]    y_re_flat,
    input  logic signed [N*WIDTH-1:0]    y_im_flat,

    // -------------------------------------------------------------------------
    // Pipeline enable  (tie high for free-running; deassert to stall)
    // When mf_en=0 the entire pipeline (both sub-modules) freezes.
    // The flow controller deasserts herm_valid_in simultaneously (Rule 1).
    // -------------------------------------------------------------------------
    input  logic                         mf_en,

    // -------------------------------------------------------------------------
    // z vector output  (= H^H · y, Q4.11, 16-bit slots, N*16-bit flat)
    // -------------------------------------------------------------------------
    output logic                         z_valid,
    output logic signed [N*WIDTH-1:0]    z_re_flat,
    output logic signed [N*WIDTH-1:0]    z_im_flat,

    // -------------------------------------------------------------------------
    // gy_enable: sticky "pipeline primed" flag.
    // 0 after reset; latches to 1 on the first z_valid; never clears until rst.
    // Route to Phase 2 forward substitution input enable in the parent.
    // -------------------------------------------------------------------------
    output logic                         gy_enable
);

// =============================================================================
// Part 1 — Internal fixed-point widths (verified constants, never track WIDTH)
// =============================================================================

    localparam int WL_IN         = 12;   // Q0.11 input
    localparam int INT_BITS_IN   =  0;
    localparam int FRAC_BITS_IN  = 11;

    localparam int WL_INT        = 16;   // Q0.15 internal
    localparam int INT_BITS_INT  =  0;
    localparam int FRAC_BITS_INT = 15;

    localparam int WL_OUT        = 16;   // Q4.11 output
    localparam int INT_BITS_OUT  =  4;
    localparam int FRAC_BITS_OUT = 11;


// =============================================================================
// Part 2 — Reset polarity adapter (handoff Risk 2)
// Parent: active-high rst.  Sub-modules: active-low rst_n.
// Single inverter; applied to both sub-module rst_n ports.
// =============================================================================

    logic rst_n_int;
    assign rst_n_int = ~rst;


// =============================================================================
// Part 3 — Unpacked arrays for sub-module ports
// =============================================================================

    // H matrix — hermitian_pipe input
    logic signed [WL_IN-1:0] h_real_arr [0:N-1][0:N-1];
    logic signed [WL_IN-1:0] h_imag_arr [0:N-1][0:N-1];

    // H^H — internal wire between hermitian_pipe and matched_filter_pipe
    logic signed [WL_IN-1:0] hh_real_w  [0:N-1][0:N-1];
    logic signed [WL_IN-1:0] hh_imag_w  [0:N-1][0:N-1];
    logic                    hh_load_w;              // = u_herm.valid_out

    // y vector — matched_filter_pipe input
    logic signed [WL_IN-1:0] y_real_arr [0:N-1];
    logic signed [WL_IN-1:0] y_imag_arr [0:N-1];

    // z vector — matched_filter_pipe output (unpacked; re-packed to flat below)
    logic signed [WL_OUT-1:0] z_real_arr [0:N-1];
    logic signed [WL_OUT-1:0] z_imag_arr [0:N-1];


// =============================================================================
// Part 4 — Flat-bus → unpacked array unpacking
// -----------------------------------------------------------------------------
// WIDTH=16 slot, WL_IN=12: extract [11:0] of each 16-bit slot.
// Bits [15:12] are sign extension of the Q0.11 value — discarded safely.
// Layout: element i occupies bits [i*WIDTH +: WIDTH]; Q0.11 data in [11:0].
// =============================================================================

    generate
        for (genvar i = 0; i < N; i++) begin : g_unpack

            // H matrix — row-major: element [r][c] at index r*N+c
            for (genvar j = 0; j < N; j++) begin : g_unpack_h
                assign h_real_arr[i][j] =
                    h_re_flat[(i*N + j)*WIDTH +: WL_IN];
                assign h_imag_arr[i][j] =
                    h_im_flat[(i*N + j)*WIDTH +: WL_IN];
            end

            // y vector — element i at slot i
            assign y_real_arr[i] = y_re_flat[i*WIDTH +: WL_IN];
            assign y_imag_arr[i] = y_im_flat[i*WIDTH +: WL_IN];

        end
    endgenerate


// =============================================================================
// Part 5 — Flow controller  (handoff §6e Rules 1–4)
// =============================================================================

    logic herm_valid_in;   // gated h_valid request → hermitian_pipe.valid_in
    logic mf_valid_in;     // delayed herm_valid_in → matched_filter_pipe.valid_in

    // -------------------------------------------------------------------------
    // Rule 1: Gate herm.valid_in with mf_en.
    // hermitian_pipe has no en port.  If valid_in fires while mf_en=0, the
    // resulting hh_load_w pulse would overwrite coef registers in a frozen MF
    // pipeline, corrupting the next output frame.
    // -------------------------------------------------------------------------
    assign herm_valid_in = h_valid & mf_en;

    // -------------------------------------------------------------------------
    // Rule 2: mf.valid_in = herm.valid_in delayed exactly 1 cycle.
    // herm.valid_out (= hh_load_w) fires 1 cycle after herm.valid_in.
    // mf.valid_in must fire on the SAME posedge as hh_load_w so that Stage 1
    // samples coefs (registered at posedge C+1) on the following posedge C+2.
    // Registering herm_valid_in by 1 cycle gives exactly this relationship.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n_int) begin
        if (!rst_n_int) mf_valid_in <= 1'b0;
        else            mf_valid_in <= herm_valid_in;
    end

    // Rule 3 (caller responsibility): h_valid must be a 1-cycle pulse with no
    // other mf.valid_in active at the same posedge.  The UPDATE_INTERVAL
    // (50*N cycles) in the parent guarantees sufficient separation.
    //
    // Rule 4: mf_en=0 → herm_valid_in=0 (Rule 1) → mf_valid_in goes 0 one
    // cycle later.  No new valid_in reaches the frozen MF.  Fully handled.


// =============================================================================
// Part 6 — hermitian_pipe instantiation
// =============================================================================

    hermitian_pipe #(
        .ROWS           (N      ),
        .COLS           (N      ),
        .WL             (WL_IN  ),    // 12 — Q0.11 verified
        .INT_BITS       (INT_BITS_IN  ),
        .FRAC_BITS      (FRAC_BITS_IN ),
        .REGISTER_OUTPUT(1      )     // latency=1; hh_load_w = valid_out
    ) u_herm (
        .clk      (clk           ),
        .rst_n    (rst_n_int     ),
        .valid_in (herm_valid_in ),   // flow-controller gated (Rule 1)
        .h_real   (h_real_arr   ),
        .h_imag   (h_imag_arr   ),
        .valid_out(hh_load_w    ),   // directly drives u_mf.hh_load (Rule 2 source)
        .hh_real  (hh_real_w    ),
        .hh_imag  (hh_imag_w    )
    );


// =============================================================================
// Part 7 — matched_filter_pipe instantiation
// =============================================================================

    matched_filter_pipe #(
        .ROWS         (N             ),
        .COLS         (N             ),   // N must be power of two
        .WL_IN        (WL_IN         ),   // 12
        .INT_BITS_IN  (INT_BITS_IN   ),   //  0
        .FRAC_BITS_IN (FRAC_BITS_IN  ),   // 11
        .WL_INT       (WL_INT        ),   // 16
        .INT_BITS_INT (INT_BITS_INT  ),   //  0
        .FRAC_BITS_INT(FRAC_BITS_INT ),   // 15
        .WL_OUT       (WL_OUT        ),   // 16
        .INT_BITS_OUT (INT_BITS_OUT  ),   //  4
        .FRAC_BITS_OUT(FRAC_BITS_OUT )    // 11
    ) u_mf (
        .clk      (clk          ),
        .rst_n    (rst_n_int    ),
        .en       (mf_en        ),
        // Coefficient load — driven by u_herm.valid_out (hh_load_w).
        // hh_load is independent of en (by MF design); coefs latch regardless
        // of pipeline state.  Flow controller Rule 1 prevents this from firing
        // while the pipeline is frozen.
        .hh_load  (hh_load_w   ),
        .hh_real  (hh_real_w   ),
        .hh_imag  (hh_imag_w   ),
        // Streaming y input
        .valid_in (mf_valid_in ),   // Rule 2: 1 cycle after herm_valid_in
        .y_real   (y_real_arr  ),
        .y_imag   (y_imag_arr  ),
        // Outputs
        .valid_out(z_valid      ),
        .gy_enable(gy_enable    ),   // → Phase 2 input enable in parent
        .yhat_real(z_real_arr   ),
        .yhat_imag(z_imag_arr   )
    );


// =============================================================================
// Part 8 — Unpacked z arrays → flat output buses
// -----------------------------------------------------------------------------
// WL_OUT=16 == WIDTH=16 here, so each element fills its slot exactly.
// Written as a generate for robustness in case WIDTH ever diverges from WL_OUT.
// The upper (WIDTH - WL_OUT) bits are sign-extended.
// =============================================================================

    generate
        for (genvar i = 0; i < N; i++) begin : g_pack_z
            assign z_re_flat[i*WIDTH +: WL_OUT] =
                z_real_arr[i];
            assign z_im_flat[i*WIDTH +: WL_OUT] =
                z_imag_arr[i];

            // Sign-extend if WIDTH > WL_OUT (defensive; currently WIDTH==WL_OUT==16)
            if (WIDTH > WL_OUT) begin : g_sign_ext_z
                assign z_re_flat[i*WIDTH + WL_OUT +: (WIDTH - WL_OUT)] =
                    {(WIDTH - WL_OUT){z_real_arr[i][WL_OUT-1]}};
                assign z_im_flat[i*WIDTH + WL_OUT +: (WIDTH - WL_OUT)] =
                    {(WIDTH - WL_OUT){z_imag_arr[i][WL_OUT-1]}};
            end
        end
    endgenerate


// =============================================================================
// Part 9 — Elaboration-time guards
// =============================================================================

`ifdef SIMULATION
    initial begin : elab_checks
        // N must be power of two (MF adder tree requirement)
        if ((N & (N - 1)) != 0)
            $fatal(1, "herm_mf_chain: N=%0d must be a power of two", N);
        // WIDTH must accommodate the 12-bit Q0.11 slice
        if (WIDTH < WL_IN)
            $fatal(1, "herm_mf_chain: WIDTH=%0d < WL_IN=%0d; cannot slice Q0.11 from flat bus",
                   WIDTH, WL_IN);
        // H flat bus must be wide enough for N*N elements
        // (structural — if N or WIDTH change this catches mismatches)
        $display("[herm_mf_chain] N=%0d WIDTH=%0d WL_IN=%0d WL_OUT=%0d TOTAL_LAT=%0d",
                 N, WIDTH, WL_IN, WL_OUT,
                 u_herm.LATENCY + u_mf.LATENCY);
    end
`endif


endmodule

// =============================================================================
// End of herm_mf_chain.sv
// =============================================================================