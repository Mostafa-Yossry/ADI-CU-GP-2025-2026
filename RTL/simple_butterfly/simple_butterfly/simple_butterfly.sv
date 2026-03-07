module simple_butterfly #(
    parameter IWIDTH = 12,
    parameter CWIDTH = 16,
    parameter OWIDTH = 12,
    parameter SHIFT  = 0,

    localparam MPY_DELAY = 2,
    localparam BFLYLATENCY = MPY_DELAY + 3
)(
    input  wire                    i_clk,
    input  wire                    i_reset,
    input  wire                    i_clk_enable,

    input  wire [10:0]             i_twiddle_idx,

    input  wire [(2*IWIDTH-1):0]   i_left,
    input  wire [(2*IWIDTH-1):0]   i_right,
    input  wire                    i_aux,

    output wire [(2*OWIDTH-1):0]   o_left,
    output wire [(2*OWIDTH-1):0]   o_right,
    output reg                     o_aux
);

////////////////////////////////////////////////////////////
// Input registers
////////////////////////////////////////////////////////////

reg [(2*IWIDTH-1):0] r_left, r_right;

always @(posedge i_clk)
if(i_clk_enable)
begin
    r_left  <= i_left;
    r_right <= i_right;
end

////////////////////////////////////////////////////////////
// Twiddle ROM
////////////////////////////////////////////////////////////

wire [(2*CWIDTH-1):0] w_coef;
reg  [(2*CWIDTH-1):0] r_coef;

simple_twiddle_rom_bank #(
    .CWIDTH(CWIDTH)
) rom (
    .clk_i(i_clk),
    .clk_en_i(i_clk_enable),
    .index_i(i_twiddle_idx),
    .twiddle_o(w_coef)
);


always @(posedge i_clk)
if(i_clk_enable)
    r_coef <= w_coef;

////////////////////////////////////////////////////////////
// Split real / imag
////////////////////////////////////////////////////////////

wire signed [IWIDTH-1:0] l_r = r_left [2*IWIDTH-1:IWIDTH];
wire signed [IWIDTH-1:0] l_i = r_left [IWIDTH-1:0];

wire signed [IWIDTH-1:0] r_r = r_right[2*IWIDTH-1:IWIDTH];
wire signed [IWIDTH-1:0] r_i = r_right[IWIDTH-1:0];

wire signed [CWIDTH-1:0] w_r = r_coef[2*CWIDTH-1:CWIDTH];
wire signed [CWIDTH-1:0] w_i = r_coef[CWIDTH-1:0];

////////////////////////////////////////////////////////////
// Butterfly SUM / DIFF
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
// 3-Multiplier Complex Multiply (DSP)
////////////////////////////////////////////////////////////

reg signed [CWIDTH+IWIDTH+1:0] p1, p2, p3;

always @(posedge i_clk)
if(i_clk_enable)
begin
    p1 <= w_r * dif_r;
    p2 <= w_i * dif_i;
    p3 <= (w_r + w_i) * (dif_r + dif_i);
end

////////////////////////////////////////////////////////////
// Reconstruction
////////////////////////////////////////////////////////////

reg signed [CWIDTH+IWIDTH+2:0] mpy_r, mpy_i;

always @(posedge i_clk)
if(i_clk_enable)
begin
    mpy_r <= p1 - p2;
    mpy_i <= p3 - p1 - p2;
end

////////////////////////////////////////////////////////////
// Delay SUM path
////////////////////////////////////////////////////////////

reg signed [IWIDTH:0] sum_r_d [0:MPY_DELAY];
reg signed [IWIDTH:0] sum_i_d [0:MPY_DELAY];

integer i;

always @(posedge i_clk)
if(i_clk_enable)
begin
    sum_r_d[0] <= sum_r;
    sum_i_d[0] <= sum_i;

    for(i=1;i<=MPY_DELAY;i=i+1)
    begin
        sum_r_d[i] <= sum_r_d[i-1];
        sum_i_d[i] <= sum_i_d[i-1];
    end
end

////////////////////////////////////////////////////////////
// Extend to rounding width
////////////////////////////////////////////////////////////

wire signed [CWIDTH+IWIDTH+2:0] left_sr;
wire signed [CWIDTH+IWIDTH+2:0] left_si;

assign left_sr =
{
    {{2{sum_r_d[MPY_DELAY][IWIDTH]}}},
    sum_r_d[MPY_DELAY],
    {(CWIDTH-1){1'b0}}
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
// Rounding
////////////////////////////////////////////////////////////

wire signed [OWIDTH-1:0] left_r, left_i;
wire signed [OWIDTH-1:0] right_r, right_i;

convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
rnd_left_r (
    i_clk,
    i_clk_enable,
    left_sr,
    left_r
);

convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
rnd_left_i (
    i_clk,
    i_clk_enable,
    left_si,
    left_i
);

convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
rnd_right_r (
    i_clk,
    i_clk_enable,
    right_sr,
    right_r
);

convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
rnd_right_i (
    i_clk,
    i_clk_enable,
    right_si,
    right_i
);

////////////////////////////////////////////////////////////
// Aux pipeline
////////////////////////////////////////////////////////////

reg [BFLYLATENCY-1:0] aux_pipe;

always @(posedge i_clk)
if(i_reset)
    aux_pipe <= 0;
else if(i_clk_enable)
    aux_pipe <= {aux_pipe[BFLYLATENCY-2:0],i_aux};

always @(posedge i_clk)
if(i_reset)
    o_aux <= 0;
else if(i_clk_enable)
    o_aux <= aux_pipe[BFLYLATENCY-1];

////////////////////////////////////////////////////////////
// Outputs
////////////////////////////////////////////////////////////

assign o_left  = {left_r,left_i};
assign o_right = {right_r,right_i};


endmodule
