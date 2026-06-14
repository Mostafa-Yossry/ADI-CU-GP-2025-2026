module fft_sdf_stg #(
    parameter FIFO_DEPTH = 4, DATA_WIDTH = 12, NUMBER_OF_POINTS=4096
)(
    input  wire clk, rst_n, valid_in,
    input  wire signed [DATA_WIDTH-1: 0] in_r, in_i,
    input  wire  [3:0]             Q_in,Q_sum,Q_diff,Q_mult,Q_out,
    output wire signed [DATA_WIDTH-1: 0] stg_out_r, stg_out_i,
    output wire  valid_out
);
/* input - output - Parameters definition 
inputs:
in_r,in_i: input (real and img )
valid_in : Asserted when there is a valid input and Enable the FFT block
clk , rst_n
Q_in  :input Q notation just the integer part i.e (Q3.9) -> Q_in(3)
Q_sum :Q notation for the output sum 
Q_diff:Q notation for the output difference 
Q_mult:Q notation for the output multiplication  
Q_out :output Q noation

outputs :
stg_out_r,stg_out_i: output from the stage (real and img )
valid_out:Asserted when there is a valid output


Parameters 
parameter (DATA_WIDTH):The width of data input and output ports
parameter (FIFO_DEPTH):the size of the FIFO 
parameter NUMBER_OF_POINTS:Total number of points
*/

wire                                  fifo_mux_sel, out_mux_sel, bf_en, rot_en;
wire [$clog2(FIFO_DEPTH)-1:0]         twiddle_sel;
wire signed [DATA_WIDTH:0]            fifo_in_r, fifo_in_i;
wire signed [DATA_WIDTH:0]            fifo_out_r, fifo_out_i;
wire signed [DATA_WIDTH:0]            bf_sum_r, bf_sum_i;
wire signed [DATA_WIDTH:0]            bf_diff_r, bf_diff_i;
wire signed [DATA_WIDTH: 0]           out_r, out_i;
wire signed [DATA_WIDTH: 0]           in_r_extended, in_i_extended;
wire signed [2*DATA_WIDTH+1:0]        temp_mult_out_r, temp_mult_out_i;
wire signed [DATA_WIDTH:0]            inter_sum_r, inter_sum_i,inter_diff_r,inter_diff_i;
wire signed [DATA_WIDTH-1: 0]         stg_out_r_stage1,stg_out_i_stage1;

/*Sign Extension for the input to achieve the delayed quantization property*/
assign in_r_extended={in_r[DATA_WIDTH-1],in_r};
assign in_i_extended={in_i[DATA_WIDTH-1],in_i};

/*Feedback FIFO to store the values of the input and difference */
fifo #(.FIFO_DEPTH(FIFO_DEPTH), .DATA_WIDTH(DATA_WIDTH)) fifo_u0(
.clk(clk),
.rst_n(rst_n),
.in_r(fifo_in_r),
.in_i(fifo_in_i),
.out_r(fifo_out_r),
.out_i(fifo_out_i)
);

/*butterfly unit to calculate the sum and diff of the input */
butterfly_unit #(.DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(FIFO_DEPTH)) bf_u0(
.en(bf_en),
.a_r(fifo_out_r),
.a_i(fifo_out_i),
.b_r(in_r_extended),
.b_i(in_i_extended),
.inter_sum_r(inter_sum_r),
.inter_sum_i(inter_sum_i),
.inter_diff_r(inter_diff_r),
.inter_diff_i(inter_diff_i)
);

/*FSM to control the logic , Note each stage has its own FSM */
stg_fsm #(.FIFO_DEPTH(FIFO_DEPTH)) fsm_u0(
.clk(clk),
.rst_n(rst_n),
.valid_in(valid_in),
.fifo_mux_sel(fifo_mux_sel),
.out_mux_sel(out_mux_sel),
.bf_en(bf_en),
.rot_en(rot_en),
.twiddle_sel(twiddle_sel),
.valid_out(valid_out)
);

