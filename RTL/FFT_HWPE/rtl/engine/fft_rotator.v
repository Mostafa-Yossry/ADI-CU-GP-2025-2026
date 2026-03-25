module fft_rotator #(
    parameter DATA_WIDTH = 12, 
    parameter FIFO_DEPTH = 4
)(
    input  wire                                  rot_en,
    input  wire        [$clog2(FIFO_DEPTH)-1: 0] twiddle_sel, 
    input  wire signed [DATA_WIDTH-1:0]          in_r,
    input  wire signed [DATA_WIDTH-1:0]          in_i,
    output wire signed [DATA_WIDTH-1:0]          out_r,
    output wire signed [DATA_WIDTH-1:0]          out_i
);

    // -------------------------------
    // Twiddles for 8-pt DIF FFT (Q2.10, 12-bit signed)
    // W0 =  1.000 + j0.000  => Re: 0x400, Im: 0x000
    // W1 =  0.707 - j0.707  => Re: 0x2D4, Im: 0xD2C
    // W2 =  0.000 - j1.000  => Re: 0x000, Im: 0xC00
    // W3 = -0.707 - j0.707  => Re: 0xD2C, Im: 0xD2C
    // -------------------------------
    localparam signed [DATA_WIDTH-1:0] W0_RE = 12'h400;  // +1.000
    localparam signed [DATA_WIDTH-1:0] W0_IM = 12'h000;  // +j0.000

    localparam signed [DATA_WIDTH-1:0] W1_RE = 12'h2D4;  // Floor(724.07)  = 724
    localparam signed [DATA_WIDTH-1:0] W1_IM = 12'hD2B;  // Floor(-724.07) = -725 (D2B)

    localparam signed [DATA_WIDTH-1:0] W2_RE = 12'h000;  
    localparam signed [DATA_WIDTH-1:0] W2_IM = 12'hC00;  

    localparam signed [DATA_WIDTH-1:0] W3_RE = 12'hD2B;  // Floor(-724.07) = -725 (D2B)
    localparam signed [DATA_WIDTH-1:0] W3_IM = 12'hD2B;  // Floor(-724.07) = -725 (D2B)


    // Internal multiplication results
    reg signed [2*DATA_WIDTH-1:0] mult_rr, mult_ii, mult_ri, mult_ir;
    reg signed [2*DATA_WIDTH:0]   temp_mult_out_r, temp_mult_out_i;
    reg signed [DATA_WIDTH-1:0]   mult_out_r, mult_out_i;


generate
    if(FIFO_DEPTH == 2) begin
        always @(*) begin
            case (twiddle_sel)
                1'd0: begin
                    mult_rr = in_r * W0_RE;
                    mult_ii = in_i * W0_IM;
                    mult_ri = in_r * W0_IM;
                    mult_ir = in_i * W0_RE;
                    temp_mult_out_r = (mult_rr - mult_ii);
                    temp_mult_out_i = (mult_ri + mult_ir);
                    mult_out_r = temp_mult_out_r >>> 10;
                    mult_out_i = temp_mult_out_i >>> 10;
                end
                1'd1: begin
                    mult_rr = in_r * W2_RE;
                    mult_ii = in_i * W2_IM;
                    mult_ri = in_r * W2_IM;
                    mult_ir = in_i * W2_RE;
                    temp_mult_out_r = (mult_rr - mult_ii);
                    temp_mult_out_i = (mult_ri + mult_ir);
                    mult_out_r = temp_mult_out_r >>> 10;
                    mult_out_i = temp_mult_out_i >>> 10;
                end
            endcase
        end        
    end
    else begin
        always @(*) begin
            case (twiddle_sel)
                2'd0: begin
                    mult_rr = in_r * W0_RE;
                    mult_ii = in_i * W0_IM;
                    mult_ri = in_r * W0_IM;
                    mult_ir = in_i * W0_RE;
                    temp_mult_out_r = (mult_rr - mult_ii);
                    temp_mult_out_i = (mult_ri + mult_ir);
                    mult_out_r = temp_mult_out_r >>> 11;
                    mult_out_i = temp_mult_out_i >>> 11;
                end
                2'd1: begin
                    mult_rr = in_r * W1_RE;
                    mult_ii = in_i * W1_IM;
                    mult_ri = in_r * W1_IM;
                    mult_ir = in_i * W1_RE;
                    temp_mult_out_r = (mult_rr - mult_ii);
                    temp_mult_out_i = (mult_ri + mult_ir);
                    mult_out_r = temp_mult_out_r >>> 11;
                    mult_out_i = temp_mult_out_i >>> 11;
                end
                2'd2: begin
                    mult_rr = in_r * W2_RE;
                    mult_ii = in_i * W2_IM;
                    mult_ri = in_r * W2_IM;
                    mult_ir = in_i * W2_RE;
                    temp_mult_out_r = (mult_rr - mult_ii);
                    temp_mult_out_i = (mult_ri + mult_ir);
                    mult_out_r = temp_mult_out_r >>> 11;
                    mult_out_i = temp_mult_out_i >>> 11;
                end
                2'd3: begin
                    mult_rr = in_r * W3_RE;
                    mult_ii = in_i * W3_IM;
                    mult_ri = in_r * W3_IM;
                    mult_ir = in_i * W3_RE;
                    temp_mult_out_r = (mult_rr - mult_ii);
                    temp_mult_out_i = (mult_ri + mult_ir);
                    mult_out_r = temp_mult_out_r >>> 11;
                    mult_out_i = temp_mult_out_i >>> 11;
                end
            endcase
        end        
    end
endgenerate


    // bypass if rot_en=0
    assign out_r = rot_en ? mult_out_r : (FIFO_DEPTH==4) ? (in_r>>>1) : in_r; 
    assign out_i = rot_en ? mult_out_i : (FIFO_DEPTH==4) ? (in_i>>>1) : in_i;  

endmodule
