module fft4096_dif #(
    parameter DATA_WIDTH = 12 ,
    parameter ORDERED_OUTPUT = 1  // 1 = Build RAM (Ordered), 0 = No RAM (Scrambled)
)(
    input  wire clk, rst_n, valid_in,
    input  wire signed [DATA_WIDTH-1: 0] in_r, in_i,
    output wire signed [DATA_WIDTH-1: 0] out_r, out_i,
    output wire                          valid_out, frame_done,
    output wire [11:0]                   out_index
);
/* input - output - Parameters definition 
inputs:
in_r,in_i: input (real and img )
valid_in : Asserted when there is a valid input and Enable the FFT block
clk , rst_n

outputs :
out_r,out_i: output (real and img )
valid_out:Asserted when there is a valid output
frame_done:Asserted when a frame ends ( for one pulse only )
out_index:The index of the current output 

Parameters 
parameter (DATA_WIDTH):The width of data input and output ports
parameter (ORDERED_OUTPUT):(1) Ordered output , (0) Scrambled output
*/

/*Number of points , Number of stages*/
localparam NUMBER_OF_POINTS = 4096;
localparam FFT_STAGES = $clog2(NUMBER_OF_POINTS);

// ---------------------------------------------------------------------------
//
// Fraction-length trace (verified vs MATLAB fft_types.m):
//   Input:11 -> stg1:9 -> stg2:8 -> stg3:8 -> stg4:7 -> stg5:6 -> stg6:6
//            -> stg7:5 -> stg8:5 -> stg9:4 -> stg10:4 -> stg11:3 -> stg12:3
// ---------------------------------------------------------------------------

/*Internal wires to connect the input and the output of each satge to the previous and the next one*/
wire signed [DATA_WIDTH-1: 0] stg1_r,  stg1_i;
wire signed [DATA_WIDTH-1: 0] stg2_r,  stg2_i;
wire signed [DATA_WIDTH-1: 0] stg3_r,  stg3_i;
wire signed [DATA_WIDTH-1: 0] stg4_r,  stg4_i;
wire signed [DATA_WIDTH-1: 0] stg5_r,  stg5_i;
wire signed [DATA_WIDTH-1: 0] stg6_r,  stg6_i;
wire signed [DATA_WIDTH-1: 0] stg7_r,  stg7_i;
wire signed [DATA_WIDTH-1: 0] stg8_r,  stg8_i;
wire signed [DATA_WIDTH-1: 0] stg9_r,  stg9_i;
wire signed [DATA_WIDTH-1: 0] stg10_r, stg10_i;
wire signed [DATA_WIDTH-1: 0] stg11_r, stg11_i;
wire signed [DATA_WIDTH-1: 0] stg12_r, stg12_i;

/*Asserted when there is a valid output*/
wire valid_out1,  valid_out2,  valid_out3,  valid_out4;
wire valid_out5,  valid_out6,  valid_out7,  valid_out8;
wire valid_out9,  valid_out10, valid_out11, valid_out12;
wire valid_out12_synced;
/*A counter to help in indexing the output*/
wire [FFT_STAGES-1:0] raw_count;

