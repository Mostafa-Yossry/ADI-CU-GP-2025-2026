// ============================================================
// Module : phase2_back_sub  (CONFIGURABLE NxN)
// Description : Fully pipelined complex backward substitution solving L^H * x = z,
//               where L^H is the conjugate transpose of the Cholesky factor and z is
//               the output of phase2. Mirrors the structure of phase2 but processes
//               rows in reverse order: stage k (k=0..N-1) computes x[N-1-k].
//               Before any stage executes, z[N-1-k] is delayed
//               2*k cycles, L is taken from depth N-1+k of the pre-delay chain, and
//               prior x values x[N-1-s] (s<k) are each delayed 2*(k-s) cycles from
//               their respective stage outputs. The conjugate of L[j][i] is formed by
//               negating the imaginary part at the b_im input of complex_mult_comb.
//               All output symbols x[0..N-1] emerge aligned to the same clock cycle.
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================


module phase2_back_sub #(
           parameter                N                       = 8             ,
           parameter                WIDTH                   = 16            ,
           parameter                FB_L                    = 11            ,
           parameter                FB_Z                    = 13            ,
           parameter                FB_XHAT                 = 13            ,
           parameter                FB_INV                  = 12            ,
           parameter                FB_PROD_PHASE3          = 13            ,
           parameter                FB_ACC_PHASE3           = 10            ,
           parameter                FB_SUB_PHASE3           = 10            ,
           parameter                ROUNDING_METHOD         = "CONVERGENT"

)(
    input  wire                     clk                                     ,
    input  wire                     rst                                     ,
    input  wire                     valid_in                                ,

    input  wire signed [WIDTH-1:0]  L_re  [0:N-1][0:N-1]                    ,
    input  wire signed [WIDTH-1:0]  L_im  [0:N-1][0:N-1]                    ,
    input  wire signed [WIDTH-1:0]  inv_L [0:N-1]                           ,

    input  wire signed [WIDTH-1:0]  z_re  [0:N-1]                           ,
    input  wire signed [WIDTH-1:0]  z_im  [0:N-1]                           ,

    output wire                     valid_out                               ,
    output wire signed [WIDTH-1:0]  x_re_out [0:N-1]                        ,
    output wire signed [WIDTH-1:0]  x_im_out [0:N-1]
);

/*...........................................Interal Signals..................................................*/

    // ----------------------------------------------------------------
    // 1. z pipeline (Depth N-1)                           (Signals)
    // ----------------------------------------------------------------
    
    wire signed [WIDTH-1:0] z_re_pipe [0:N-1][0:N-1]                ;
    wire signed [WIDTH-1:0] z_im_pipe [0:N-1][0:N-1]                ;

    // ----------------------------------------------------------------
    // 2. x pipeline (Feedback delays)                     (Signals)
    // x_pipe[s][d] = x_int[s] delayed d DFFs
    // ----------------------------------------------------------------
   
    wire signed [WIDTH-1:0] x_re_int  [0:N-1]                       ;
    wire signed [WIDTH-1:0] x_im_int  [0:N-1]                       ;

    wire signed [WIDTH-1:0] x_re_pipe [0:N-1][0:N-1]                ;
    wire signed [WIDTH-1:0] x_im_pipe [0:N-1][0:N-1]                ;

    // ----------------------------------------------------------------
    // 5. Valid Out Pipeline (Latency = N-1 cycles)        (Signals)
    // ----------------------------------------------------------------
   
    reg [N-1:0] valid_pipe                                          ;

