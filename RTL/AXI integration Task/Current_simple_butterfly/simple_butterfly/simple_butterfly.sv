// ==============================================================================
// MODULE: simple_butterfly (Flattened / Un-pipelined Math)
// PURPOSE: A Radix-2 DIF Butterfly unit. Math is purely combinational.
// LATENCY: 2 clock cycles (Due to synchronous ROM and Rounder modules)
// ==============================================================================
module simple_butterfly #(
    parameter IWIDTH = 12, 
    parameter CWIDTH = 16, 
    parameter OWIDTH = 12, 
    parameter SHIFT  = 0,  

    // Total latency is strictly 2 cycles now.
    localparam BFLYLATENCY = 2 
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
    output wire                    o_aux  // Done pulse
);

////////////////////////////////////////////////////////////
// STAGE 1: Input Registration & ROM Fetch (1 Cycle)
// We must latch inputs so they arrive at the math cloud 
// at the exact same time the ROM spits out the twiddle factor.
////////////////////////////////////////////////////////////
reg [(2*IWIDTH-1):0] r_left, r_right;
reg                  r_aux;

always @(posedge i_clk) begin
    if(i_clk_enable) begin
        r_left  <= i_left;
        r_right <= i_right;
        r_aux   <= i_aux; // Delay trigger to match data
    end
end

wire [(2*CWIDTH-1):0] w_coef;

// Assuming the ROM has 1 cycle of read latency
twiddle_rom_bank #(.CWIDTH(CWIDTH)) rom (
    .clk_i(i_clk),
    .clk_en_i(i_clk_enable),
    .index_i(i_twiddle_idx),
    .twiddle_o(w_coef)
);

////////////////////////////////////////////////////////////
// STAGE 2: PURE COMBINATIONAL MATH CLOUD (0 Cycles)
// All registers are removed. This evaluates instantly.
////////////////////////////////////////////////////////////

// Unpack
wire signed [IWIDTH-1:0] l_r = r_left [2*IWIDTH-1:IWIDTH];
wire signed [IWIDTH-1:0] l_i = r_left [IWIDTH-1:0];
wire signed [IWIDTH-1:0] r_r = r_right[2*IWIDTH-1:IWIDTH];
wire signed [IWIDTH-1:0] r_i = r_right[IWIDTH-1:0];

wire signed [CWIDTH-1:0] w_r = w_coef[2*CWIDTH-1:CWIDTH];
wire signed [CWIDTH-1:0] w_i = w_coef[CWIDTH-1:0];

// The Cross
wire signed [IWIDTH:0] sum_r = l_r + r_r;
wire signed [IWIDTH:0] sum_i = l_i + r_i;
wire signed [IWIDTH:0] dif_r = l_r - r_r;
wire signed [IWIDTH:0] dif_i = l_i - r_i;

// 3-Multiplier Complex Multiply
wire signed [CWIDTH+IWIDTH+1:0] p1 = w_r * dif_r; 
wire signed [CWIDTH+IWIDTH+1:0] p2 = w_i * dif_i; 
wire signed [CWIDTH+IWIDTH+1:0] p3 = (w_r + w_i) * (dif_r + dif_i);

// Reconstruction
wire signed [CWIDTH+IWIDTH+2:0] mpy_r = p1 - p2;
wire signed [CWIDTH+IWIDTH+2:0] mpy_i = p3 - p1 - p2;

// Padding and Sign Extension
wire signed [CWIDTH+IWIDTH+2:0] left_sr, left_si;
wire signed [CWIDTH+IWIDTH+2:0] right_sr, right_si;

assign left_sr  = { {{2{sum_r[IWIDTH]}}}, sum_r, {(CWIDTH-1){1'b0}} };
assign left_si  = { {{2{sum_i[IWIDTH]}}}, sum_i, {(CWIDTH-1){1'b0}} };

assign right_sr = { {{2{mpy_r[CWIDTH+IWIDTH+2]}}}, mpy_r };
assign right_si = { {{2{mpy_i[CWIDTH+IWIDTH+2]}}}, mpy_i };

////////////////////////////////////////////////////////////
// STAGE 3: Convergent Rounding (1 Cycle)
// Your sub-module contains clock edges, adding the final cycle.
////////////////////////////////////////////////////////////
wire signed [OWIDTH-1:0] left_r, left_i, right_r, right_i;

convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_l_r (i_clk, i_clk_enable, left_sr, left_r);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_l_i (i_clk, i_clk_enable, left_si, left_i);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_r_r (i_clk, i_clk_enable, right_sr, right_r);
convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4) rnd_r_i (i_clk, i_clk_enable, right_si, right_i);

////////////////////////////////////////////////////////////
// STAGE 4: Control Synchronization
////////////////////////////////////////////////////////////
reg aux_out_reg;

always @(posedge i_clk) begin
    if(i_reset)
        aux_out_reg <= 0;
    else if(i_clk_enable)
        // Delay the trigger by 1 more cycle to match the convround latency
        aux_out_reg <= r_aux; 
end

assign o_aux   = aux_out_reg;
assign o_left  = {left_r, left_i};
assign o_right = {right_r, right_i};

endmodule
