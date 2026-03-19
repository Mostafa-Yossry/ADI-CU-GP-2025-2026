// ==============================================================================
// MODULE: simple_butterfly
// PURPOSE: A pipelined Radix-2 Decimation-in-Frequency (DIF) Butterfly unit.
// LATENCY: 6 clock cycles (Input Reg -> Add/Sub -> Mult -> Recon -> Round -> Out)
// ==============================================================================
module simple_butterfly #(
    parameter IWIDTH = 12, 
    parameter CWIDTH = 16, 
    parameter OWIDTH = 12, 
    parameter SHIFT  = 0,  

    // MPY_DELAY represents the stages between the Cross (Stage 3) and Reconstruction (Stage 5).
    localparam MPY_DELAY = 2,
    // Total latency from input pins to output pins is 6 cycles.
    localparam BFLYLATENCY =  MPY_DELAY + 3
)(
    input  wire                    i_clk,
    input  wire                    i_reset,
    input  wire                    i_clk_enable,
    input  wire [10:0]             i_twiddle_idx, 
    input  wire [(2*IWIDTH-1):0]   i_left,
    input  wire [(2*IWIDTH-1):0]   i_right,
    input  wire                    i_aux, // Trigger pulse

    output wire [(2*OWIDTH-1):0]   o_left,
    output wire [(2*OWIDTH-1):0]   o_right,
    output wire                     o_aux  // Done pulse
);

////////////////////////////////////////////////////////////
// STAGE 1: Input Registration (1 Cycle)
////////////////////////////////////////////////////////////
reg [(2*IWIDTH-1):0] r_left, r_right;

always @(posedge i_clk)
if(i_clk_enable) begin
    r_left  <= i_left;
    r_right <= i_right;
end

// Twiddle ROM (Assuming 1-cycle internal latency to match STAGE 1)
wire [(2*CWIDTH-1):0] w_coef;
reg  [(2*CWIDTH-1):0] r_coef;

twiddle_rom_bank #(.CWIDTH(CWIDTH)) rom (
    .clk_i(i_clk),
    .clk_en_i(i_clk_enable),
    .index_i(i_twiddle_idx),
    .twiddle_o(w_coef)
);

always @(posedge i_clk)
if(i_clk_enable)
    r_coef <= w_coef;

////////////////////////////////////////////////////////////
// STAGE 2: Data Splitting (Combinational)
////////////////////////////////////////////////////////////
wire signed [IWIDTH-1:0] l_r = r_left [2*IWIDTH-1:IWIDTH];
wire signed [IWIDTH-1:0] l_i = r_left [IWIDTH-1:0];
wire signed [IWIDTH-1:0] r_r = r_right[2*IWIDTH-1:IWIDTH];
wire signed [IWIDTH-1:0] r_i = r_right[IWIDTH-1:0];
wire signed [CWIDTH-1:0] w_r = r_coef[2*CWIDTH-1:CWIDTH];
wire signed [CWIDTH-1:0] w_i = r_coef[CWIDTH-1:0];

////////////////////////////////////////////////////////////
// STAGE 3: The Cross (Add/Sub) (1 Cycle)
////////////////////////////////////////////////////////////
reg signed [IWIDTH:0] sum_r, sum_i;
reg signed [IWIDTH:0] dif_r, dif_i;

always @(posedge i_clk)
if(i_clk_enable) begin
    sum_r <= l_r + r_r;
    sum_i <= l_i + r_i;
    dif_r <= l_r - r_r;
    dif_i <= l_i - r_i;
end

////////////////////////////////////////////////////////////
// STAGE 4: 3-Multiplier Complex Multiply (1 Cycle)
////////////////////////////////////////////////////////////
reg signed [CWIDTH+IWIDTH+1:0] p1, p2, p3;

always @(posedge i_clk)
if(i_clk_enable) begin
    p1 <= w_r * dif_r; 
    p2 <= w_i * dif_i; 
    p3 <= (w_r + w_i) * (dif_r + dif_i);
end

////////////////////////////////////////////////////////////
// STAGE 5: Multiplier Reconstruction (1 Cycle)
////////////////////////////////////////////////////////////
reg signed [CWIDTH+IWIDTH+2:0] mpy_r, mpy_i;

always @(posedge i_clk)
if(i_clk_enable) begin
    mpy_r <= p1 - p2;
    mpy_i <= p3 - p1 - p2;
end

////////////////////////////////////////////////////////////
// STAGE 6: Delay SUM path (Synchronization)
// FIX: To match the multiplier path (Stage 4 + Stage 5), 
// we only need TWO stages of delay for the sum.
////////////////////////////////////////////////////////////
reg signed [IWIDTH:0] sum_r_d [0:MPY_DELAY-1]; // Index 0 and 1
reg signed [IWIDTH:0] sum_i_d [0:MPY_DELAY-1];

integer i;
always @(posedge i_clk)
if(i_clk_enable) begin
    sum_r_d[0] <= sum_r;
    sum_i_d[0] <= sum_i;

    for(i=1; i < MPY_DELAY; i=i+1) begin
        sum_r_d[i] <= sum_r_d[i-1];
        sum_i_d[i] <= sum_i_d[i-1];
    end
end

////////////////////////////////////////////////////////////
// STAGE 7: Padding and Sign Extension (Combinational)
////////////////////////////////////////////////////////////
wire signed [CWIDTH+IWIDTH+2:0] left_sr, left_si;
wire signed [CWIDTH+IWIDTH+2:0] right_sr, right_si;

// Left path uses the end of the delay line (sum_r_d[1])
assign left_sr  = { {{2{sum_r_d[MPY_DELAY-1][IWIDTH]}}}, sum_r_d[MPY_DELAY-1], {(CWIDTH-1){1'b0}} };
assign left_si  = { {{2{sum_i_d[MPY_DELAY-1][IWIDTH]}}}, sum_i_d[MPY_DELAY-1], {(CWIDTH-1){1'b0}} };

assign right_sr = { {{2{mpy_r[CWIDTH+IWIDTH+2]}}}, mpy_r };
assign right_si = { {{2{mpy_i[CWIDTH+IWIDTH+2]}}}, mpy_i };

////////////////////////////////////////////////////////////
// STAGE 8: Convergent Rounding (1 Cycle)
////////////////////////////////////////////////////////////
wire signed [OWIDTH-1:0] left_r, left_i, right_r, right_i;

convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_l_r (i_clk, i_clk_enable, left_sr, left_r);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_l_i (i_clk, i_clk_enable, left_si, left_i);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_r_r (i_clk, i_clk_enable, right_sr, right_r);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_r_i (i_clk, i_clk_enable, right_si, right_i);

////////////////////////////////////////////////////////////
// STAGE 9: Aux Pipeline (Timing Match)
// FIX: Using a bit-vector to track i_aux across 6 cycles.
////////////////////////////////////////////////////////////
reg [BFLYLATENCY-1:0] aux_pipe;

always @(posedge i_clk)
if(i_reset)
    aux_pipe <= 0;
else if(i_clk_enable)
    aux_pipe <= {aux_pipe[BFLYLATENCY-2:0], i_aux};

// Output o_aux directly from the pipe to avoid an extra 7th cycle

    assign o_aux = aux_pipe[BFLYLATENCY-1];

////////////////////////////////////////////////////////////
// STAGE 10: Final Output Assignment
////////////////////////////////////////////////////////////
assign o_left  = {left_r, left_i};
assign o_right = {right_r, right_i};

endmodule
