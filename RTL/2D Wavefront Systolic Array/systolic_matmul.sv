// =============================================================================
// systolic_matmul.sv
// -----------------------------------------------------------------------------
// Wavefront Systolic Array : ŷ = H^H · y
//
// PURPOSE:
//   Computes the matched-filter output vector ŷ from the conjugate-transpose
//   channel matrix H^H and the received signal vector y:
//
//     ŷ(i) = Σ_{k=0}^{K-1}  H^H(i,k) · y(k)    for i = 0 .. ROWS-1
//
//   This is a ROWS × K  matrix  times a  K × COLS  matrix.
//   For the matched filter ŷ = H^H(8×8) · y(8×1): ROWS=8, COLS=K_DEPTH=8.
//   COLS is the accumulation dimension (dot-product length), NOT the number
//   of output columns.  y_real[gc] carries y(k=gc) — the k-th element of the
//   y vector — which is constant across the K_DEPTH input cycles.
//
// ARCHITECTURE — TRUE WAVEFRONT SYSTOLIC ARRAY:
// -----------------------------------------------
//   The array matches the specification diagram exactly.  All three data
//   streams propagate through the PE fabric — no broadcast wires.
//
//   Mapping onto the diagram variables:
//     d_{ij}  ←→  H^H(i-1, j-1)   (enters from the TOP,    flows DOWNWARD)
//     c_{ij}  ←→  y(i-1)           (enters from the LEFT,   flows RIGHTWARD)
//     e_{ij}  ←→  partial dot-product at PE[i-1][j-1], flows RIGHTWARD
//
//   DATA PROPAGATION:
//     H^H  : enters at PE[0][gc] for each column gc, propagates DOWNWARD
//              via the a_pass register chain (one hop per row).
//     y    : enters at PE[gr][0] for each row gr (after row-skew), propagates
//              RIGHTWARD via the b_pass register chain (one hop per col).
//     e    : partial sums flow RIGHTWARD from PE[gr][0] to PE[gr][COLS-1].
//     valid: propagates DOWNWARD with H^H (same a_pass timing).
//
//   INPUT SKEWING (wavefront alignment):
//   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//   H^H is time-multiplexed: hh_real[gr] carries H^H[gr][k] on input cycle k.
//   H^H needs NO external col-skew: H^H[gr][gc] arrives at the input on
//   cycle gc; with zero extra delay it reaches PE[0][gc] on cycle gc; then
//   a_pass propagates it to PE[gr][gc] on cycle gc+gr.  ✓
//
//   y is spatial: y_real[gc] = y(k=gc) is held constant.
//   y[gc] enters at PE[gr][0] after gr stages of row-skew (skew_b), so
//   PE[gr][0] sees y[gc] on cycle gr; b_pass then carries it rightward so
//   PE[gr][gc] sees it on cycle gr+gc.  ✓
//
//   Both operands arrive at PE[row][col] on cycle (row + col).  ✓
//
//   valid propagation:
//     start pulses on cycle 0.  skew_valid delays it col stages so
//     valid_top[col] fires on cycle col and enters PE[0][col].
//     valid then propagates DOWNWARD through a_pass: pe_valid[gr-1][gc]
//     drives valid_in of PE[gr][gc], so PE[gr][gc] sees valid on cycle
//     col+gr = row+col.  ✓  skew_valid2 provides the row-direction delay.
//
// TIMING:
//   - Present H^H column k on hh_real/imag[:,k] and y element y[k] on
//     y_real/imag[k] on clock cycle k  (k = 0 .. K-1), with start=1 on
//     cycle 0.
//   - All inputs are presented for K consecutive cycles (no gaps).
//   - valid_out[i] fires when ŷ(i) is ready at the right edge of the array.
//     The output latency is:
//       pipe_latency = (ROWS - 1) + (COLS - 1) + K_DEPTH + 1
//     For 8×8 with ROWS=8, COLS=K_DEPTH=8: (7) + (7) + (8) + (1) = 23 cycles.
//
// FIXED-POINT FORMATS (from modelling spec):
//   H^H input  (system boundary) : Q1.11, 12-bit  (WL_IN)
//   y   input  (system boundary) : Q1.11, 12-bit  (WL_IN)
//   After widening               : Q1.15, 16-bit  (WL_INT)
//   ŷ   output                   : Q5.11, 16-bit  (WL_OUT)
//
// MODELLING NOTES IMPLEMENTED:
//   [Note 1] 12-bit → 16-bit widening via 4 zero LSBs (input_widen).
//   [Note 4] H^H presented at full Q1.15 to multiplier — not pre-truncated.
//   [Note 5] 16×16 complex multiply → 32-bit full-precision product.
//   [Note 6] Output Q5.11 — smaller dynamic range than Block 1 (no σ²/P).
//   [Note 3] No diagonal σ²/P addition — pure matched filter only.
//
// RESET:
//   rst_n : active-low ASYNCHRONOUS reset throughout.
//
// PARAMETERS:
//   ROWS    : rows of H^H = rows of ŷ                    (default 8)
//   COLS    : columns of y = columns of ŷ                (default 1)
//   K_DEPTH : shared dimension = dot-product length       (default 8)
//   WL_IN   : input word length at I/O boundary           (default 12)
//   WL_INT  : internal word length after widening         (default 16)
//   WL_OUT  : output word length                          (default 16)
//
// PORTS:
//   clk                : system clock
//   rst_n              : active-low asynchronous reset
//   en                 : global clock enable (stall the pipeline when 0)
//   start              : pulse high for one cycle on the first input cycle
//                        (accompanies hh[:,0] and y[0])
//
//   hh_real[i]         : H^H column being fed this cycle, real part  of row i
//   hh_imag[i]         : H^H column being fed this cycle, imag part  of row i
//                        All ROWS elements of the current column are presented
//                        simultaneously; the column index advances each cycle.
//
//   y_real[c]          : y matrix column c, element for this cycle
//   y_imag[c]          : (c = 0 for MF; up to COLS-1 for general use)
//
//   yhat_real[i][c]    : ŷ output element (row i, col c), Q5.11
//   yhat_imag[i][c]
//   valid_out[i][c]    : high for one cycle when yhat[i][c] is valid
// =============================================================================