/*Mux to direct the real input of the FIFO*/
stg_mux #(.DATA_WIDTH(DATA_WIDTH)) fifo_mux_u0_r (
    .sel(fifo_mux_sel),
    .in0(inter_diff_r),
    .in1(in_r_extended),
    .out(fifo_in_r)
);

/*Mux to direct the img input of the FIFO*/
stg_mux #(.DATA_WIDTH(DATA_WIDTH)) fifo_mux_u0_i (
    .sel(fifo_mux_sel),
    .in0(inter_diff_i),
    .in1(in_i_extended),
    .out(fifo_in_i)
);

/*Mux to direct the real output to the mutliplier & rounding module*/
stg_mux #(.DATA_WIDTH(DATA_WIDTH)) out_mux_u0_r (
    .sel(out_mux_sel),
    .in0(fifo_out_r),
    .in1(inter_sum_r),
    .out(out_r)
);

/*Mux to direct the img output to the mutliplier & rounding module*/
stg_mux #(.DATA_WIDTH(DATA_WIDTH)) out_mux_u0_i (
    .sel(out_mux_sel),
    .in0(fifo_out_i),
    .in1(inter_sum_i),
    .out(out_i)
);

/* generate block to handle the special case (last stage) as it doesn't have a multiplier and instead it has a DFF at the output*/
generate
    /* If it's not the last stage instentiate both rotator and rounding module*/
    if(FIFO_DEPTH != 1) begin
        /*general complex Multiplier*/
        rotator #(.DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(FIFO_DEPTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) rotator_u0 (
            .rot_en(rot_en),
            .in_r(out_r),
            .in_i(out_i),
            .twiddle_sel(twiddle_sel),
            .temp_mult_out_r(temp_mult_out_r),
            .temp_mult_out_i(temp_mult_out_i)
        );
        /*Convergent rounding module */
        convergent_rounding #(.DATA_WIDTH(DATA_WIDTH)) conv_round (
         .inter_sum_r(out_r),
         .inter_sum_i(out_i),
         .temp_mult_out_r(temp_mult_out_r),
         .temp_mult_out_i(temp_mult_out_i),
         .Q_in(Q_in),
         .Q_sum(Q_sum),
         .Q_diff(Q_diff),
         .Q_mult(Q_mult),
         .Q_out(Q_out),
         .rot_en(rot_en),
         .out_r(stg_out_r),
         .out_i(stg_out_i)
        );
  
    end
    else begin
        /* If it's the last stage instentiate only the rounding module and also a DFF*/
        convergent_rounding #(.DATA_WIDTH(DATA_WIDTH)) conv_round (
         .inter_sum_r(out_r),
         .inter_sum_i(out_i),
         .temp_mult_out_r({ {13{out_r[DATA_WIDTH]}}, out_r }),
         .temp_mult_out_i({ {13{out_i[DATA_WIDTH]}}, out_i }),
         .Q_in(Q_in),
         .Q_sum(Q_sum),
         .Q_diff(Q_diff),
         .Q_mult(Q_mult),
         .Q_out(Q_out),
         //Force rot_en to 0 since the final stage doesn't have rotator 
         .rot_en(1'b0),
         .out_r(stg_out_r_stage1),
         .out_i(stg_out_i_stage1)
        );
        /*Register the real output of the last stage */
        dff #(.DATA_WIDTH(DATA_WIDTH)) stg_out_r_ff_u0(
        .clk(clk),
        .rst_n(rst_n),
        .in(stg_out_r_stage1),
        .out(stg_out_r)
        );
        /*Register the img output of the last stage */
        dff #(.DATA_WIDTH(DATA_WIDTH)) stg_out_i_ff_u0(
        .clk(clk),
        .rst_n(rst_n),
        .in(stg_out_i_stage1),
        .out(stg_out_i)
        );
    end
endgenerate




endmodule