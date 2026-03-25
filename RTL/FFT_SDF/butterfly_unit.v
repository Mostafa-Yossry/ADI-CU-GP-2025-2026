module butterfly_unit #(parameter DATA_WIDTH=12, FIFO_DEPTH = 4) (
    input  wire                         en,
    input  wire signed [DATA_WIDTH:0] a_r, a_i,
    input  wire signed [DATA_WIDTH:0] b_r, b_i,
    output reg signed  [DATA_WIDTH:0] inter_sum_r, inter_sum_i,inter_diff_r,inter_diff_i
);

/*add and subtracte in 13 bits to make a delayed quantization*/

always @(*) begin
    if(en) begin
        inter_sum_r  = a_r + b_r;
        inter_sum_i  = a_i + b_i;
        inter_diff_r = a_r - b_r;
        inter_diff_i = a_i - b_i;
    end
    else begin
        inter_sum_r  = 0;
        inter_sum_i  = 0;
        inter_diff_r = 0;
        inter_diff_i = 0;
    end
end


endmodule
