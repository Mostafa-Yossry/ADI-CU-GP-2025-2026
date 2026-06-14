// ============================================================
// Module : pe_off_diagonal_complex  (CONFIGURABLE NxN VERSION)
// Description : The off-diagonal Processing Element (PE) for the systolic complex
//               Cholesky decomposition. Computes the complex L element at position
//               (row, col): L_ij = (G_ij - sum_{k<j} L_ik * conj(L_jk)) * inv_j.
//               Mirrors the MATLAB bit-true reference in three pipelined stages:
//               (1) MAC chain — N_PRIOR registered complex multiply-accumulate stages
//               compute the inner product sum(L_left * conj(L_top)). Each stage uses
//               complex_mult_comb with the conjugate applied by negating the b_im
//               input; the product is cast to FB_ACC_OFF via smart_round before
//               accumulation.
//               (2) Subtraction — G_ij and the accumulator are independently cast
//               to FB_SUB_OFF, then subtracted to form sub_off.
//               (3) Scaling — sub_off is multiplied by the real-valued inv (1/L_jj)
//               via complex_mult_comb to produce L_out.
//               After L_out is registered, the squared magnitude |L_out|^2 is
//               computed via a second complex_mult_comb and negated to form
//               a_diag_out, which is sent to the diagonal PE above on the valid_diag
//               strobe so it can accumulate the contribution to its own diagonal.
// Math   : 
//   1. acc_off = sum_{k=0}^{N_PRIOR-1} L_left[k]*conj(L_top[k])
//   2. sub_off = G_in - acc_off
//   3. L_out   = sub_off * L_inv
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================

module pe_off_diagonal_complex #(
           parameter                                             WIDTH           = 16                    ,
           parameter                                             FB_L            = 11                    ,
           parameter                                             FB_G            = 8                     ,   
           parameter                                             FB_PROD_OFF     = 13                    , 
           parameter                                             FB_ACC_OFF      = 10                    , 
           parameter                                             FB_SUB_OFF      = 12                    , 
           parameter                                             FB_INV          = 12                    ,
           parameter                                             FB_MAG2_OUT     = 12                    ,
           parameter                                             N_PRIOR         = 1                     ,
           parameter                                             ROUNDING_METHOD = "CONVERGENT" // "FLOOR" or "CONVERGENT"                   
)(                   
    input  wire                                                  clk                                     ,   
    input  wire                                                  rst                                     ,
    input  wire                                                  valid_in                                ,
                      
    input  wire signed [WIDTH-1:0]                               a_in_re                                 ,
    input  wire signed [WIDTH-1:0]                               a_in_im                                 ,
                      
    input  wire signed [(N_PRIOR > 0 ? N_PRIOR : 1)*WIDTH-1:0]   l_left_flat_re                          ,
    input  wire signed [(N_PRIOR > 0 ? N_PRIOR : 1)*WIDTH-1:0]   l_left_flat_im                          ,
    input  wire signed [(N_PRIOR > 0 ? N_PRIOR : 1)*WIDTH-1:0]   l_top_flat_re                           ,
    input  wire signed [(N_PRIOR > 0 ? N_PRIOR : 1)*WIDTH-1:0]   l_top_flat_im                           ,
 
    input  wire signed [WIDTH-1:0]           l_inv                                                       ,
 
    output reg                               valid_out                                                   ,
    output reg  signed [WIDTH-1:0]           l_out_re                                                    ,
    output reg  signed [WIDTH-1:0]           l_out_im                                                    ,
    output reg                               valid_diag                                                  ,
    output reg  signed [WIDTH-1:0]           a_diag_out
);

/*...........................................Local Parameters..................................................*/

    localparam STAGES = (N_PRIOR == 0) ? 1 : N_PRIOR;


    // ----------------------------------------------------------------
    // MATLAB STEP 2: sub_off = G(i,k) - acc_off    (Parameters)
    // Both casted to T.sub_off BEFORE subtraction
    // ----------------------------------------------------------------
    
    localparam SHIFT_G_SUB_R = (FB_G > FB_SUB_OFF)       ? (FB_G - FB_SUB_OFF)       : 0;
    localparam SHIFT_G_SUB_L = (FB_SUB_OFF > FB_G)       ? (FB_SUB_OFF - FB_G)       : 0;
    localparam SHIFT_A_SUB_R = (FB_ACC_OFF > FB_SUB_OFF) ? (FB_ACC_OFF - FB_SUB_OFF) : 0;
    localparam SHIFT_A_SUB_L = (FB_SUB_OFF > FB_ACC_OFF) ? (FB_SUB_OFF - FB_ACC_OFF) : 0;