/*Calling 12 stages from the general stage module fft_sdf_stg*/
// Stage 1 
fft_sdf_stg #(.FIFO_DEPTH(2048),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .in_r(in_r),
    .in_i(in_i),
    .Q_in(4'd1),
    .Q_sum(4'd2),
    .Q_diff(4'd2),
    .Q_mult(4'd3),
    .Q_out(4'd3),
    .stg_out_r(stg1_r),
    .stg_out_i(stg1_i),
    .valid_out(valid_out1));

// Stage 2 
fft_sdf_stg #(.FIFO_DEPTH(1024),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg2 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out1),
    .in_r(stg1_r),
    .in_i(stg1_i),
    .Q_in(4'd3),
    .Q_sum(4'd4),
    .Q_diff(4'd4),
    .Q_mult(4'd4),
    .Q_out(4'd4),
    .stg_out_r(stg2_r),
    .stg_out_i(stg2_i),
    .valid_out(valid_out2));

// Stage 3 
fft_sdf_stg #(.FIFO_DEPTH(512),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg3 (
    .clk(clk),.rst_n(rst_n),.valid_in(valid_out2),
    .in_r(stg2_r),.in_i(stg2_i),
    .Q_in(4'd4),.Q_sum(4'd4),.Q_diff(4'd4),.Q_mult(4'd4),.Q_out(4'd4),
    .stg_out_r(stg3_r),.stg_out_i(stg3_i),.valid_out(valid_out3));

// Stage 4 
fft_sdf_stg #(.FIFO_DEPTH(256),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg4 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out3),
    .in_r(stg3_r),
    .in_i(stg3_i),
    .Q_in(4'd4),
    .Q_sum(4'd5),
    .Q_diff(4'd5),
    .Q_mult(4'd5),
    .Q_out(4'd5),
    .stg_out_r(stg4_r),
    .stg_out_i(stg4_i),
    .valid_out(valid_out4));

// Stage 5 
fft_sdf_stg #(.FIFO_DEPTH(128),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg5 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out4),
    .in_r(stg4_r),
    .in_i(stg4_i),
    .Q_in(4'd5),
    .Q_sum(4'd6),
    .Q_diff(4'd6),
    .Q_mult(4'd6),
    .Q_out(4'd6),
    .stg_out_r(stg5_r),
    .stg_out_i(stg5_i),
    .valid_out(valid_out5));

// Stage 6 
fft_sdf_stg #(.FIFO_DEPTH(64),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg6 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out5),
    .in_r(stg5_r),
    .in_i(stg5_i),
    .Q_in(4'd6),
    .Q_sum(4'd6),
    .Q_diff(4'd6),
    .Q_mult(4'd6),
    .Q_out(4'd6),
    .stg_out_r(stg6_r),
    .stg_out_i(stg6_i),
    .valid_out(valid_out6));

// Stage 7 
fft_sdf_stg #(.FIFO_DEPTH(32),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg7 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out6),
    .in_r(stg6_r),
    .in_i(stg6_i),
    .Q_in(4'd6),
    .Q_sum(4'd7),
    .Q_diff(4'd7),
    .Q_mult(4'd7),
    .Q_out(4'd7),
    .stg_out_r(stg7_r),
    .stg_out_i(stg7_i),
    .valid_out(valid_out7));

// Stage 8 
fft_sdf_stg #(.FIFO_DEPTH(16),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg8 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out7),
    .in_r(stg7_r),
    .in_i(stg7_i),
    .Q_in(4'd7),
    .Q_sum(4'd7),
    .Q_diff(4'd7),
    .Q_mult(4'd7),
    .Q_out(4'd7),
    .stg_out_r(stg8_r),
    .stg_out_i(stg8_i),
    .valid_out(valid_out8));

// Stage 9
fft_sdf_stg #(.FIFO_DEPTH(8),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg9 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out8),
    .in_r(stg8_r),
    .in_i(stg8_i),
    .Q_in(4'd7),
    .Q_sum(4'd8),
    .Q_diff(4'd8),
    .Q_mult(4'd8),
    .Q_out(4'd8),
    .stg_out_r(stg9_r),
    .stg_out_i(stg9_i),
    .valid_out(valid_out9));

// Stage 10 
fft_sdf_stg #(.FIFO_DEPTH(4),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg10 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out9),
    .in_r(stg9_r),
    .in_i(stg9_i),
    .Q_in(4'd8),
    .Q_sum(4'd8),
    .Q_diff(4'd8),
    .Q_mult(4'd8),
    .Q_out(4'd8),
    .stg_out_r(stg10_r),
    .stg_out_i(stg10_i),
    .valid_out(valid_out10));

// Stage 11 
fft_sdf_stg #(.FIFO_DEPTH(2),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg11 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out10),
    .in_r(stg10_r),
    .in_i(stg10_i),
    .Q_in(4'd8),
    .Q_sum(4'd9),
    .Q_diff(4'd9),
    .Q_mult(4'd9),
    .Q_out(4'd9),
    .stg_out_r(stg11_r),
    .stg_out_i(stg11_i),
    .valid_out(valid_out11));

// Stage 12 
fft_sdf_stg #(.FIFO_DEPTH(1),.DATA_WIDTH(DATA_WIDTH),.NUMBER_OF_POINTS(NUMBER_OF_POINTS)) fft_stg12 (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out11),
    .in_r(stg11_r),
    .in_i(stg11_i),
    .Q_in(4'd9),
    .Q_sum(4'd9),
    .Q_diff(4'd9),
    .Q_mult(4'd9),
    .Q_out(4'd9),
    .stg_out_r(stg12_r),
    .stg_out_i(stg12_i),
    .valid_out(valid_out12));


// =========================================================
//  Sync the early valid_out12 with the delayed stg12_r (as the output from the last stage is registered so we have to register the valid_out to be synchronized)
// =========================================================

dff #(.DATA_WIDTH(1)) sync_valid_dff(
    .clk(clk), .rst_n(rst_n), .in(valid_out12), .out(valid_out12_synced)
);


/* A generate block to handle the output case (ORDERED-SCRAMBLED)*/
generate
    /*ORDERED_OUTPUT=1 means we want the output ordered so we have to call the bit_reversal module*/
    if (ORDERED_OUTPUT == 1) 
    begin : gen_ordered_path
        
        wire ordered_valid;
        wire signed [DATA_WIDTH-1: 0] ordered_r, ordered_i;
 
        bit_reversal_complex #(.DATA_WIDTH(DATA_WIDTH) , .FFT_POINTS(NUMBER_OF_POINTS)) bit_rev_u0 (
            .clk(clk), .rst_n(rst_n), .valid_in(valid_out12_synced), // perfectly aligned with the output
            .in_r(stg12_r), .in_i(stg12_i),
            .out_r(ordered_r), .out_i(ordered_i),
            .valid_out(ordered_valid)
        );

        valid_out_gen #(.FRAME_SIZE(NUMBER_OF_POINTS)) valid_gen_u0 (
            .clk(clk), .rst_n(rst_n), .start(ordered_valid),
            .count(raw_count), .frame_done(frame_done)
        );

        // Map directly to outputs. 
        assign out_r = ordered_r;
        assign out_i = ordered_i;
        assign valid_out = ordered_valid;
        assign out_index = raw_count;

    end 
    else 
    begin : gen_scrambled_path
        /*ORDERED_OUTPUT=0 means we want the output directly (srambled) so we doesn't need to call the bit_reversal module*/

        valid_out_gen #(.FRAME_SIZE(NUMBER_OF_POINTS)) valid_gen_u0(
            .clk(clk), .rst_n(rst_n), .start(valid_out12_synced),
            .count(raw_count), .frame_done(frame_done)
        );

        // Map directly to outputs. 
        assign out_r = stg12_r;
        assign out_i = stg12_i;
        assign valid_out = valid_out12_synced;
        assign out_index = {raw_count[0], raw_count[1], raw_count[2],raw_count[3], raw_count[4], raw_count[5],raw_count[6], raw_count[7], raw_count[8],raw_count[9], raw_count[10], raw_count[11]};

    end
endgenerate
endmodule