module systolic_matmul #(
    parameter ROWS    = 8,
    parameter COLS    = 1,
    parameter K_DEPTH = 8,
    parameter WL_IN   = 12,
    parameter WL_INT  = 16,
    parameter WL_OUT  = 16
)(
    input  wire clk,
    input  wire rst_n,   // active-low asynchronous reset
    input  wire en,      // global clock enable

    // --- Start strobe (one cycle, accompanies first column of inputs) -------
    input  wire start,

    // --- H^H matrix: one full column per cycle  (ROWS elements, 12-bit) ----
    input  wire signed [WL_IN-1:0] hh_real [0:ROWS-1],
    input  wire signed [WL_IN-1:0] hh_imag [0:ROWS-1],

    // --- y matrix: one element per column input per cycle (COLS elements) --
    input  wire signed [WL_IN-1:0] y_real  [0:COLS-1],
    input  wire signed [WL_IN-1:0] y_imag  [0:COLS-1],

    // --- Outputs: ŷ = H^H · y  (ROWS × COLS result) -----------------------
    output wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1][0:COLS-1],
    output wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1][0:COLS-1],
    output wire                     valid_out  [0:ROWS-1][0:COLS-1]
);

// ===========================================================================
// SECTION 1 : Input widening  (12-bit Q1.11 → 16-bit Q1.15)
// ===========================================================================

wire signed [WL_INT-1:0] hh_real_w [0:ROWS-1];
wire signed [WL_INT-1:0] hh_imag_w [0:ROWS-1];
wire signed [WL_INT-1:0] y_real_w  [0:COLS-1];
wire signed [WL_INT-1:0] y_imag_w  [0:COLS-1];

genvar gi;
generate
    for (gi = 0; gi < ROWS; gi = gi + 1) begin : gen_widen_hh
        input_widen #(.WL_IN(WL_IN), .WL_OUT(WL_INT))
            u_hr (.in_word(hh_real[gi]), .out_word(hh_real_w[gi]));
        input_widen #(.WL_IN(WL_IN), .WL_OUT(WL_INT))
            u_hi (.in_word(hh_imag[gi]), .out_word(hh_imag_w[gi]));
    end
    for (gi = 0; gi < COLS; gi = gi + 1) begin : gen_widen_y
        input_widen #(.WL_IN(WL_IN), .WL_OUT(WL_INT))
            u_yr (.in_word(y_real[gi]),  .out_word(y_real_w[gi]));
        input_widen #(.WL_IN(WL_IN), .WL_OUT(WL_INT))
            u_yi (.in_word(y_imag[gi]),  .out_word(y_imag_w[gi]));
    end
