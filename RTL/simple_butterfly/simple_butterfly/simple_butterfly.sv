// ==============================================================================
// MODULE: simple_butterfly
// PURPOSE: A highly optimized, pipelined Radix-2 Decimation-in-Frequency (DIF) 
//          Butterfly execution unit for a 4096-point FFT.
// LATENCY: 7 clock cycles 
// ==============================================================================
module simple_butterfly #(
    parameter IWIDTH = 12, // Input bit-width per real/imaginary component
    parameter CWIDTH = 16, // Twiddle factor (Coefficient) bit-width
    parameter OWIDTH = 12, // Output bit-width per component
    parameter SHIFT  = 0,  // Rounding shift factor

    // The multiplier takes 2 cycles (1 for p1/p2/p3, 1 for reconstruction).
    localparam MPY_DELAY = 2,
    // Total pipeline latency = 7 cycles
    localparam BFLYLATENCY = MPY_DELAY + 3
)(
    input  wire                    i_clk,
    input  wire                    i_reset,
    input  wire                    i_clk_enable,

    // Control and Addressing
    input  wire [10:0]             i_twiddle_idx, // 11-bit index for the 4096-point Twiddle ROM

    // Data Inputs (Packed as {Real, Imaginary})
    input  wire [(2*IWIDTH-1):0]   i_left,
    input  wire [(2*IWIDTH-1):0]   i_right,
    
    // The Zero-Overhead Trigger Pulse (from the .qe wire in the wrapper)
    input  wire                    i_aux,

    // Data Outputs
    output wire [(2*OWIDTH-1):0]   o_left,
    output wire [(2*OWIDTH-1):0]   o_right,
    
    // The "Done" Pulse (drives the .de wire in the wrapper)
    output reg                     o_aux
);

////////////////////////////////////////////////////////////
// STAGE 1: Input Registration
// To achieve high fMAX (maximum clock frequency), inputs are 
// immediately latched into flip-flops.
////////////////////////////////////////////////////////////
reg [(2*IWIDTH-1):0] r_left, r_right;

always @(posedge i_clk)
if(i_clk_enable)
begin
    r_left  <= i_left;
    r_right <= i_right;
end

////////////////////////////////////////////////////////////
// STAGE 1b: Twiddle ROM Fetch
// Occurs in parallel with input registration.
////////////////////////////////////////////////////////////
wire [(2*CWIDTH-1):0] w_coef;
reg  [(2*CWIDTH-1):0] r_coef;

// Instantiate the ROM block holding the pre-computed sine/cosine values
simple_twiddle_rom_bank #(
    .CWIDTH(CWIDTH)
) rom (
    .clk_i(i_clk),
    .clk_en_i(i_clk_enable),
    .index_i(i_twiddle_idx),
    .twiddle_o(w_coef)
);

// Latch the fetched Twiddle factor
always @(posedge i_clk)
if(i_clk_enable)
    r_coef <= w_coef;

////////////////////////////////////////////////////////////
// STAGE 2: Data Splitting (Combinational)
// Unpacking the 24-bit inputs into 12-bit Real and Imaginary wires
////////////////////////////////////////////////////////////
wire signed [IWIDTH-1:0] l_r = r_left [2*IWIDTH-1:IWIDTH];
wire signed [IWIDTH-1:0] l_i = r_left [IWIDTH-1:0];

wire signed [IWIDTH-1:0] r_r = r_right[2*IWIDTH-1:IWIDTH];
wire signed [IWIDTH-1:0] r_i = r_right[IWIDTH-1:0];

wire signed [CWIDTH-1:0] w_r = r_coef[2*CWIDTH-1:CWIDTH];
wire signed [CWIDTH-1:0] w_i = r_coef[CWIDTH-1:0];

////////////////////////////////////////////////////////////
// STAGE 3: The "Cross" (Pre-Addition and Subtraction)
// Top Leg   = Left + Right (sum)
// Bottom Leg = Left - Right (dif) -> This goes to the multiplier next
////////////////////////////////////////////////////////////
reg signed [IWIDTH:0] sum_r, sum_i;
reg signed [IWIDTH:0] dif_r, dif_i;

always @(posedge i_clk)
if(i_clk_enable)
begin
    sum_r <= l_r + r_r;
    sum_i <= l_i + r_i;

    dif_r <= l_r - r_r;
    dif_i <= l_i - r_i;
end

////////////////////////////////////////////////////////////
// STAGE 4: 3-Multiplier Complex Multiply (Gauss's Trick)
// Standard complex math needs 4 multipliers. We use 3 to save 
// massive silicon area, at the cost of extra adders.
////////////////////////////////////////////////////////////
reg signed [CWIDTH+IWIDTH+1:0] p1, p2, p3;

