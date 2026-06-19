// ============================================================
// Module      : complex_adder
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// Description : Smart Parameterized Complex Adder (Q-format)
//               Dynamically aligns fractions before addition,
//               then shifts to the target output fraction.
//
// Rounding methods (parameter ROUNDING_METHOD):
//   "FLOOR"       — arithmetic right shift (truncation toward -inf).
//                   Fast, zero hardware overhead.
//   "CONVERGENT"  — round-half-to-even (banker's rounding).
//                   Eliminates systematic bias at half-points.
//                   Hardware: round_bit & (sticky_bit | lsb) adder.
//
// Convergent rounding rule for right-shift by S bits:
//   round_bit  = sum[S-1]          half-point indicator
//   sticky_bit = |sum[S-2:0]       any energy below half-point
//   lsb        = (sum >>> S)[0]    LSB of the truncated result
//   round_up   = round_bit & (sticky_bit | lsb)
//   result     = (sum >>> S) + round_up
//
// Note: rounding only applies when SHIFT_OUT_R > 0.
//       Left shifts and no-shift cases are identical for both methods.
// ============================================================  

module complex_adder #(
           parameter WIDTH              = 16            ,
           parameter FB_IN1             = 12            ,
           parameter FB_IN2             = 12            ,
           parameter FB_OUT             = 12            ,
           parameter ROUNDING_METHOD    = "CONVERGENT"  // "FLOOR" or "CONVERGENT"
)(                    
    // Input A (Complex)
    input  wire signed [WIDTH-1:0] a_re                 ,
    input  wire signed [WIDTH-1:0] a_im                 ,
        
    // Input B (Complex)                       
    input  wire signed [WIDTH-1:0] b_re                 ,
    input  wire signed [WIDTH-1:0] b_im                 ,
        
    // Output Sum (Complex)        
    output reg  signed [WIDTH-1:0] sum_re               ,
    output reg  signed [WIDTH-1:0] sum_im
);
/*...........................................Local Parameters..................................................*/
    
    // -----------------------------------------------------------------------------
    // Stage 1: Dynamic Alignment to the Highest Fractional Precision (Parameters)
    // -----------------------------------------------------------------------------
    
    localparam MAX_FB    = (FB_IN1 > FB_IN2)   ? FB_IN1  : FB_IN2           ; 
    localparam SHIFT_A   = MAX_FB - FB_IN1                                  ;
    localparam SHIFT_B   = MAX_FB - FB_IN2                                  ;
    localparam MAX_SHIFT = (SHIFT_A > SHIFT_B) ? SHIFT_A : SHIFT_B          ;
    localparam EXT_W     = WIDTH + MAX_SHIFT + 1                            ;

    // -----------------------------------------------------------------------------
    // Stage 2: Target Output Formatting (Quantization)                (Parameters)
    // -----------------------------------------------------------------------------

    localparam SHIFT_OUT_R = (MAX_FB > FB_OUT) ? (MAX_FB - FB_OUT) : 0      ;
    localparam SHIFT_OUT_L = (FB_OUT > MAX_FB) ? (FB_OUT - MAX_FB) : 0      ;


/*...........................................Interal Signals..................................................*/
    
    // -----------------------------------------------------------------------------
    // Stage 1: Dynamic Alignment to the Highest Fractional Precision (signals)
    // -----------------------------------------------------------------------------

    reg signed [EXT_W-1:0] a_re_ext   , a_im_ext                            ;
    reg signed [EXT_W-1:0] b_re_ext   , b_im_ext                            ;
    reg signed [EXT_W-1:0] sum_re_full, sum_im_full                         ;

    // -----------------------------------------------------------------------------
    // Stage 2: Target Output Formatting (Quantization)               (signals)
    // -----------------------------------------------------------------------------
    // ----------------------------------------------------------------
    // Convergent rounding helper signals
    // Only meaningful when SHIFT_OUT_R > 0.
    //
    // round_bit  : the MSB of the dropped bits (the "half" bit)
    // sticky_bit : OR of all bits below round_bit (any sub-half energy)
    // lsb_re/im  : LSB of the floor-shifted result
    // round_up   : 1-bit flag — add 1 to the floor result
    // ----------------------------------------------------------------

    wire round_bit_re  , round_bit_im                                       ;
    wire sticky_bit_re , sticky_bit_im                                      ;
    wire lsb_re        , lsb_im                                             ;
    wire round_up_re   , round_up_im                                        ;

