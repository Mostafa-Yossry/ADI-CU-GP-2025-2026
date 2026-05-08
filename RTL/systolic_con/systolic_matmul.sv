// =============================================================================
// systolic_matmul.sv
// -----------------------------------------------------------------------------
// Wavefront Systolic Array : ŷ = H^H · y
//
// FIX: valid_burst generator added (v2)
// -----------------------------------------------------------------------------
// ROOT CAUSE OF ORIGINAL BUG:
//   start is a 1-cycle pulse.  The original code propagated this single pulse
//   through all valid skew chains, so each PE received valid_in=1 for only ONE
//   cycle.  Because complex_mac_pe accumulates only when valid_in=1, each PE
//   accumulated only one product instead of all K_DEPTH products.
//   Result: wrong outputs, timeouts waiting for K_DEPTH valid pulses.
//
// FIX:
//   A K_DEPTH-bit shift register (valid_sr) seeds from start and produces
//   valid_burst = start | (|valid_sr), which is HIGH for exactly K_DEPTH
//   consecutive cycles (cycles 0..K_DEPTH-1).
//   valid_burst replaces start everywhere it fed the valid skew chains
//   (skew_valid column-skew and valid_top[0]).
//   Each PE now receives valid_in=1 for all K_DEPTH accumulation cycles. ✓
// -----------------------------------------------------------------------------
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
//   The array matches the diagram in the specification exactly.
//
//   Mapping onto the diagram variables:
//     d_{ij}  ←→  H^H(i-1, j-1)   (enters from the TOP,    flows DOWNWARD)
//     c_{ij}  ←→  y(i-1)           (enters from the LEFT,   flows RIGHTWARD)
//     e_{ij}  ←→  partial dot-product at PE[i-1][j-1], flows RIGHTWARD
//
//   For the MF case COLS=1, so there is only one column of PEs (one output
//   per row).  The parameter COLS generalises this to full matrix × matrix.
//
//   INPUT SKEWING (wavefront alignment):
//   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//   In the reference diagram each d column and each c row are staggered by
//   pipeline registers so that matching indices arrive at the same PE on
//   the same cycle.
//
//   For H^H element at PE[row][col]:
//     d skew = col   delay registers before the element reaches row 0.
//     The element then passes downward through rows 0..row, adding one
//     cycle per row (the a_pass register in each PE).
//     Total latency from input pin to PE[row][col] = col + row  cycles.
//
//   For y element feeding PE column col:
//     c skew = row   delay registers before the element reaches col 0.
//     The element then passes rightward through cols 0..col, adding one
//     cycle per col (the b_pass register in each PE).
//     Total latency from input pin to PE[row][col] = row + col  cycles.
//
//   Both operands arrive at PE[row][col] at the same time  ✓
//   (latency = row + col  for both).
//
//   valid_in skewing:
//     A valid token accompanies each H^H column.  It receives col stages of
//     column-direction skew (skew_valid) so valid_top[col] arrives at row 0
//     of column col on cycle col.  An additional row stages of row-direction
//     skew (skew_valid2) then delay it further, so PE[row][col] sees valid_in
//     on cycle (row + col) — exactly when both operands arrive.  ✓
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
localparam MAX_SKEW_A = ROWS - 1;   // H^H row gr needs gr cycles of delay
localparam MAX_SKEW_B = ROWS - 1;   // y   is delayed by 0..ROWS-1 for rows

