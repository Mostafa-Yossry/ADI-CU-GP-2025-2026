// ==============================================================================
// MODULE: twiddle_rom_radix8
// PURPOSE: Fetches 7 Twiddle factors simultaneously for Radix-8 DIF FFT.
// LATENCY: 1 Clock Cycle
// ==============================================================================
module twiddle_rom_radix8 #(
    parameter CWIDTH = 16,
    parameter DEPTH  = 2048
)(
    input  wire                    clk_i,
    input  wire                    clk_en_i,
    input  wire [10:0]             base_idx_i, // The base 'k' index
    output reg  [(7*2*CWIDTH-1):0] twiddles_o  // Packed {W7, W6, ..., W1}
);

    // Define the ROM memory. 
    // By reading from 7 different addresses simultaneously below, 
    // the synthesis tool will automatically infer 7 separate ROM blocks.
    reg [(2*CWIDTH-1):0] rom [0:DEPTH-1];

    initial begin
        $readmemh("twiddle_4096.hex", rom);
    end

    // ---------------------------------------------------------
    // INDEX CALCULATION (Combinational)
    // ---------------------------------------------------------
    // In Radix-8, if the base index is 'k', we need k, 2k, 3k... 7k.
    // Because DEPTH is 2048 (which is exactly 2^11), letting the multiplication 
    // naturally overflow a 11-bit wire perfectly calculates the modulo! 
    // e.g., (k * 7) % 2048 is inherently handled by the [10:0] bit-width.
    
    wire [10:0] idx1 = base_idx_i;
    wire [10:0] idx2 = base_idx_i << 1;     // k * 2
    wire [10:0] idx3 = base_idx_i * 3;      // k * 3
    wire [10:0] idx4 = base_idx_i << 2;     // k * 4
    wire [10:0] idx5 = base_idx_i * 5;      // k * 5
    wire [10:0] idx6 = base_idx_i * 6;      // k * 6
    wire [10:0] idx7 = base_idx_i * 7;      // k * 7

    // ---------------------------------------------------------
    // SYNCHRONOUS READ
    // ---------------------------------------------------------
    always @(posedge clk_i) begin
        if(clk_en_i) begin
            // Pack the outputs into the wide bus required by Stage 4
            twiddles_o <= {
                rom[idx7], 
                rom[idx6], 
                rom[idx5], 
                rom[idx4], 
                rom[idx3], 
                rom[idx2], 
                rom[idx1]
            };
        end
    end

endmodule