always @(posedge i_clk)
if(i_clk_enable)
begin
    p1 <= w_r * dif_r;                     // C * A
    p2 <= w_i * dif_i;                     // D * B
    p3 <= (w_r + w_i) * (dif_r + dif_i);   // (C+D) * (A+B)
end

////////////////////////////////////////////////////////////
// STAGE 5: Multiplier Reconstruction
// Resolving the 3 products back into standard Real/Imaginary results.
////////////////////////////////////////////////////////////
reg signed [CWIDTH+IWIDTH+2:0] mpy_r, mpy_i;

always @(posedge i_clk)
if(i_clk_enable)
begin
    mpy_r <= p1 - p2;          // Real: (C*A) - (D*B)
    mpy_i <= p3 - p1 - p2;     // Imag: (C+D)(A+B) - CA - DB = CB + AD
end

////////////////////////////////////////////////////////////
// STAGE 6: Delay SUM path (Synchronization)
// The Top Leg (sum) finished mathematically back in Stage 3.
// We must delay it by MPY_DELAY (2 cycles) so it arrives at the 
// output exactly parallel with the Bottom Leg's multiplier results.
////////////////////////////////////////////////////////////
reg signed [IWIDTH:0] sum_r_d [0:MPY_DELAY];
reg signed [IWIDTH:0] sum_i_d [0:MPY_DELAY];

integer i;

always @(posedge i_clk)
if(i_clk_enable)
begin
    // Push the fresh sum into the front of the queue
    sum_r_d[0] <= sum_r;
    sum_i_d[0] <= sum_i;

    // Shift it down the line
    for(i=1;i<=MPY_DELAY;i=i+1)
    begin
        sum_r_d[i] <= sum_r_d[i-1];
        sum_i_d[i] <= sum_i_d[i-1];
    end
end

////////////////////////////////////////////////////////////
// STAGE 7: Padding and Sign Extension
// The multiplier generated a lot of extra bits. We must sign-extend 
// the delayed Top Leg (sum) so it exactly matches the bit-width 
// of the Bottom Leg before we send them to the rounders.
////////////////////////////////////////////////////////////
wire signed [CWIDTH+IWIDTH+2:0] left_sr;
wire signed [CWIDTH+IWIDTH+2:0] left_si;

assign left_sr =
{
    {{2{sum_r_d[MPY_DELAY][IWIDTH]}}}, // Sign extension
    sum_r_d[MPY_DELAY],
    {(CWIDTH-1){1'b0}}                 // Padding with zeros
};

assign left_si =
{
    {{2{sum_i_d[MPY_DELAY][IWIDTH]}}},
    sum_i_d[MPY_DELAY],
    {(CWIDTH-1){1'b0}}
};

wire signed [CWIDTH+IWIDTH+2:0] right_sr;
wire signed [CWIDTH+IWIDTH+2:0] right_si;

assign right_sr =
{
    {{2{mpy_r[CWIDTH+IWIDTH+2]}}},
    mpy_r
};

assign right_si =
{
    {{2{mpy_i[CWIDTH+IWIDTH+2]}}},
    mpy_i
};

////////////////////////////////////////////////////////////
// STAGE 8: Convergent Rounding
// Safely slicing off the extra multiplier bits to return the 
// data to OWIDTH (12 bits) without introducing DC bias noise.
////////////////////////////////////////////////////////////
wire signed [OWIDTH-1:0] left_r, left_i;
wire signed [OWIDTH-1:0] right_r, right_i;

convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_left_r  (i_clk, i_clk_enable, left_sr, left_r);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_left_i  (i_clk, i_clk_enable, left_si, left_i);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_right_r (i_clk, i_clk_enable, right_sr, right_r);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_right_i (i_clk, i_clk_enable, right_si, right_i);

////////////////////////////////////////////////////////////
// STAGE 9: The Trigger Pipeline (Aux Pipe)
// This is the shadow pipeline for the control path!
// It delays the i_aux trigger pulse by the exact same number of 
// cycles as the data pipeline (BFLYLATENCY). 
////////////////////////////////////////////////////////////
reg [BFLYLATENCY-1:0] aux_pipe;

always @(posedge i_clk)
if(i_reset)
    aux_pipe <= 0;
else if(i_clk_enable)
    // Shift the spark into the pipeline
    aux_pipe <= {aux_pipe[BFLYLATENCY-2:0], i_aux};

always @(posedge i_clk)
if(i_reset)
    o_aux <= 0;
else if(i_clk_enable)
    // The spark pops out exactly when the math finishes!
    o_aux <= aux_pipe[BFLYLATENCY-1];

////////////////////////////////////////////////////////////
// STAGE 10: Outputs
// Repacking the 12-bit Real/Imaginary values into 24-bit vectors
////////////////////////////////////////////////////////////
assign o_left  = {left_r, left_i};
assign o_right = {right_r, right_i};

endmodule
