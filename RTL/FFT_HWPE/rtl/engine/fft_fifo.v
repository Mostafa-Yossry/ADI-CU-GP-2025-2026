module fft_fifo #(
    parameter FIFO_DEPTH = 2,
    parameter DATA_WIDTH = 12
)(
    input  wire clk, rst_n,
    input  wire signed [DATA_WIDTH-1:0] in_r, in_i,
    output wire signed [DATA_WIDTH-1:0] out_r, out_i
);

    // shift registers for real and imag
    reg signed [DATA_WIDTH-1:0] fifo_reg_r [0:FIFO_DEPTH-1];
    reg signed [DATA_WIDTH-1:0] fifo_reg_i [0:FIFO_DEPTH-1];

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(k=0; k<FIFO_DEPTH; k=k+1) begin
                fifo_reg_r[k] <= '0;
                fifo_reg_i[k] <= '0;
            end
            // out_r <= 'd0;
            // out_i <= 'd0;
        end
        else begin
            // shift
            for(k=FIFO_DEPTH-1; k>0; k=k-1) begin
                fifo_reg_r[k] <= fifo_reg_r[k-1];
                fifo_reg_i[k] <= fifo_reg_i[k-1];
            end
            // out_r <= fifo_reg_r[FIFO_DEPTH-1];
            // out_i <= fifo_reg_i[FIFO_DEPTH-1];
            fifo_reg_r[0] <= in_r;
            fifo_reg_i[0] <= in_i;
        end
    end

    // output = last stage
    assign out_r = fifo_reg_r[FIFO_DEPTH-1];
    assign out_i = fifo_reg_i[FIFO_DEPTH-1];

endmodule