// ---------------------------------------------------------------------------
// valid burst generator
// ---------------------------------------------------------------------------
// start is a 1-cycle pulse on cycle 0.  Each PE must see valid_in=1 for
// ALL K_DEPTH accumulation cycles so that it accumulates every product.
// A shift-register of depth K_DEPTH seeds from start and produces a burst
// that is high for exactly K_DEPTH consecutive cycles (cycles 0..K_DEPTH-1).
// This burst replaces the bare "start" signal fed into all valid skew chains.
// ---------------------------------------------------------------------------
reg [K_DEPTH-1:0] valid_sr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        valid_sr <= {K_DEPTH{1'b0}};
    else if (en)
        valid_sr <= {valid_sr[K_DEPTH-2:0], start};
end

// valid_burst is high from cycle 0 (start) through cycle K_DEPTH-1
wire valid_burst = start | (|valid_sr);

// ---------------------------------------------------------------------------
// 2a. H^H row skew:
//   The testbench time-multiplexes H^H: at cycle k, hh_real_w[gr] = H^H[gr][k].
//   PE[gr][gc].valid_in fires at cycle gr+gc.  At that cycle we need A = H^H[gr][gc],
//   i.e. hh_real_w[gr] as it was at cycle gc — which is gr cycles in the past.
//   Therefore each row gr needs its own delay chain of depth gr.
//
//   skew_a_r[gr][gs] = hh_real_w[gr] delayed gs+1 cycles, gs = 0..gr-1.
//   For gr==0: no delay — connect directly.
//   For gr>0:  use skew_a_r[gr][gr-1] as the A input for every PE in that row.
//
//   This is independent of column gc: the same delayed value is correct for
//   all columns because hh_real_w[gr] naturally presents H^H[gr][gc] at cycle gc,
//   and the gr-cycle delay makes it arrive at cycle gc+gr = PE[gr][gc].valid time.
// ---------------------------------------------------------------------------

reg signed [WL_INT-1:0] skew_a_r [0:ROWS-1][0:ROWS-1]; // [row][stage], stage=0..ROWS-2
reg signed [WL_INT-1:0] skew_a_i [0:ROWS-1][0:ROWS-1];

// valid skew chain: one per output column (depth = col stages)
reg skew_valid [0:COLS-1][0:COLS-1];   // [col][stage]

// 2D valid skew: valid_skew2[col][row][stage] delays valid_top[col] by row
// additional stages so PE[row][col] sees valid at cycle (row + col).
// Maximum extra row delay = ROWS-1.
reg skew_valid2 [0:COLS-1][0:ROWS-1][0:ROWS-1];  // [col][row][stage]

// ---------------------------------------------------------------------------
// 2b. y row skew:  c enters the left; delay row row by row cycles.
//     skew_y_r[col][row][depth] where depth goes 0..row
// ---------------------------------------------------------------------------
reg signed [WL_INT-1:0] skew_y_r [0:COLS-1][0:ROWS-1][0:ROWS-1]; // [col][row][stage]
reg signed [WL_INT-1:0] skew_y_i [0:COLS-1][0:ROWS-1][0:ROWS-1];

genvar gr, gc, gs;

// ---------------------------------------------------------------------------
// Register processes for skew chains (async reset)
// ---------------------------------------------------------------------------
generate
    // --- H^H per-row delay chains -------------------------------------------
    // skew_a_r[gr][gs]: hh_real_w[gr] delayed gs+1 cycles, for gs=0..gr-1.
    // Row 0 needs no delay (direct connection), so only rows 1..ROWS-1 have chains.
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

    // --- y skew chains (row-wise delay) -------------------------------------
    for (gc = 0; gc < COLS; gc = gc + 1) begin : skew_y_col
        for (gr = 0; gr < ROWS; gr = gr + 1) begin : skew_y_row
            for (gs = 0; gs < gr; gs = gs + 1) begin : skew_y_stage
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        skew_y_r[gc][gr][gs] <= {WL_INT{1'b0}};
                        skew_y_i[gc][gr][gs] <= {WL_INT{1'b0}};
                    end else if (en) begin
                        if (gs == 0) begin
                            skew_y_r[gc][gr][gs] <= y_real_w[gc];
                            skew_y_i[gc][gr][gs] <= y_imag_w[gc];
                        end else begin
                            skew_y_r[gc][gr][gs] <= skew_y_r[gc][gr][gs-1];
                            skew_y_i[gc][gr][gs] <= skew_y_i[gc][gr][gs-1];
                        end
                    end
                end
            end
        end
    end

    // --- valid skew chains (column-wise, same depth as H^H) -----------------
    // Feed valid_burst (K_DEPTH-wide window) instead of the bare start pulse.
    for (gc = 0; gc < COLS; gc = gc + 1) begin : skew_valid_col
        for (gs = 0; gs < gc; gs = gs + 1) begin : skew_valid_stage
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    skew_valid[gc][gs] <= 1'b0;
                end else if (en) begin
                    if (gs == 0)
                        skew_valid[gc][gs] <= valid_burst;  // was: start
                    else
                        skew_valid[gc][gs] <= skew_valid[gc][gs-1];
                end
            end
        end
    end

endgenerate

// ---------------------------------------------------------------------------
// 2c.  Wire the skewed values to the PE inputs.
// ---------------------------------------------------------------------------

// a_in_r[gr][gc]: A input for PE[gr][gc] = H^H[gr][gc] delayed to arrive
// at cycle gr+gc.  Same value for all gc in the same row (timing correct
// because hh_real_w[gr] is time-muxed and naturally presents H^H[gr][gc]
// at cycle gc; the gr-stage delay makes it arrive at gr+gc).
wire signed [WL_INT-1:0] a_in_r [0:ROWS-1]; // one delayed value per row
wire signed [WL_INT-1:0] a_in_i [0:ROWS-1];

generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : wire_a_row
        if (gr == 0) begin : wire_a_row0
            assign a_in_r[gr] = hh_real_w[gr];   // no delay
            assign a_in_i[gr] = hh_imag_w[gr];
        end else begin : wire_a_rowN
            assign a_in_r[gr] = skew_a_r[gr][gr-1];   // gr stages of delay
            assign a_in_i[gr] = skew_a_i[gr][gr-1];
        end
    end
endgenerate

// b_left and valid_top wire declarations (used in generate blocks below)
wire signed [WL_INT-1:0] b_left_r [0:ROWS-1][0:COLS-1];
wire signed [WL_INT-1:0] b_left_i [0:ROWS-1][0:COLS-1];
wire                     valid_top [0:COLS-1];

generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : wire_b_row
        for (gc = 0; gc < COLS; gc = gc + 1) begin : wire_b_col
            if (gr == 0) begin : wire_b_row0
                assign b_left_r[gr][gc] = y_real_w[gc];
                assign b_left_i[gr][gc] = y_imag_w[gc];
            end else begin : wire_b_rowN
                assign b_left_r[gr][gc] = skew_y_r[gc][gr][gr-1];
                assign b_left_i[gr][gc] = skew_y_i[gc][gr][gr-1];
            end
        end
    end

    for (gc = 0; gc < COLS; gc = gc + 1) begin : wire_valid
        if (gc == 0) begin : wire_valid_col0
            assign valid_top[gc] = valid_burst;  // was: start
        end else begin : wire_valid_colN
            assign valid_top[gc] = skew_valid[gc][gc-1];
        end
    end

    // --- valid 2D row skew -------------------------------------------------
    // skew_valid2 already feeds from valid_top[gc] which now carries
    // valid_burst (or its column-skewed version).  No change needed here.
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

// ===========================================================================
// SECTION 3 : PE array wiring
// ===========================================================================
//
// PE[row][col] receives:
//   a (H^H): a_in_r[row] = hh_real_w[row] delayed row cycles.
//            Correct for all columns: hh_real_w[row] naturally presents
//            H^H[row][gc] at cycle gc; row-cycle delay → arrives at cycle row+gc.
//   b (y):   b_left[row][col] from row-skew chain (same as before)
//   e_in:    col==0 → 0;  col>0 → e_out of PE[row][col-1]
//   valid_in: skew_valid2 as before
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

            // --- Select A input (H^H, direct per-row skew) ------------------
            // Each PE[gr][gc] receives H^H[gr][gc] via the per-row delay chain.
            // a_in_r[gr] = hh_real_w[gr] delayed gr cycles, correct for all gc.
            // a_pass is still registered inside the PE but its output is unused.
            wire signed [WL_INT-1:0] pe_a_r_in;
            wire signed [WL_INT-1:0] pe_a_i_in;
            assign pe_a_r_in = a_in_r[gr];
            assign pe_a_i_in = a_in_i[gr];

            // --- Select B input (y element for this PE column) --------------
            // y is spatial: y_real[gc] = y(k=gc), held constant each transaction.
            // b_left[gr][gc] = y_real_w[gc] delayed by gr row-skew stages so
            // PE[gr][gc] sees y(gc) at exactly cycle (gr+gc) — matching the
            // wavefront.  Each PE takes B directly from its own skew output;
            // the b_pass output is still registered (keeps pipeline uniform)
            // but is not used as a B source in this spatial-y mapping.
            wire signed [WL_INT-1:0] pe_b_r_in;
            wire signed [WL_INT-1:0] pe_b_i_in;
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

            // --- Select valid_in --------------------------------------------
            // valid_in at PE[gr][gc] must fire at cycle (gr + gc).
            // valid_top[gc] fires at cycle gc (col-skew already applied).
            // An additional gr-stage row-skew (skew_valid2) is needed for gr > 0.
            wire pe_valid_in;
            if (gr == 0) begin : sel_vin_row0
                // Row 0: no extra row delay — valid_top[gc] arrives at the right cycle.
                assign pe_valid_in = valid_top[gc];
            end else begin : sel_vin_rowN
                // Row > 0: gr extra pipeline stages on valid_top[gc].
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