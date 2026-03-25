module fft8_dif #(
    parameter DATA_WIDTH = 12
)(
    input  wire clk, rst_n, valid_in,
    input  wire signed [DATA_WIDTH-1: 0] in_r, in_i,
    output wire signed [DATA_WIDTH-1: 0] out_r, out_i,
    output wire                          valid_out,frame_done,
    output wire [2:0]                    out_index
);

wire signed [DATA_WIDTH-1: 0] stg1_r,stg1_i;
wire signed [DATA_WIDTH-1: 0] stg2_r,stg2_i;
wire signed [DATA_WIDTH-1: 0] stg3_r,stg3_i;

wire stg1_fill_done, stg2_fill_done, stg3_fill_done;
wire valid_out1,valid_out2,valid_out3;
wire frame_done_dff;
wire [2:0] raw_count;

fft_sdf_stg #(.FIFO_DEPTH(4), .DATA_WIDTH(DATA_WIDTH)) fft_stg1 (
.clk(clk),
.rst_n(rst_n),
.valid_in(valid_in),
.in_r(in_r),
.in_i(in_i),
.stg_out_r(stg1_r),
.stg_out_i(stg1_i),
.fill_done(stg1_fill_done),
.frame_done(frame_done),
.valid_out(valid_out1)
);

fft_sdf_stg #(.FIFO_DEPTH(2), .DATA_WIDTH(DATA_WIDTH)) fft_stg2 (
.clk(clk),
.rst_n(rst_n),
.valid_in(valid_out1),
.in_r(stg1_r),
.in_i(stg1_i),
.stg_out_r(stg2_r),
.stg_out_i(stg2_i),
.fill_done(stg2_fill_done),
.frame_done(frame_done),
.valid_out(valid_out2)
);


fft_sdf_stg #(.FIFO_DEPTH(1), .DATA_WIDTH(DATA_WIDTH)) fft_stg3 (
.clk(clk),
.rst_n(rst_n),
.valid_in(valid_out2),
.in_r(stg2_r),
.in_i(stg2_i),
.stg_out_r(out_r),
.stg_out_i(out_i),
.fill_done(stg3_fill_done),
.frame_done(frame_done),
.valid_out(valid_out3)
);

// // valid out logic
fft_valid_out_gen valid_gen_u0 (
    .clk(clk),
    .rst_n(rst_n),
    .start(valid_out3),
    .count(raw_count),
    .frame_done(frame_done_dff)
);

fft_dff #(.DATA_WIDTH(1)) valid_out_delay(
.clk(clk),
.rst_n(rst_n),
.in(valid_out3),
.out(valid_out)
);

fft_dff #(.DATA_WIDTH(1)) frame_done_delay(
.clk(clk),
.rst_n(rst_n),
.in(frame_done_dff),
.out(frame_done)
);

assign out_index = {raw_count[0], raw_count[1], raw_count[2]};
endmodule