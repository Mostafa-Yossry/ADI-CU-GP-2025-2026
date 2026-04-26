// ==============================================================================
// MODULE: twiddle_rom_radix8 (OPTIMIZED WIDE-WORD)
// PURPOSE: Fetches 7 Twiddle factors simultaneously using exactly 1 Read Port.
// LATENCY: 1 Clock Cycle
// ==============================================================================
module twiddle_rom_radix8 #(
    parameter CWIDTH = 16,
    parameter DEPTH  = 512  // Dramatically reduced depth!
)(
    input  wire                    clk_i,
    input  wire                    clk_en_i,
    input  wire [8:0]              base_idx_i, // Only 9 bits needed for 512!
    output reg  [(7*2*CWIDTH-1):0] twiddles_o
);

    // A single, ultra-wide memory block.
    // Width: 224 bits. Depth: 512. 
    // Total Size: ~114 Kbits.
    // Synthesis will map this to ~3.5 Block RAM tiles with exactly 1 Read Port.
    reg [(7*2*CWIDTH-1):0] rom [0:DEPTH-1];

    initial begin
        $readmemh("/home/icpedia/GP/sim/twiddles/twiddle_packed_radix8.hex", rom);
    end

    // ---------------------------------------------------------
    // SYNCHRONOUS READ (Zero Combinational Logic)
    // ---------------------------------------------------------
    always @(posedge clk_i) begin
        if(clk_en_i) begin
            // The 224-bit word perfectly matches the w_coefs bus in Stage 4
            twiddles_o <= rom[base_idx_i];
        end
    end

endmodule
