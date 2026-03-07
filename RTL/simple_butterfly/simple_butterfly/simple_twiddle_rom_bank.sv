module simple_twiddle_rom_bank #(
    parameter CWIDTH = 16,
    parameter DEPTH  = 2048
)(
    input  wire clk_i,
    input  wire clk_en_i,
    input  wire [10:0] index_i,
    output reg  [(2*CWIDTH-1):0] twiddle_o
);

reg [(2*CWIDTH-1):0] rom [0:DEPTH-1];

initial begin
    $readmemh("/home/icpedia/GP/sim/twiddles/twiddle_4096.hex", rom);
end


always @(posedge clk_i)
if(clk_en_i)
    twiddle_o <= rom[index_i];

endmodule
