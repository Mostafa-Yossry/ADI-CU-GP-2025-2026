module fft_modulo_N_counter #(
    parameter N = 2
)(
    input  wire clk,
    input  wire count_en,
    input  wire rst_n,
    output wire count_done,
    output reg  [$clog2(N)-1:0] count
);

assign count_done = (count == N-1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        count <= 0;
    end
    else if (count_en && !count_done) begin
        count <= count + 'b1;
    end
    else if(count_en && count_done) begin
        count <= 'b0;
    end
end

endmodule