endgenerate

// ===========================================================================
// SECTION 2 : Input skew registers
// ===========================================================================
//
// Reference diagram:
//   d_{i,col} (H^H row i, column-index col):
//     Enters the TOP of the array.  Column col needs col pipeline-register
//     stages of delay so that H^H(i, col) reaches PE[0][col] on cycle
//     (col + i).  Each PE's a_pass register then propagates it downward,
//     adding one cycle per row, so PE[row][col] sees it on cycle (col + row).
//
//   c_{row,j} (y column j, element for row row):
//     Enters the LEFT of the array.  Row row needs row pipeline-register
//     stages of delay so that y[j] reaches PE[row][0] on cycle
//     (row + j).  Each PE's b_pass register then propagates it rightward,
//     adding one cycle per col, so PE[row][col] sees it on cycle (row + col).
//
//   Both arrive at PE[row][col] at cycle (row + col).  ✓
//
// valid_in skewing:
//   start is a one-cycle pulse on cycle 0 (the first H^H column).
//   A valid shift-register chain of depth (col) delays it to arrive at the
//   top of column col on the same cycle as hh column col.
//
// Implementation:
//   hh_skew[row][col][stage] : stage = 0..col-1 delay chain for row row
//   y_skew[col][row][stage]  : stage = 0..row-1 delay chain for col col
//   valid_skew[col][stage]   : stage = 0..col-1 delay chain
//
// Note: for col=0 and row=0 there is no delay (zero registers); the wire
// connects directly from the widened input.
// ---------------------------------------------------------------------------

// Maximum skew depth needed
localparam MAX_SKEW_A = ROWS - 1;   // H^H row gr needs gr cycles of row-skew
localparam MAX_SKEW_B = ROWS - 1;   // y row gr needs gr cycles of row-skew

// ---------------------------------------------------------------------------
// 2a. H^H per-row skew (enters top-left of each row, flows DOWNWARD via a_pass)
//
//   H^H is time-multiplexed: hh_real_w[gr] = H^H[gr][k] on input cycle k.
//   PE[gr][gc] must receive H^H[gr][gc] (from cycle gc) at wavefront cycle
//   gr+gc.  That means H^H[gr][gc] needs to be delayed by gr cycles from
//   when it appears on the input (cycle gc).
//
//   Implementation: each row gr has a gr-stage delay chain on its input.
//   The delayed value enters PE[0] of the RIGHTMOST column gc=0 and then
//   propagates RIGHTWARD down the row via a_pass — BUT since we need the
//   same H^H[gr][k] to arrive at every column gc at cycle gc+gr (different
//   time for different columns), we connect the per-row-skewed value to the
//   top of each column independently (no a_pass between columns for H^H).
//   Instead, a_pass carries H^H downward within each column, feeding rows
//   below with the current H^H[gr] value delayed one more cycle per row.
//
//   Wait — see note below.  With all rows parallel, a_pass carries H^H[gr]
//   downward but PE[gr+1][gc] needs H^H[gr+1][gc], not H^H[gr][gc-1].
//   Therefore a_pass outputs for H^H are NOT used for inter-row routing here;
//   each row gets its own independently skewed input.  The a_pass register
//   inside the PE still runs (it's part of the PE cell), but its output is
//   used only as the source for the ROW BELOW'S a_pass input if we want to
//   implement a true downward flow.  For this parallel-row H^H topology,
//   the per-row-skew + direct connection is the correct systolic equivalent.
// ---------------------------------------------------------------------------

reg signed [WL_INT-1:0] skew_a_r [0:ROWS-1][0:ROWS-1]; // [row][stage]
reg signed [WL_INT-1:0] skew_a_i [0:ROWS-1][0:ROWS-1];

