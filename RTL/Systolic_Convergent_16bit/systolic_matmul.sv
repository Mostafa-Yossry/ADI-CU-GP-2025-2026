// =============================================================================
// systolic_matmul.sv
// -----------------------------------------------------------------------------
// Wavefront Systolic Array : ŷ = H^H · y   (Matched Filter, Block 2)
//
// MATLAB model reference:
//   T_Z = MULTIPLICATION_TYPES('fixed_point_Z_8x8', 12)
//   Z_fixed = systolic_matmul_8_8__8_1_mex(HH, Y, T_Z)
//
// Fixed-point formats:
//   I/O boundary  : Q1.11,  12-bit  (WL_IN  = 12)
//   After widening: Q1.15,  16-bit  (WL_INT = 16)  [4 zero LSBs appended]
//   After multiply: Q2.30,  32-bit  (full precision)
//   After rounding: Q5.11,  16-bit  (WL_OUT = 16)  [RIGHT_SH=19, convergent]
//   Output yhat   : Q5.11,  16-bit  — matches MATLAB FL_OUT=11
//
// Parameters (defaults for matched filter):
//   ROWS    = 8    (rows of H^H = elements of output yhat)
//   COLS    = 1    (yhat is 8x1)
//   K_DEPTH = 8    (dot-product length)
//   WL_IN   = 12   (Q1.11 input boundary)
//   WL_INT  = 16   (Q1.15 internal after widening)
//   WL_OUT  = 16   (Q5.11 output — 16-bit)
//
// Pipeline latency (COLS=1):
//   pipe_latency = (ROWS-1) + (COLS-1) + K_DEPTH + 1 = 7+0+8+1 = 16 cycles
// =============================================================================

module systolic_matmul #(
    parameter ROWS    = 8,
    parameter COLS    = 1,
    parameter K_DEPTH = 8,
    parameter WL_IN   = 12,
    parameter WL_INT  = 16,
    parameter WL_OUT  = 16    // Q5.11  16-bit — matches MATLAB FL_OUT=11
)(
    input  wire clk,
    input  wire rst_n,
    input  wire en,
    input  wire start,

    input  wire signed [WL_IN-1:0] hh_real [0:ROWS-1],
    input  wire signed [WL_IN-1:0] hh_imag [0:ROWS-1],

    input  wire signed [WL_IN-1:0] y_real  [0:COLS-1],
    input  wire signed [WL_IN-1:0] y_imag  [0:COLS-1],

    output wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1][0:COLS-1],
    output wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1][0:COLS-1],
    output wire                     valid_out  [0:ROWS-1][0:COLS-1]
);

// ===========================================================================
// SECTION 1 : Input widening  (12-bit Q1.11 -> 16-bit Q1.15)
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

localparam MAX_SKEW_A = ROWS - 1;
localparam MAX_SKEW_B = ROWS - 1;

// ---------------------------------------------------------------------------
// valid_burst generator
// start is a 1-cycle pulse. valid_burst is HIGH for exactly K_DEPTH cycles.
// ---------------------------------------------------------------------------
reg [K_DEPTH-1:0] valid_sr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        valid_sr <= {K_DEPTH{1'b0}};
    else if (en)
        valid_sr <= {valid_sr[K_DEPTH-2:0], start};
end

wire valid_burst = start | (|valid_sr);

// ---------------------------------------------------------------------------
// H^H per-row delay chains (skew_a): row gr needs gr delay stages
// ---------------------------------------------------------------------------
reg signed [WL_INT-1:0] skew_a_r [0:ROWS-1][0:ROWS-1];
reg signed [WL_INT-1:0] skew_a_i [0:ROWS-1][0:ROWS-1];

// valid skew chains
reg skew_valid  [0:COLS-1][0:COLS-1];
reg skew_valid2 [0:COLS-1][0:ROWS-1][0:ROWS-1];

// y skew chains
reg signed [WL_INT-1:0] skew_y_r [0:COLS-1][0:ROWS-1][0:ROWS-1];
reg signed [WL_INT-1:0] skew_y_i [0:COLS-1][0:ROWS-1][0:ROWS-1];
wire                     valid_top [0:COLS-1];
genvar gr, gc, gs;

generate
    // H^H per-row delay chains
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

    // y skew chains
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

    // valid column skew chains
    for (gc = 0; gc < COLS; gc = gc + 1) begin : skew_valid_col
        for (gs = 0; gs < gc; gs = gs + 1) begin : skew_valid_stage
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    skew_valid[gc][gs] <= 1'b0;
                end else if (en) begin
                    if (gs == 0)
                        skew_valid[gc][gs] <= valid_burst;
                    else
                        skew_valid[gc][gs] <= skew_valid[gc][gs-1];
                end
            end
        end
    end

    // valid 2D row skew
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
// Wire skewed A inputs (one delayed value per row, shared across all cols)
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Wire B inputs and valid_top
// ---------------------------------------------------------------------------
wire signed [WL_INT-1:0] b_left_r [0:ROWS-1][0:COLS-1];
wire signed [WL_INT-1:0] b_left_i [0:ROWS-1][0:COLS-1];


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
            assign valid_top[gc] = valid_burst;
        end else begin : wire_valid_colN
            assign valid_top[gc] = skew_valid[gc][gc-1];
        end
    end
endgenerate

// ===========================================================================
// SECTION 3 : PE array
// ===========================================================================

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

            wire signed [WL_INT-1:0] pe_a_r_in = a_in_r[gr];
            wire signed [WL_INT-1:0] pe_a_i_in = a_in_i[gr];

            wire signed [WL_INT-1:0] pe_b_r_in = b_left_r[gr][gc];
            wire signed [WL_INT-1:0] pe_b_i_in = b_left_i[gr][gc];

            wire signed [WL_OUT-1:0] pe_e_r_in;
            wire signed [WL_OUT-1:0] pe_e_i_in;
            if (gc == 0) begin : sel_e_zero
                assign pe_e_r_in = {WL_OUT{1'b0}};
                assign pe_e_i_in = {WL_OUT{1'b0}};
            end else begin : sel_e_prev
                assign pe_e_r_in = pe_e_out_r[gr][gc-1];
                assign pe_e_i_in = pe_e_out_i[gr][gc-1];
            end

            wire pe_valid_in;
            if (gr == 0) begin : sel_vin_row0
                assign pe_valid_in = valid_top[gc];
            end else begin : sel_vin_rowN
                assign pe_valid_in = skew_valid2[gc][gr][gr-1];
            end

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

        end
    end
endgenerate

// ===========================================================================
// SECTION 4 : Output connections
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