/*...........................................Internal Logic..................................................*/
    
    // ----------------------------------------------------------------
    // 1. z pipeline (Depth N-1)
    // ----------------------------------------------------------------

    genvar z_src_num,z_delay_num;
    generate
        for (z_src_num = 0; z_src_num < N; z_src_num = z_src_num + 1) begin : z_pipe_src
            assign z_re_pipe[z_src_num][0] = z_re[z_src_num];
            assign z_im_pipe[z_src_num][0] = z_im[z_src_num];
            for (z_delay_num = 0; z_delay_num < N-1; z_delay_num = z_delay_num + 1) begin : z_pipe_delay
                d_ff_complex #(
                            .WIDTH                (             WIDTH                                                                      ) 
                ) eq_zp_ff (
                            .clk                  (             clk                                                                        ),
                            .rst                  (             rst                                                                        ),
                            .d_r                  (             z_re_pipe[z_src_num][z_delay_num  ]                                        ),
                            .d_im                 (             z_im_pipe[z_src_num][z_delay_num  ]                                        ),
                            .q_r                  (             z_re_pipe[z_src_num][z_delay_num+1]                                        ),
                            .q_im                 (             z_im_pipe[z_src_num][z_delay_num+1]                                        )
                );
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // 2. x pipeline (Feedback delays)
    // x_pipe[s][d] = x_int[s] delayed d DFFs
    // ----------------------------------------------------------------

     genvar x_src_num,x_delay_num;
    generate
        for (x_src_num = 0; x_src_num < N; x_src_num = x_src_num + 1) begin : x_pipe_src
            assign x_re_pipe[x_src_num][0] = x_re_int[x_src_num];
            assign x_im_pipe[x_src_num][0] = x_im_int[x_src_num];
            for (x_delay_num = 0; x_delay_num < N-1; x_delay_num = x_delay_num + 1) begin : x_pipe_delay
                d_ff_complex #(
                            .WIDTH                (             WIDTH                                                                      ) 
                ) eq_xp_ff (
                            .clk                  (             clk                                                                        ),
                            .rst                  (             rst                                                                        ),
                            .d_r                  (             x_re_pipe[x_src_num][x_delay_num  ]                                        ),
                            .d_im                 (             x_im_pipe[x_src_num][x_delay_num  ]                                        ),
                            .q_r                  (             x_re_pipe[x_src_num][x_delay_num+1]                                        ),
                            .q_im                 (             x_im_pipe[x_src_num][x_delay_num+1]                                        )
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------------------------------------------------------------
    // 3. Computation stages 
    // In this stage we inverted the index so x0 is x7 and x1 is x6 as so on while we invert it at the output stage
    // ------------------------------------------------------------------------------------------------------------------
    genvar inv_stage_num, term_num;
    generate
        for (inv_stage_num = 0; inv_stage_num < N; inv_stage_num = inv_stage_num + 1) begin : stage_k

            localparam L_COL  = N - 1 - inv_stage_num              ;
            localparam Z_INDX = N - 1 - inv_stage_num              ;

            // Sequential Accumulator Chain
            wire signed [WIDTH-1:0] acc_chain_re [0:inv_stage_num] ;
            wire signed [WIDTH-1:0] acc_chain_im [0:inv_stage_num] ;
            
            assign acc_chain_re[0] = 0;
            assign acc_chain_im[0] = 0;

            for (term_num = 0; term_num < inv_stage_num; term_num = term_num + 1) begin : gen_mults
                localparam REVERTED_X  = inv_stage_num - 1 - term_num  ;
                localparam X_DELAY     = 1 + term_num                  ;
                localparam LROW        = N - 1 - REVERTED_X            ;

                wire signed [WIDTH-1:0] prod_re                        ;
                wire signed [WIDTH-1:0] prod_im                        ;

                // prod = conj(L) * x
                complex_mult_comb #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .FB_IN1               (             FB_XHAT                                                                    ),       // a = x
                            .FB_IN2               (             FB_L                                                                       ),          // b = conj(L)
                            .FB_OUT               (             FB_PROD_PHASE3                                                             ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )   
                ) eq_mult_xs (
                            .a_re                 (             x_re_pipe[REVERTED_X][X_DELAY]                                             ),
                            .a_im                 (             x_im_pipe[REVERTED_X][X_DELAY]                                             ),
                            .b_re                 (              L_re    [LROW      ][L_COL  ]                                             ), // Conjugate (+Re)
                            .b_im                 (             -L_im    [LROW      ][L_COL  ]                                             ), // Conjugate (-Im)
                            .res_re               (             prod_re                                                                    ),
                            .res_im               (             prod_im                                                                    )
                );

                // acc = acc + prod
                complex_adder #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .FB_IN1               (             FB_ACC_PHASE3                                                              ),
                            .FB_IN2               (             FB_PROD_PHASE3                                                             ),
                            .FB_OUT               (             FB_ACC_PHASE3                                                              ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )   
                ) eq_acc_step (
                            .a_re                 (             acc_chain_re[term_num]                                                     ),
                            .a_im                 (             acc_chain_im[term_num]                                                     ),
                            .b_re                 (             prod_re                                                                    ),
                            .b_im                 (             prod_im                                                                    ),
                            .sum_re               (             acc_chain_re[term_num+1]                                                   ),
                            .sum_im               (             acc_chain_im[term_num+1]                                                   )
                );
            end

            // sub = z - acc
            localparam SHIFT_Z_SUB_R = (FB_Z > FB_SUB_PHASE3) ? (FB_Z - FB_SUB_PHASE3) : 0;
            localparam SHIFT_Z_SUB_L = (FB_SUB_PHASE3 > FB_Z) ? (FB_SUB_PHASE3 - FB_Z) : 0;
            

            wire signed [WIDTH-1:0] z_shifted_re, z_shifted_im;

            smart_round #(
                            .WIDTH                (             WIDTH                                                                      ),
                            .SHIFT                (             SHIFT_Z_SUB_R                                                              ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )
            ) eq_rnd_z_re (
                            .d_in                 (             z_re_pipe[Z_INDX][inv_stage_num]                                           ),
                            .d_out                (             z_shifted_re                                                               )
            );

            smart_round #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .SHIFT                (             SHIFT_Z_SUB_R                                                              ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )
            ) eq_rnd_z_im (
                            .d_in                 (             z_im_pipe[Z_INDX][inv_stage_num]                                           ),
                            .d_out                (             z_shifted_im                                                               )
            );

            wire signed [WIDTH-1:0] z_i_re = (SHIFT_Z_SUB_R > 0) ? z_shifted_re : (z_re_pipe[Z_INDX][inv_stage_num] <<< SHIFT_Z_SUB_L);
            wire signed [WIDTH-1:0] z_i_im = (SHIFT_Z_SUB_R > 0) ? z_shifted_im : (z_im_pipe[Z_INDX][inv_stage_num] <<< SHIFT_Z_SUB_L);

            wire signed [WIDTH-1:0] sub_re = z_i_re - acc_chain_re[inv_stage_num]                                                     ;
            wire signed [WIDTH-1:0] sub_im = z_i_im - acc_chain_im[inv_stage_num]                                                     ;

            // x = sub * inv_L
            complex_mult_comb #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .FB_IN1               (             FB_SUB_PHASE3                                                              ),
                            .FB_IN2               (             FB_INV                                                                     ),
                            .FB_OUT               (             FB_XHAT                                                                    ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )   
            ) eq_mult_inv (
                            .a_re                 (             sub_re                                                                     ),
                            .a_im                 (             sub_im                                                                     ),
                            .b_re                 (             inv_L   [L_COL        ]                                                    ),
                            .b_im                 (             {WIDTH{1'b0}}                                                              ), // Real Inverse
                            .res_re               (             x_re_int[inv_stage_num]                                                    ),
                            .res_im               (             x_im_int[inv_stage_num]                                                    )
            );

        end
    endgenerate

    // ----------------------------------------------------------------
    // 4. Output assignments (Aligned)
    // ----------------------------------------------------------------
    genvar current_stage;
    generate
        for (current_stage = 0; current_stage < N; current_stage = current_stage + 1) begin : gen_out
            // Element current_stage is computed at stage (N-1-current_stage).
            // Needs (current_stage) delays to reach cycle N-1.
            assign x_re_out[current_stage] = x_re_pipe[N-1-current_stage][current_stage];
            assign x_im_out[current_stage] = x_im_pipe[N-1-current_stage][current_stage];
        end
    endgenerate

    // ----------------------------------------------------------------
    // 5. Valid Out Pipeline (Latency = N-1 cycles)
    // ----------------------------------------------------------------

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            valid_pipe <= 0                            ;
        end 
        else begin
            valid_pipe <= {valid_pipe[N-2:0], valid_in};
        end
    end
    assign valid_out = valid_pipe[N-2];

endmodule