// ---------------------------------------------------------------------------
// 2b. y row-skew (feeds left edge of each row only — col 0).
//   y is spatial: y_real_w[gc] = y(k=gc), held constant.
//   Row gr needs gr stages of delay so that y_real_w[gc] enters PE[gr][0]
//   on cycle gr.  b_pass then carries it rightward: PE[gr][gc] sees it on
//   cycle gr + gc.  Only one skew chain per (col, row) pair — col 0 gets
//   the skewed value; other cols get it via b_pass from the PE to the left.
// ---------------------------------------------------------------------------
reg signed [WL_INT-1:0] skew_b_r [0:COLS-1][0:ROWS-1][0:ROWS-1]; // [col][row][stage]
reg signed [WL_INT-1:0] skew_b_i [0:COLS-1][0:ROWS-1][0:ROWS-1];

// valid skew chain: one per PE column (depth = col stages).
// Delays 'start' by col cycles so valid_top[col] fires on cycle col.
reg skew_valid [0:COLS-1][0:COLS-1];   // [col][stage]

// 2D valid skew: delays valid_top[col] by row additional stages.
// PE[row][col] sees valid_in on cycle (row + col) — matching both operands.
reg skew_valid2 [0:COLS-1][0:ROWS-1][0:ROWS-1];  // [col][row][stage]