/*...........................................Interal Signals..................................................*/

    // ----------------------------------------------------------------
    // Pipeline Registers                                 (Signals)
    // ----------------------------------------------------------------
    
    reg signed [WIDTH-1:0]   a_in_re_p [0:STAGES]              ;
    reg signed [WIDTH-1:0]   a_in_im_p [0:STAGES]              ;
                
    reg signed [WIDTH-1:0]   acc_re    [0:STAGES]              ;
    reg signed [WIDTH-1:0]   acc_im    [0:STAGES]              ;
                
    reg signed [WIDTH-1:0]   l_inv_p   [0:STAGES]              ;
    reg                      valid_p   [0:STAGES]              ;

    // ----------------------------------------------------------------
    // MATLAB STEP 2: sub_off = G(i,k) - acc_off          (Signals)
    // Both casted to T.sub_off BEFORE subtraction
    // ----------------------------------------------------------------
    
    wire signed [WIDTH-1:0] G_shifted_re   , G_shifted_im      ;
    wire signed [WIDTH-1:0] G_sub_re       , G_sub_im          ;
    wire signed [WIDTH-1:0] acc_shifted_re , acc_shifted_im    ;
    wire signed [WIDTH-1:0] acc_sub_re     , acc_sub_im        ;
    wire signed [WIDTH-1:0] sub_off_re     , sub_off_im        ;
    wire signed [WIDTH-1:0] l_wire_re_comb , l_wire_im_comb    ;

    // ----------------------------------------------------------------
    // MATLAB STEP 3: L_out = sub_off * L_inv             (Signals)
    // ----------------------------------------------------------------
    
    reg signed  [WIDTH-1:0] l_wire_re      , l_wire_im         ;
    reg                     valid_scale                        ;

    // ----------------------------------------------------------------
    // Square for diagonal contribution: -(|l_out|^2)     (Signals)
    // ----------------------------------------------------------------

    reg signed [WIDTH-1:0]   l_re_sq_stage, l_im_sq_stage      ;
    reg                      valid_sq                          ;