/*...........................................Interal Logic..................................................*/
    // -----------------------------------------------------------------------------
    // Stage 1: Dynamic Alignment to the Highest Fractional Precision 
    // -----------------------------------------------------------------------------
    
    always @(*) begin
        a_re_ext = $signed(a_re) <<< SHIFT_A    ;
        a_im_ext = $signed(a_im) <<< SHIFT_A    ;
        b_re_ext = $signed(b_re) <<< SHIFT_B    ;
        b_im_ext = $signed(b_im) <<< SHIFT_B    ;

        sum_re_full = a_re_ext + b_re_ext       ;
        sum_im_full = a_im_ext + b_im_ext       ;
    end

    // -----------------------------------------------------------------------------
    // Stage 2: Target Output Formatting (Quantization)
    // -----------------------------------------------------------------------------

    generate
        if (SHIFT_OUT_R > 0) begin : gen_round_signals

            // round_bit = sum[SHIFT_OUT_R - 1]
            assign round_bit_re = sum_re_full[SHIFT_OUT_R - 1]          ;
            assign round_bit_im = sum_im_full[SHIFT_OUT_R - 1]          ;

            if (SHIFT_OUT_R > 1) begin : gen_sticky
                // sticky_bit = OR of sum[SHIFT_OUT_R-2 : 0]
                assign sticky_bit_re = |sum_re_full[SHIFT_OUT_R-2:0]    ;
                assign sticky_bit_im = |sum_im_full[SHIFT_OUT_R-2:0]    ;
            end 
            else begin : gen_no_sticky
                // Only 1 bit being dropped — no bits below round_bit
                assign sticky_bit_re = 1'b0                             ;
                assign sticky_bit_im = 1'b0                             ;
            end

            // lsb = bit 0 of the floor-shifted result
            assign lsb_re = sum_re_full[SHIFT_OUT_R]                    ;
            assign lsb_im = sum_im_full[SHIFT_OUT_R]                    ;

            // round_up = round_bit & (sticky_bit | lsb)
            assign round_up_re = round_bit_re & (sticky_bit_re | lsb_re);
            assign round_up_im = round_bit_im & (sticky_bit_im | lsb_im);

        end 
        else begin : gen_no_round
            assign round_bit_re  = 1'b0                                 ;
            assign round_bit_im  = 1'b0                                 ;
            assign sticky_bit_re = 1'b0                                 ;
            assign sticky_bit_im = 1'b0                                 ;
            assign lsb_re        = 1'b0                                 ;
            assign lsb_im        = 1'b0                                 ;
            assign round_up_re   = 1'b0                                 ;
            assign round_up_im   = 1'b0                                 ;
        end
    endgenerate

    // ----------------------------------------------------------------
    // Output mux: FLOOR vs CONVERGENT
    // ----------------------------------------------------------------
    always @(*) begin
        if (SHIFT_OUT_R > 0) begin
            if (ROUNDING_METHOD == "CONVERGENT") begin
                // Convergent: floor result + round_up
                sum_re = (sum_re_full >>> SHIFT_OUT_R) + {{(WIDTH-1){1'b0}}, round_up_re};
                sum_im = (sum_im_full >>> SHIFT_OUT_R) + {{(WIDTH-1){1'b0}}, round_up_im};
            end 
            else begin
                // FLOOR: arithmetic right shift (truncation)
                sum_re = sum_re_full >>> SHIFT_OUT_R                                     ;
                sum_im = sum_im_full >>> SHIFT_OUT_R                                     ;
            end
        end 
        else if (SHIFT_OUT_L > 0) begin
            // Left shift — rounding method makes no difference here
            sum_re = sum_re_full <<< SHIFT_OUT_L                                         ;
            sum_im = sum_im_full <<< SHIFT_OUT_L                                         ;
        end 
        else begin
            // No shift needed
            sum_re = sum_re_full[WIDTH-1:0]                                              ;
            sum_im = sum_im_full[WIDTH-1:0]                                              ;
        end
    end

endmodule