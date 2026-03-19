module bit_reversal_complex #(
    parameter DATA_WIDTH = 12,
    parameter FFT_POINTS = 8    // <-- NEW: Set this to any power of 2
)(
    input  wire                          clk,
    input  wire                          rst_n,      
    input  wire                          valid_in,  
    input  wire signed [DATA_WIDTH-1:0]  in_r,   
    input  wire signed [DATA_WIDTH-1:0]  in_i,   
    
    output reg                           valid_out, 
    output reg  signed [DATA_WIDTH-1:0]  out_r,   
    output reg  signed [DATA_WIDTH-1:0]  out_i    
);

    // Automatically calculate the number of bits needed for the counter
    localparam FFT_STAGES = $clog2(FFT_POINTS);

    reg [FFT_STAGES-1:0] count;
    reg                  ping_pong_state; // it determined which ram reads and which writes  
    reg                  first_block_done; // to prevent the garbage in the first frame 

    // --- The Generalized Address Flipper ---
    reg [FFT_STAGES-1:0] reversed_count; // to store the output in ordered indexed in the RAM
    integer i;
    
    always @(*) begin
        for (i = 0; i < FFT_STAGES; i = i + 1) begin
            // Wire the Most Significant Bits to the Least Significant Bits
            reversed_count[i] = count[FFT_STAGES - 1 - i];
        end
    end
    
    wire [FFT_STAGES-1:0] write_addr = reversed_count; 
    wire [FFT_STAGES-1:0] read_addr  = count; 

    // Complex RAM arrays dynamically sized by FFT_POINTS
    reg signed [DATA_WIDTH-1:0] ram_A_r [0:FFT_POINTS-1];
    reg signed [DATA_WIDTH-1:0] ram_A_i [0:FFT_POINTS-1];
    reg signed [DATA_WIDTH-1:0] ram_B_r [0:FFT_POINTS-1];
    reg signed [DATA_WIDTH-1:0] ram_B_i [0:FFT_POINTS-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count            <= 0;
            ping_pong_state  <= 1'b0;
            first_block_done <= 1'b0;
            valid_out        <= 1'b0;
            out_r            <= 0;
            out_i            <= 0;
        end else if (valid_in) begin
            count <= count + 1;
            
            // a dynamic check instead of 11111..
            if (count == FFT_POINTS - 1) begin
                ping_pong_state  <= ~ping_pong_state; 
                first_block_done <= 1'b1;             
            end

            // Input Switch (Writing Scrambled Data)
            if (ping_pong_state == 1'b0) begin
                ram_A_r[write_addr] <= in_r; 
                ram_A_i[write_addr] <= in_i;
            end else begin
                ram_B_r[write_addr] <= in_r; 
                ram_B_i[write_addr] <= in_i;
            end

            // Output Switch (Reading Sorted Data)
            if (first_block_done) begin
                valid_out <= 1'b1;
                if (ping_pong_state == 1'b0) begin
                    out_r <= ram_B_r[read_addr];
                    out_i <= ram_B_i[read_addr];
                end else begin
                    out_r <= ram_A_r[read_addr];
                    out_i <= ram_A_i[read_addr];
                end
            end
        end else begin
            valid_out <= 1'b0; 
        end
    end
endmodule