/*...........................................Internal Logic..................................................*/

    // Stage 0: Register inputs, Initialize Accumulator to 0
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            a_in_re_p[0]   <= 0        ;
            a_in_im_p[0]   <= 0        ;
            acc_re   [0]   <= 0        ;
            acc_im   [0]   <= 0        ;
            l_inv_p  [0]   <= 0        ;
            valid_p  [0]   <= 0        ;
        end 
        else begin      
            a_in_re_p[0]   <= a_in_re  ;
            a_in_im_p[0]   <= a_in_im  ; 
            acc_re   [0]   <= 0        ;      
            acc_im   [0]   <= 0        ;       
            l_inv_p  [0]   <= l_inv    ;
            valid_p  [0]   <= valid_in ;
        end
    end

    // ----------------------------------------------------------------
    // MATLAB STEP 1: MAC Chain (acc_off = sum(L * conj(L)))
    // ----------------------------------------------------------------
    genvar current_col_indx;
    generate
        for (current_col_indx = 0; current_col_indx < STAGES; current_col_indx = current_col_indx + 1) begin : gen_mac

            wire signed [WIDTH-1:0] ll_re = (current_col_indx < N_PRIOR) ? l_left_flat_re[current_col_indx *WIDTH +: WIDTH] : 0;
            wire signed [WIDTH-1:0] ll_im = (current_col_indx < N_PRIOR) ? l_left_flat_im[current_col_indx *WIDTH +: WIDTH] : 0;
            wire signed [WIDTH-1:0] lt_re = (current_col_indx < N_PRIOR) ? l_top_flat_re [current_col_indx *WIDTH +: WIDTH] : 0;
            wire signed [WIDTH-1:0] lt_im = (current_col_indx < N_PRIOR) ? l_top_flat_im [current_col_indx *WIDTH +: WIDTH] : 0;

            wire signed [WIDTH-1:0] p_re, p_im;

           
            complex_mult_comb #(
                    .WIDTH                (              WIDTH                    ), 
                    .FB_IN1               (              FB_L                     ),     
                    .FB_IN2               (              FB_L                     ),      
                    .FB_OUT               (              FB_PROD_OFF              ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
            ) eq_prod_off_mult (
                    .a_re                 (               ll_re                   ),
                    .a_im                 (               ll_im                   ),
                    .b_re                 (               lt_re                   ),
                    .b_im                 (               -lt_im                  ),    // Conjugate (Negative Imaginary)
                    .res_re               (               p_re                    ),
                    .res_im               (               p_im                    )
            );

            // MATLAB: acc_cast = cast(prod_off, 'like', T.acc_off)
            localparam SHIFT_ACC_R = (FB_PROD_OFF > FB_ACC_OFF) ? (FB_PROD_OFF - FB_ACC_OFF) : 0;
            localparam SHIFT_ACC_L = (FB_ACC_OFF > FB_PROD_OFF) ? (FB_ACC_OFF - FB_PROD_OFF) : 0;
            wire signed [WIDTH-1:0] p_re_shifted, p_im_shifted                                  ;     
            
            smart_round #(
                    .WIDTH                (              WIDTH                    ), 
                    .SHIFT                (              SHIFT_ACC_R              ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
            ) eq_rnd_mac_re (
                    .d_in                 (              p_re                     ),
                    .d_out                (              p_re_shifted             )
            );

            smart_round #(
                    .WIDTH                (              WIDTH                    ), 
                    .SHIFT                (              SHIFT_ACC_R              ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
            ) eq_rnd_mac_im (
                    .d_in                 (              p_im                     ),
                    .d_out                (              p_im_shifted             )
            );

            wire signed [WIDTH-1:0] prod_acc_re = (SHIFT_ACC_R > 0) ? p_re_shifted : (p_re <<< SHIFT_ACC_L);
            wire signed [WIDTH-1:0] prod_acc_im = (SHIFT_ACC_R > 0) ? p_im_shifted : (p_im <<< SHIFT_ACC_L);

            // MATLAB: acc_off = acc_off + acc_cast (Registered)
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    a_in_re_p[current_col_indx+1] <= 0                                                                                                  ;
                    a_in_im_p[current_col_indx+1] <= 0                                                                                                  ;
                    acc_re   [current_col_indx+1] <= 0                                                                                                  ;
                    acc_im   [current_col_indx+1] <= 0                                                                                                  ;
                    l_inv_p  [current_col_indx+1] <= 0                                                                                                  ;
                    valid_p  [current_col_indx+1] <= 0                                                                                                  ;
                end 
                else begin
                    a_in_re_p[current_col_indx+1] <= a_in_re_p[current_col_indx]                                                                        ; // Pass G through delay pipe
                    a_in_im_p[current_col_indx+1] <= a_in_im_p[current_col_indx]                                                                        ;
                    acc_re   [current_col_indx+1] <= (current_col_indx < N_PRIOR) ? (acc_re[current_col_indx] + prod_acc_re) : acc_re[current_col_indx] ;
                    acc_im   [current_col_indx+1] <= (current_col_indx < N_PRIOR) ? (acc_im[current_col_indx] + prod_acc_im) : acc_im[current_col_indx] ;
                    l_inv_p  [current_col_indx+1] <= l_inv_p[current_col_indx]                                                                          ;
                    valid_p  [current_col_indx+1] <= valid_p[current_col_indx]                                                                          ;
                end                             
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // MATLAB STEP 2: sub_off = G(i,k) - acc_off
    // Both casted to T.sub_off BEFORE subtraction
    // ----------------------------------------------------------------
    
    smart_round #(
                    .WIDTH                (              WIDTH                    ), 
                    .SHIFT                (              SHIFT_G_SUB_R            ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
    ) eq_rnd_g_re (
                    .d_in                 (              a_in_re_p[STAGES]        ),
                    .d_out                (              G_shifted_re             )
    );

    smart_round #(
                    .WIDTH                (              WIDTH                    ), 
                    .SHIFT                (              SHIFT_G_SUB_R            ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
    ) eq_rnd_g_im (
                    .d_in                 (              a_in_im_p[STAGES]        ),
                    .d_out                (              G_shifted_im             )
    );

    smart_round #(
                    .WIDTH                (              WIDTH                    ), 
                    .SHIFT                (              SHIFT_A_SUB_R            ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
    ) eq_rnd_sub_re (
                    .d_in                 (              acc_re[STAGES]           ),
                    .d_out                (              acc_shifted_re           )
    );
    
    smart_round #(
                    .WIDTH                (              WIDTH                    ), 
                    .SHIFT                (              SHIFT_A_SUB_R            ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
    ) eq_rnd_sub_im (
                    .d_in                 (              acc_im[STAGES]           ),
                    .d_out                (              acc_shifted_im           )
    );

    assign G_sub_re = (SHIFT_G_SUB_R > 0)   ? G_shifted_re   : (a_in_re_p[STAGES] <<< SHIFT_G_SUB_L) ;
    assign G_sub_im = (SHIFT_G_SUB_R > 0)   ? G_shifted_im   : (a_in_im_p[STAGES] <<< SHIFT_G_SUB_L) ;

    assign acc_sub_re = (SHIFT_A_SUB_R > 0) ? acc_shifted_re : (acc_re   [STAGES] <<< SHIFT_A_SUB_L) ;
    assign acc_sub_im = (SHIFT_A_SUB_R > 0) ? acc_shifted_im : (acc_im   [STAGES] <<< SHIFT_A_SUB_L) ;
    assign sub_off_re = G_sub_re - acc_sub_re                                                        ;
    assign sub_off_im = G_sub_im - acc_sub_im                                                        ;

    // ----------------------------------------------------------------
    // MATLAB STEP 3: L_out = sub_off * L_inv
    // ----------------------------------------------------------------

    //scaling
    complex_mult_comb #(
                    .WIDTH                (              WIDTH                    ), 
                    .FB_IN1               (              FB_SUB_OFF               ),
                    .FB_IN2               (              FB_INV                   ),
                    .FB_OUT               (              FB_L                     ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
    ) eq_scale_mult (            
                    .a_re                 (              sub_off_re               ),
                    .a_im                 (              sub_off_im               ),
                    .b_re                 (              l_inv_p[STAGES]          ),
                    .b_im                 (              {WIDTH{1'b0}}            ), // Real-only inverse
                    .res_re               (              l_wire_re_comb           ),
                    .res_im               (              l_wire_im_comb           )
    );


    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            l_wire_re   <= 0                ;
            l_wire_im   <= 0                ; 
            valid_scale <= 0                ;
        end
        else begin
            l_wire_re   <= l_wire_re_comb   ;
            l_wire_im   <= l_wire_im_comb   ;
            valid_scale <= valid_p[STAGES]  ;
        end
    end

    // ----------------------------------------------------------------
    // Square for diagonal contribution: -(|l_out|^2)
    // ----------------------------------------------------------------

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            l_re_sq_stage <= 0                       ;
            l_im_sq_stage <= 0                       ; 
            valid_sq      <= 0                       ;
        end 
        else begin
            // Result fraction = 2 * FB_L
            l_re_sq_stage <= l_wire_re               ;
            l_im_sq_stage <= l_wire_im               ;
            valid_sq      <= valid_scale             ;
        end
    end

    // Align squared magnitude to FB_mag2_out
    wire signed [WIDTH-1:0] mag2_re_comb, mag2_im_comb;

    complex_mult_comb #(
                    .WIDTH                (              WIDTH                    ), 
                    .FB_IN1               (              FB_L                     ),
                    .FB_IN2               (              FB_L                     ),
                    .FB_OUT               (              FB_MAG2_OUT              ),
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )
    ) eq_mag2_mult_inst (
                    .a_re                 (               l_re_sq_stage           ),
                    .a_im                 (               l_im_sq_stage           ),
                    .b_re                 (               l_re_sq_stage           ),
                    .b_im                 (               -l_im_sq_stage          ), 
                    .res_re               (               mag2_re_comb            ),   
                    .res_im               (               mag2_im_comb            )    
    );

    // ----------------------------------------------------------------
    // Output register
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            valid_out  <= 0                          ; 
            valid_diag <= 0                          ;
            l_out_re   <= 0                          ; 
            l_out_im   <= 0                          ;
            a_diag_out <= 0                          ;
        end  
        else begin 
            valid_out  <= valid_sq                   ;
            valid_diag <= valid_sq                   ;
            if (valid_sq) begin 
                l_out_re   <= l_re_sq_stage          ;
                l_out_im   <= l_im_sq_stage          ;
                a_diag_out <= -$signed(mag2_re_comb) ;
            end
        end
    end

endmodule