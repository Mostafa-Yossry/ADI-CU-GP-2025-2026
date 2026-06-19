// ============================================================
// Module      : div_complex_by_real
// Description : Divides a complex number (real + imaginary parts) by a single real
//               scalar. Instantiates two div_signed_pipelined_wrapper cores in
//               parallel — one for the real part and one for the imaginary part —
//               feeding both with the same real denominator. Because both paths share
//               the same pipeline depth and the same clock, their valid_out signals
//               are identical; only the real-part valid is forwarded to the output.
//               All fixed-point format parameters and ROUNDING_METHOD are passed
//               identically to both sub-dividers so the two parts always match.
//               Used inside pe_diagonal_complex to compute the reciprocal 1/L_kk
//               needed by the off-diagonal PEs.

// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================
module div_complex_by_real #(
           parameter                WIDTH           = 16                ,
           parameter                FB_NUM          = 12                ,
           parameter                FB_DEN          = 10                ,
           parameter                FB_OUT          = 11                ,
           parameter                ROUNDING_METHOD = "CONVERGENT"   // "FLOOR" or "CONVERGENT"

)(
    input  wire                     clk                                 ,
    input  wire                     rst                                 ,
    input  wire                     valid_in                            ,

    // Complex Numerator (e.g., from off-diagonal)                   
    input  wire signed [WIDTH-1:0]  num_re                              ,
    input  wire signed [WIDTH-1:0]  num_im                              ,

    // Real Denominator (e.g., from diagonal Sqrt)                   
    input  wire signed [WIDTH-1:0]  den_real                            ,

    output wire                     valid_out                           ,
    output wire signed [WIDTH-1:0]  quo_re                              ,
    output wire signed [WIDTH-1:0]  quo_im
);

/*...........................................Interal Signals..................................................*/
    wire valid_out_re, valid_out_im;
    
/*...........................................Submodules.......................................................*/

    // Real Part Division
    div_signed_pipelined_wrapper #(
            .WIDTH                      (              WIDTH               ),
            .FB_NUM                     (              FB_NUM              ),
            .FB_DEN                     (              FB_DEN              ),
            .FB_OUT                     (              FB_OUT              ),
            .ROUNDING_METHOD            (              ROUNDING_METHOD     )
    ) eq_div_re (
            .clk                        (              clk                 ),
            .rst                        (              rst                 ),
            .valid_in                   (              valid_in            ),
            .num_in                     (              num_re              ),
            .den_in                     (              den_real            ),
            .valid_out                  (              valid_out_re        ),
            .quo_out                    (              quo_re              )
    );

    // Imaginary Part Division
    div_signed_pipelined_wrapper #(
            .WIDTH                      (              WIDTH               ),
            .FB_NUM                     (              FB_NUM              ),
            .FB_DEN                     (              FB_DEN              ),
            .FB_OUT                     (              FB_OUT              ),
            .ROUNDING_METHOD            (              ROUNDING_METHOD     )
    ) eq_div_im (
            .clk                        (              clk                 ),
            .rst                        (              rst                 ),
            .valid_in                   (              valid_in            ),
            .num_in                     (              num_im              ),
            .den_in                     (              den_real            ),
            .valid_out                  (              valid_out_im        ),
            .quo_out                    (              quo_im              )
    );

    // Both finish at the same time, so we just use one valid_out
    assign valid_out = valid_out_re;

endmodule