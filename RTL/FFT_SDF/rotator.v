module rotator #(
    parameter DATA_WIDTH       = 12,
    parameter FIFO_DEPTH       = 4,
    parameter NUMBER_OF_POINTS = 4096
)(
    input  wire                              rot_en,
    input  wire [$clog2(FIFO_DEPTH)-1:0]     twiddle_sel,
    input  wire signed [DATA_WIDTH:0]        in_r,
    input  wire signed [DATA_WIDTH:0]        in_i,
    output reg  signed [2*DATA_WIDTH+1:0]    temp_mult_out_r, temp_mult_out_i
);

    // -----------------------------------------------------------------------
    // Address generation for the Twiddle ROM
    // index = twiddle_sel * ((N/2) / FIFO_DEPTH)
    // -----------------------------------------------------------------------
    wire [10:0] tw_idx;   // 11 bits covers 0..2047
    assign tw_idx = twiddle_sel * ((NUMBER_OF_POINTS/2) / FIFO_DEPTH);

    // Wires to connect ROM outputs
    wire signed [DATA_WIDTH-1:0] tw_w_re;
    wire signed [DATA_WIDTH-1:0] tw_w_im;

    // -----------------------------------------------------------------------
    // Twiddle ROM Instantiation
    // -----------------------------------------------------------------------
    twiddle_rom #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_twiddle_rom (
        .addr  (tw_idx),
        .tw_re (tw_w_re),
        .tw_im (tw_w_im)
    );

    // -----------------------------------------------------------------------
    // Complex Multiplication Logic
    // -----------------------------------------------------------------------
    reg signed [2*DATA_WIDTH:0] mult_rr, mult_ii, mult_ri, mult_ir;

    always @(*) begin
        if (rot_en) begin
            mult_rr         = in_r * tw_w_re;
            mult_ii         = in_i * tw_w_im;
            mult_ri         = in_r * tw_w_im;
            mult_ir         = in_i * tw_w_re;
            temp_mult_out_r = mult_rr - mult_ii;
            temp_mult_out_i = mult_ri + mult_ir;
        end else begin
            mult_rr         = 0;
            mult_ii         = 0;
            mult_ri         = 0;
            mult_ir         = 0;
            temp_mult_out_r = 0;
            temp_mult_out_i = 0;
        end
    end

endmodule