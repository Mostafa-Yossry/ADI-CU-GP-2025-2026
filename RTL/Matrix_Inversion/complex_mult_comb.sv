// ============================================================
// Module      : complex_mult_comb
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// Description : Smart Parameterized Complex Multiplier (Q-format)
//               Dynamically aligns the output fractional bits
//               based on input and target fraction sizes.
//
// Rounding methods (parameter ROUNDING_METHOD):
//   "FLOOR"       — arithmetic right shift (truncation toward -inf).
//                   Fast, zero hardware overhead.
//   "CONVERGENT"  — round-half-to-even (banker's rounding).
//                   Eliminates systematic bias at half-points.
//
// Convergent rounding rule for right-shift by S bits:
//   round_bit  = result[S-1]       half-point indicator
//   sticky_bit = |result[S-2:0]    any energy below half-point
//   lsb        = (result >>> S)[0] LSB of the truncated result
//   round_up   = round_bit & (sticky_bit | lsb)
//   output     = (result >>> S) + round_up
//
// Note: rounding only applies when SHIFT_R > 0.
//       Left shifts and no-shift cases are identical for both methods.
// ============================================================  

module complex_mult_comb #(
           parameter WIDTH           = 16           ,
           parameter FB_IN1          = 8            ,
           parameter FB_IN2          = 8            ,
           parameter FB_OUT          = 11           ,
           parameter ROUNDING_METHOD = "CONVERGENT"  // "FLOOR" or "CONVERGENT"
)(
    input  wire signed [WIDTH-1:0]  a_re            ,
    input  wire signed [WIDTH-1:0]  a_im            , 
    input  wire signed [WIDTH-1:0]  b_re            , 
    input  wire signed [WIDTH-1:0]  b_im            ,

    output reg  signed [WIDTH-1:0]  res_re          ,
    output reg  signed [WIDTH-1:0]  res_im
);

/*...........................................Local Parameters..................................................*/
    
    // ----------------------------------------------------------------
    // Stage 3: Dynamic Shifting & Quantization     (Parameters)
    // ----------------------------------------------------------------

    localparam MULT_FBITS = FB_IN1 + FB_IN2                                             ;
    localparam SHIFT_R    = (MULT_FBITS > FB_OUT) ? (MULT_FBITS - FB_OUT) : 0           ;
    localparam SHIFT_L    = (FB_OUT > MULT_FBITS) ? (FB_OUT - MULT_FBITS) : 0           ;

/*...........................................Interal Signals..................................................*/
    // ----------------------------------------------------------------
    // Stage 1: Parallel Real Multiplications       (signals)
    // ----------------------------------------------------------------
    
    reg signed [2*WIDTH-1:0] ac, bd, ad, bc                                             ;
    reg signed [2*WIDTH  :0] real_mult, img_mult                                        ;
    
    // ----------------------------------------------------------------
    // Stage 3: Dynamic Shifting & Quantization     (signals)
    // ----------------------------------------------------------------
    // ----------------------------------------------------------------
    // Convergent rounding helper signals
    // Only meaningful when SHIFT_R > 0, otherwise tied to 0.
    //
    //   round_bit  : MSB of the dropped bits (the "half" bit)
    //   sticky_bit : OR of all bits below round_bit
    //   lsb        : LSB of the floor-shifted result
    //   round_up   : add 1 to the floor result
    // ----------------------------------------------------------------
    wire round_bit_re , round_bit_im                                                   ;  
    wire sticky_bit_re, sticky_bit_im                                                  ;
    wire lsb_re       , lsb_im                                                         ;
    wire round_up_re  , round_up_im                                                    ;
/*...........................................Interal Logic..................................................*/
    
    // ----------------------------------------------------------------
    // Stage 1: Parallel Real Multiplications 
    // ----------------------------------------------------------------
    always @(*) begin
        ac = a_re * b_re;
        bd = a_im * b_im;
        ad = a_re * b_im;
        bc = a_im * b_re;
    end

    // ----------------------------------------------------------------
    // Stage 2: Addition/Subtraction
    // ----------------------------------------------------------------
    always @(*) begin
        real_mult = $signed(ac) - $signed(bd);
        img_mult  = $signed(ad) + $signed(bc);
    end

    // ----------------------------------------------------------------
    // Stage 3: Dynamic Shifting & Quantization
    // ----------------------------------------------------------------

    generate
        if (SHIFT_R > 0) begin : gen_round_signals

            assign round_bit_re = real_mult[SHIFT_R - 1]                    ;
            assign round_bit_im = img_mult [SHIFT_R - 1]                    ;

            if (SHIFT_R > 1) begin : gen_sticky
                assign sticky_bit_re = |real_mult[SHIFT_R-2:0]              ;
                assign sticky_bit_im = |img_mult [SHIFT_R-2:0]              ;
            end 
            else begin : gen_no_sticky
                assign sticky_bit_re = 1'b0                                 ;
                assign sticky_bit_im = 1'b0                                 ;
            end

            assign lsb_re = real_mult[SHIFT_R]                              ;
            assign lsb_im = img_mult [SHIFT_R]                              ;

            assign round_up_re = round_bit_re & (sticky_bit_re | lsb_re)    ;
            assign round_up_im = round_bit_im & (sticky_bit_im | lsb_im)    ;

        end 
        else begin : gen_no_round
            assign round_bit_re  = 1'b0                                     ;
            assign round_bit_im  = 1'b0                                     ;
            assign sticky_bit_re = 1'b0                                     ;
            assign sticky_bit_im = 1'b0                                     ;
            assign lsb_re        = 1'b0                                     ;
            assign lsb_im        = 1'b0                                     ;
            assign round_up_re   = 1'b0                                     ;
            assign round_up_im   = 1'b0                                     ;
        end
    endgenerate

    // ----------------------------------------------------------------
    // Output mux: FLOOR vs CONVERGENT
    // ----------------------------------------------------------------
    always @(*) begin
        if (SHIFT_R > 0) begin
            if (ROUNDING_METHOD == "CONVERGENT") begin
                res_re = (real_mult >>> SHIFT_R) + {{(WIDTH-1){1'b0}}, round_up_re}     ;
                res_im = (img_mult  >>> SHIFT_R) + {{(WIDTH-1){1'b0}}, round_up_im}     ;
            end 
            else begin
                // FLOOR: arithmetic right shift (truncation)
                res_re = real_mult >>> SHIFT_R                                          ;
                res_im = img_mult  >>> SHIFT_R                                          ;
            end
        end 
        else if (SHIFT_L > 0) begin
            res_re = real_mult <<< SHIFT_L                                              ;
            res_im = img_mult  <<< SHIFT_L                                              ;
        end 
        else begin
            res_re = real_mult                                                          ;
            res_im = img_mult                                                           ;
        end
    end

endmodule