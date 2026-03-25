module fft_sdf_stg #(
    parameter FIFO_DEPTH = 4, DATA_WIDTH = 12
)(
    input  wire clk, rst_n, valid_in, frame_done,
    input  wire signed [DATA_WIDTH-1: 0] in_r, in_i,
    output wire signed [DATA_WIDTH-1: 0] stg_out_r, stg_out_i,
    output wire                          fill_done , 
    output wire  valid_out
);


wire fifo_mux_sel, out_mux_sel, bf_en, rot_en;
wire [$clog2(FIFO_DEPTH)-1: 0] twiddle_sel;
wire signed [DATA_WIDTH-1:0] fifo_in_r, fifo_in_i;
wire signed [DATA_WIDTH-1:0] fifo_out_r, fifo_out_i;
wire signed [DATA_WIDTH-1:0] bf_sum_r, bf_sum_i;
wire signed [DATA_WIDTH-1:0] bf_diff_r, bf_diff_i;
wire signed [DATA_WIDTH-1: 0] out_r, out_i;
wire signed [DATA_WIDTH-1: 0] comb_stg_out_r, comb_stg_out_i;


fft_fifo #(.FIFO_DEPTH(FIFO_DEPTH), .DATA_WIDTH(DATA_WIDTH)) fifo_u0(
.clk(clk),
.rst_n(rst_n),
.in_r(fifo_in_r),
.in_i(fifo_in_i),
.out_r(fifo_out_r),
.out_i(fifo_out_i)
);


fft_butterfly_unit #(.DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(FIFO_DEPTH)) bf_u0(
.en(bf_en),
.a_r(fifo_out_r),
.a_i(fifo_out_i),
.b_r(in_r),
.b_i(in_i),
.sum_r(bf_sum_r),
.sum_i(bf_sum_i),
.diff_r(bf_diff_r),
.diff_i(bf_diff_i)
);


fft_stg_fsm #(.FIFO_DEPTH(FIFO_DEPTH)) fsm_u0(
.clk(clk),
.rst_n(rst_n),
.valid_in(valid_in),
.fifo_mux_sel(fifo_mux_sel),
.out_mux_sel(out_mux_sel),
.bf_en(bf_en),
.rot_en(rot_en),
.fill_done(fill_done),
.twiddle_sel(twiddle_sel),
.frame_done(frame_done),
.valid_out(valid_out)
);


fft_stg_mux #(.DATA_WIDTH(DATA_WIDTH)) fifo_mux_u0_r (
    .sel(fifo_mux_sel),
    .in0(bf_diff_r),
    .in1(in_r),
    .out(fifo_in_r)
);

fft_stg_mux #(.DATA_WIDTH(DATA_WIDTH)) fifo_mux_u0_i (
    .sel(fifo_mux_sel),
    .in0(bf_diff_i),
    .in1(in_i),
    .out(fifo_in_i)
);

fft_stg_mux #(.DATA_WIDTH(DATA_WIDTH)) out_mux_u0_r (
    .sel(out_mux_sel),
    .in0(fifo_out_r),
    .in1(bf_sum_r),
    .out(out_r)
);

fft_stg_mux #(.DATA_WIDTH(DATA_WIDTH)) out_mux_u0_i (
    .sel(out_mux_sel),
    .in0(fifo_out_i),
    .in1(bf_sum_i),
    .out(out_i)
);


generate
    if(FIFO_DEPTH != 1) begin
        fft_rotator #(.DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(FIFO_DEPTH)) rotator_u0 (
            .in_r(out_r),
            .in_i(out_i),
            .rot_en(rot_en),
            .twiddle_sel(twiddle_sel),
            .out_r(stg_out_r),
            .out_i(stg_out_i)
        );
  
    end
    else begin
        fft_dff #(.DATA_WIDTH(DATA_WIDTH)) stg_out_r_ff_u0(
        .clk(clk),
        .rst_n(rst_n),
        .in(out_r),
        .out(stg_out_r)
        );

        fft_dff #(.DATA_WIDTH(DATA_WIDTH)) stg_out_i_ff_u0(
        .clk(clk),
        .rst_n(rst_n),
        .in(out_i),
        .out(stg_out_i)
        );
    end

endgenerate




endmodule