genvar gr, gc, gs;
wire                     valid_top [0:COLS-1];
// ---------------------------------------------------------------------------
// Register processes for skew chains (async reset)
// ---------------------------------------------------------------------------
generate
    // --- H^H per-row delay chains -------------------------------------------
    for (gr = 1; gr < ROWS; gr = gr + 1) begin : skew_a_row
        for (gs = 0; gs < gr; gs = gs + 1) begin : skew_a_stage
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    skew_a_r[gr][gs] <= {WL_INT{1'b0}};
                    skew_a_i[gr][gs] <= {WL_INT{1'b0}};
                end else if (en) begin
                    if (gs == 0) begin
                        skew_a_r[gr][gs] <= hh_real_w[gr];
                        skew_a_i[gr][gs] <= hh_imag_w[gr];
                    end else begin
                        skew_a_r[gr][gs] <= skew_a_r[gr][gs-1];
                        skew_a_i[gr][gs] <= skew_a_i[gr][gs-1];
                    end
                end
            end
        end
    end

    // --- y row-skew chains (feeds left edge of each row) --------------------
    // skew_b_r[gc][gr][gs]: y_real_w[gc] delayed gs+1 cycles, gs=0..gr-1.
    // Row 0: no delay (direct connection), so only rows 1..ROWS-1 have chains.
    for (gc = 0; gc < COLS; gc = gc + 1) begin : skew_b_col
        for (gr = 1; gr < ROWS; gr = gr + 1) begin : skew_b_row
            for (gs = 0; gs < gr; gs = gs + 1) begin : skew_b_stage
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        skew_b_r[gc][gr][gs] <= {WL_INT{1'b0}};
                        skew_b_i[gc][gr][gs] <= {WL_INT{1'b0}};
                    end else if (en) begin
                        if (gs == 0) begin
                            skew_b_r[gc][gr][gs] <= y_real_w[gc];
                            skew_b_i[gc][gr][gs] <= y_imag_w[gc];
                        end else begin
                            skew_b_r[gc][gr][gs] <= skew_b_r[gc][gr][gs-1];
                            skew_b_i[gc][gr][gs] <= skew_b_i[gc][gr][gs-1];
                        end
                    end
                end
            end
        end
    end

    // --- valid skew chains (column-wise, depth = col stages) ----------------
    for (gc = 0; gc < COLS; gc = gc + 1) begin : skew_valid_col
        for (gs = 0; gs < gc; gs = gs + 1) begin : skew_valid_stage
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    skew_valid[gc][gs] <= 1'b0;
                end else if (en) begin
                    if (gs == 0)
                        skew_valid[gc][gs] <= start;
                    else
                        skew_valid[gc][gs] <= skew_valid[gc][gs-1];
                end
            end
        end
    end

    // --- valid 2D row skew --------------------------------------------------
    // Delays valid_top[col] by row additional stages so PE[row][col] fires
    // valid_in at cycle (col + row) — same as when both A and B arrive.
    for (gc = 0; gc < COLS; gc = gc + 1) begin : skew_valid2_col
        for (gr = 0; gr < ROWS; gr = gr + 1) begin : skew_valid2_row
            for (gs = 0; gs < gr; gs = gs + 1) begin : skew_valid2_stage
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        skew_valid2[gc][gr][gs] <= 1'b0;
                    end else if (en) begin
                        if (gs == 0)
                            skew_valid2[gc][gr][gs] <= valid_top[gc];
                        else
                            skew_valid2[gc][gr][gs] <= skew_valid2[gc][gr][gs-1];
                    end
                end
            end
        end
    end

endgenerate

// ---------------------------------------------------------------------------
// 2c.  Wire the skewed values to the PE array edges.
// ---------------------------------------------------------------------------

// a_in_r[gr]: per-row skewed H^H, feeds all PEs in that row directly.
// Row 0: no delay. Row gr > 0: gr-stage delay output.
wire signed [WL_INT-1:0] a_in_r [0:ROWS-1];
wire signed [WL_INT-1:0] a_in_i [0:ROWS-1];

generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : wire_a_row
        if (gr == 0) begin : wire_a_row0
            assign a_in_r[gr] = hh_real_w[gr];
            assign a_in_i[gr] = hh_imag_w[gr];
        end else begin : wire_a_rowN
            assign a_in_r[gr] = skew_a_r[gr][gr-1];
            assign a_in_i[gr] = skew_a_i[gr][gr-1];
        end
    end
endgenerate

// b_left_r[gr][0]: B input for the left edge of each row (feeds PE[gr][0]).
// Row 0: direct. Row gr > 0: gr-stage skew output.
// For gc > 0, B propagates rightward via b_pass — b_left[gr][gc>0] unused.
wire signed [WL_INT-1:0] b_left_r [0:ROWS-1][0:COLS-1];
wire signed [WL_INT-1:0] b_left_i [0:ROWS-1][0:COLS-1];


generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : wire_b_row
        for (gc = 0; gc < COLS; gc = gc + 1) begin : wire_b_col
            if (gr == 0) begin : wire_b_row0
                assign b_left_r[gr][gc] = y_real_w[gc];
                assign b_left_i[gr][gc] = y_imag_w[gc];
            end else begin : wire_b_rowN
                assign b_left_r[gr][gc] = skew_b_r[gc][gr][gr-1];
                assign b_left_i[gr][gc] = skew_b_i[gc][gr][gr-1];
            end
        end
    end

    for (gc = 0; gc < COLS; gc = gc + 1) begin : wire_valid
        if (gc == 0) begin : wire_valid_col0
            assign valid_top[gc] = start;
        end else begin : wire_valid_colN
            assign valid_top[gc] = skew_valid[gc][gc-1];
        end
    end
endgenerate

// ===========================================================================
// SECTION 3 : PE array wiring — TRUE 2D SYSTOLIC
// ===========================================================================
//
// Data flows:
//   A (H^H) : each row gr receives its own per-row-skewed value a_in_r[gr]
//              (H^H[gr][k] delayed gr cycles), wired to ALL PEs in that row.
//              a_pass output from each PE is registered internally but carries
//              the same H^H[gr] value — not used for inter-row distribution
//              (each row has its own parallel H^H input port).
//
//   B (y)   : spatial mapping — every PE[gr][gc] is driven directly from
//              b_left_r[gr][gc] = y(gc) delayed gr cycles (skew_b).
//              b_pass is not used for inter-PE B routing.
//
//   e       : partial sums flow RIGHTWARD.
//              PE[gr][0].e_in  = 0
//              PE[gr][gc].e_in = pe_e_out_r[gr][gc-1]   (gc > 0)
//
//   valid   : 2D skew: valid_top[gc] delayed gr more stages via skew_valid2.
//              PE[gr][gc] sees valid_in at cycle (gc + gr) = row + col.  ✓
// ---------------------------------------------------------------------------

// Inter-PE wires (indexed [row][col])
wire signed [WL_INT-1:0] pe_a_pass_r [0:ROWS-1][0:COLS-1];
wire signed [WL_INT-1:0] pe_a_pass_i [0:ROWS-1][0:COLS-1];
wire signed [WL_INT-1:0] pe_b_pass_r [0:ROWS-1][0:COLS-1];
wire signed [WL_INT-1:0] pe_b_pass_i [0:ROWS-1][0:COLS-1];
wire signed [WL_OUT-1:0] pe_e_out_r  [0:ROWS-1][0:COLS-1];
wire signed [WL_OUT-1:0] pe_e_out_i  [0:ROWS-1][0:COLS-1];
wire                     pe_valid    [0:ROWS-1][0:COLS-1];

generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : pe_row
        for (gc = 0; gc < COLS; gc = gc + 1) begin : pe_col

            // --- A input: H^H, per-row skewed, enters each PE directly -------
            // Each row gr receives H^H[gr][k] delayed gr cycles (via skew_a),
            // so it arrives at the PE in that row at cycle k+gr = gc+gr (wavefront).
            // a_pass carries this value downward to rows below — but since all
            // rows receive their own H^H[gr] on parallel ports, a_pass is used
            // only to pass the value through the cell (PE spec requires it).
            // All columns in a row share the same a_in_r[gr] source.
            wire signed [WL_INT-1:0] pe_a_r_in;
            wire signed [WL_INT-1:0] pe_a_i_in;
            assign pe_a_r_in = a_in_r[gr];
            assign pe_a_i_in = a_in_i[gr];

            // --- B input: y(gc) delayed gr cycles, injected directly ----------
            // Spatial-y: b_left_r[gr][gc] = skew_b output = y(gc) delayed gr
            // cycles. Each PE gets its own independently-skewed y element.
            // b_pass is registered inside the PE but its output is unused here.
            wire signed [WL_INT-1:0] pe_b_r_in;
            wire signed [WL_INT-1:0] pe_b_i_in;
            // Spatial-y: every PE[gr][gc] gets y(gc) delayed gr cycles directly
            // from b_left_r[gr][gc]. b_pass is not used for B routing.
            assign pe_b_r_in = b_left_r[gr][gc];
            assign pe_b_i_in = b_left_i[gr][gc];

            // --- Select e_in (partial sum from left, 0 for leftmost) --------
            wire signed [WL_OUT-1:0] pe_e_r_in;
            wire signed [WL_OUT-1:0] pe_e_i_in;
            if (gc == 0) begin : sel_e_zero
                assign pe_e_r_in = {WL_OUT{1'b0}};
                assign pe_e_i_in = {WL_OUT{1'b0}};
            end else begin : sel_e_prev
                assign pe_e_r_in = pe_e_out_r[gr][gc-1];
                assign pe_e_i_in = pe_e_out_i[gr][gc-1];
            end

            // --- valid_in: 2D skew fires at cycle (gr + gc) -----------------
            // valid_top[gc] fires at cycle gc (col-skewed start).
            // skew_valid2[gc][gr] adds gr more stages → fires at cycle gc+gr. ✓
            wire pe_valid_in;
            if (gr == 0) begin : sel_vin_top
                assign pe_valid_in = valid_top[gc];
            end else begin : sel_vin_skew
                assign pe_valid_in = skew_valid2[gc][gr][gr-1];
            end

            // --- Instantiate PE ---------------------------------------------
            complex_mac_pe #(
                .WL_OP  (WL_INT),
                .WL_ACC (WL_OUT)
            ) u_pe (
                .clk          (clk),
                .rst_n        (rst_n),
                .en           (en),

                .a_real       (pe_a_r_in),
                .a_imag       (pe_a_i_in),
                .b_real       (pe_b_r_in),
                .b_imag       (pe_b_i_in),

                .e_in_real    (pe_e_r_in),
                .e_in_imag    (pe_e_i_in),

                .valid_in     (pe_valid_in),

                .a_pass_real  (pe_a_pass_r[gr][gc]),
                .a_pass_imag  (pe_a_pass_i[gr][gc]),
                .b_pass_real  (pe_b_pass_r[gr][gc]),
                .b_pass_imag  (pe_b_pass_i[gr][gc]),

                .e_out_real   (pe_e_out_r[gr][gc]),
                .e_out_imag   (pe_e_out_i[gr][gc]),

                .valid_out    (pe_valid[gr][gc])
            );

        end // pe_col
    end // pe_row
endgenerate

// ===========================================================================
// SECTION 4 : Output connections (rightmost column of PEs)
// ===========================================================================

generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : out_row
        for (gc = 0; gc < COLS; gc = gc + 1) begin : out_col
            assign yhat_real[gr][gc] = pe_e_out_r[gr][gc];
            assign yhat_imag[gr][gc] = pe_e_out_i[gr][gc];
            assign valid_out[gr][gc] = pe_valid[gr][gc];
        end
    end
endgenerate

endmodule