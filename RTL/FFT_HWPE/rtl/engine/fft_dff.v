module fft_dff #(
    parameter DATA_WIDTH = 1
)(
    input wire clk, rst_n,
    input wire [DATA_WIDTH-1: 0] in,
    output reg [DATA_WIDTH-1 :0] out
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        out <= 'd0;
    end
    else begin
        out <= in;
    end
end
    
endmodule