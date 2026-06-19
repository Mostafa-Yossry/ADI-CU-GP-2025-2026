// ============================================================
// Module : phase1_fwd_sub  (CONFIGURABLE NxN)
// Description : Fully pipelined complex forward substitution solving L*z = y, where
//               L is the lower-triangular Cholesky factor and y is the matched-filter
//               output vector. Produces one z vector per clock cycle (throughput = 1
//               vector/cycle) with a latency of N cycles. Stage i computes z[i]
//               combinationally by subtracting the dot product of L[i][0..i-1] with
//               the already-computed z[0..i-1] from y[i], then scaling by inv[i].
//               To align all signals at stage i: y[i] is delayed i cycles through a
//               d_ff_complex chain; The multiply-accumulate tree inside each stage uses
//               complex_mult_comb and complex_adder exclusively. A valid shift
//               register of depth N-1 propagates the input valid flag to the output.
//
// Algorithm:
//   z[0] = y[0] * inv[0]
//   z[i] = (y[i] - sum_{j=0}^{i-1} L[i][j] * z[j]) * inv[i]
//
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================


module phase1_fwd_sub #(
           parameter N                      = 8                     ,
           parameter WIDTH                  = 16                    ,
           
           // MATLAB Bit-True Q-Formats from Instrumentation Table
           parameter FB_L                   = 11                    ,
           parameter FB_Y                   = 11                    ,
           parameter FB_Z                   = 13                    ,
           parameter FB_INV                 = 12                    ,
           parameter FB_PROD_PHASE2         = 13                    ,
           parameter FB_ACC_PHASE2          = 10                    ,
           parameter FB_SUB_PHASE2          = 10                    ,
           parameter ROUNDING_METHOD        = "CONVERGENT"
)(
    input  wire                     clk                             ,
    input  wire                     rst                             ,
    input  wire                     valid_in                        ,

    input  wire signed [WIDTH-1:0]  L_re     [0:N-1][0:N-1]         ,
    input  wire signed [WIDTH-1:0]  L_im     [0:N-1][0:N-1]         ,
    input  wire signed [WIDTH-1:0]  inv_L    [0:N-1]                ,
     
    input  wire signed [WIDTH-1:0]  y_re     [0:N-1]                ,
    input  wire signed [WIDTH-1:0]  y_im     [0:N-1]                ,

    output reg                     valid_out                        ,           
    output reg signed [WIDTH-1:0]  z_re_out  [0:N-1]                ,
    output reg signed [WIDTH-1:0]  z_im_out  [0:N-1]
);


/*...........................................Interal Signals..................................................*/

    // ----------------------------------------------------------------
    // y pipeline                                   (signals)
    // ----------------------------------------------------------------
    
    wire signed [WIDTH-1:0] y_re_pipe   [0:N-1][0:N-1]          ;
    wire signed [WIDTH-1:0] y_im_pipe   [0:N-1][0:N-1]          ;

    // ----------------------------------------------------------------
    // z pipeline                                   (signals)
    // ----------------------------------------------------------------
    
    wire signed [WIDTH-1:0] z_re_int [0:N-1]                    ;
    wire signed [WIDTH-1:0] z_im_int [0:N-1]                    ;

    wire signed [WIDTH-1:0] z_re_pipe [0:N-1][0:N-1]            ;
    wire signed [WIDTH-1:0] z_im_pipe [0:N-1][0:N-1]            ;

    // ----------------------------------------------------------------
    // Valid Out Pipeline (Latency = N-1 cycles)
    // ----------------------------------------------------------------
    
    reg [N-1:0] valid_pipe                                      ;

/*...........................................Internal Logic..................................................*/

    // ----------------------------------------------------------------
    // y pipeline
    // ----------------------------------------------------------------

    genvar user_num, y_delay_stage;
    generate
        for (user_num = 0; user_num < N; user_num = user_num + 1) begin : y_pipe_user
            assign y_re_pipe[user_num][0] = y_re[user_num];
            assign y_im_pipe[user_num][0] = y_im[user_num];
            for (y_delay_stage = 0; y_delay_stage < N-1; y_delay_stage = y_delay_stage + 1) begin : y_pipe_delay
                d_ff_complex #(
                            .WIDTH                (             WIDTH                                                                       ) 
                ) eq_yp_ff (
                            .clk                  (             clk                                                                         ),
                            .rst                  (             rst                                                                         ),
                            .d_r                  (             y_re_pipe[user_num][y_delay_stage  ]                                          ),
                            .d_im                 (             y_im_pipe[user_num][y_delay_stage  ]                                          ),
                            .q_r                  (             y_re_pipe[user_num][y_delay_stage+1]                                          ),
                            .q_im                 (             y_im_pipe[user_num][y_delay_stage+1]                                          )
                );
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // z pipeline
    // ----------------------------------------------------------------

    genvar z_src_number,z_delay_stage;
    generate
        for (z_src_number = 0; z_src_number < N; z_src_number = z_src_number + 1) begin : z_pipe_src
            assign z_re_pipe[z_src_number][0] = z_re_int[z_src_number];
            assign z_im_pipe[z_src_number][0] = z_im_int[z_src_number];
            for (z_delay_stage = 0; z_delay_stage < N-1; z_delay_stage = z_delay_stage + 1) begin : z_pipe_delay
                d_ff_complex #(
                            .WIDTH                (             WIDTH                                                                      ) 
                ) eq_zp_ff (
                            .clk                  (             clk                                                                        ),
                            .rst                  (             rst                                                                        ),
                            .d_r                  (             z_re_pipe[z_src_number][z_delay_stage  ]                                       ),
                            .d_im                 (             z_im_pipe[z_src_number][z_delay_stage  ]                                       ),
                            .q_r                  (             z_re_pipe[z_src_number][z_delay_stage+1]                                       ),
                            .q_im                 (             z_im_pipe[z_src_number][z_delay_stage+1]                                       )
                );
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // Computation stages (EXACT MATLAB BIT-TRUE MATCHING)
    // ----------------------------------------------------------------
    genvar current_stage_number, current_term_number;
    generate
        for (current_stage_number = 0; current_stage_number < N; current_stage_number = current_stage_number + 1) begin : stage_i
            
            // Sequential Accumulator Chain
            wire signed [WIDTH-1:0] acc_chain_re [0:current_stage_number];
            wire signed [WIDTH-1:0] acc_chain_im [0:current_stage_number];
            
            assign acc_chain_re[0] = 0;
            assign acc_chain_im[0] = 0;

            for (current_term_number = 0; current_term_number < current_stage_number; current_term_number = current_term_number + 1) begin : gen_mults
                wire signed [WIDTH-1:0] prod_re;
                wire signed [WIDTH-1:0] prod_im;

                // 1. prod = L(i,j) * z(j)
                complex_mult_comb #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .FB_IN1               (             FB_L                                                                       ),
                            .FB_IN2               (             FB_Z                                                                       ),
                            .FB_OUT               (             FB_PROD_PHASE2                                                             ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )
                ) eq_mult_zj (
                            .a_re                 (             L_re[current_stage_number][current_term_number]                            ),
                            .a_im                 (             L_im[current_stage_number][current_term_number]                            ),
                            .b_re                 (             z_re_pipe[current_term_number][current_stage_number-current_term_number]   ),
                            .b_im                 (             z_im_pipe[current_term_number][current_stage_number-current_term_number]   ),
                            .res_re               (             prod_re                                                                    ),
                            .res_im               (             prod_im                                                                    )
                );

                // 2. acc = acc + prod
                complex_adder #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .FB_IN1               (             FB_ACC_PHASE2                                                              ),
                            .FB_IN2               (             FB_PROD_PHASE2                                                             ),
                            .FB_OUT               (             FB_ACC_PHASE2                                                              ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )
                ) eq_acc_step (
                            .a_re                 (             acc_chain_re[current_term_number]                                          ),
                            .a_im                 (             acc_chain_im[current_term_number]                                          ),
                            .b_re                 (             prod_re                                                                    ),
                            .b_im                 (             prod_im                                                                    ),
                            .sum_re               (             acc_chain_re[current_term_number+1]                                        ),
                            .sum_im               (             acc_chain_im[current_term_number+1]                                        )
                );
            end

            // 3. sub = yhat - acc
            localparam SHIFT_Y_SUB_R = (FB_Y > FB_SUB_PHASE2) ? (FB_Y - FB_SUB_PHASE2) : 0;
            localparam SHIFT_Y_SUB_L = (FB_SUB_PHASE2 > FB_Y) ? (FB_SUB_PHASE2 - FB_Y) : 0;
            
            wire signed [WIDTH-1:0] y_shifted_re, y_shifted_im                            ;

            smart_round #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .SHIFT                (             SHIFT_Y_SUB_R                                                              ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )
            ) eq_rnd_y_re (
                            .d_in                 (             y_re_pipe[current_stage_number][current_stage_number]                      ),
                            .d_out                (             y_shifted_re                                                               )
            );
            
            smart_round #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .SHIFT                (             SHIFT_Y_SUB_R                                                              ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )
            ) eq_rnd_y_im (
                            .d_in                 (             y_im_pipe[current_stage_number][current_stage_number]                      ),
                            .d_out                (             y_shifted_im                                                               )
            );

            wire signed [WIDTH-1:0] yhat_i_re = (SHIFT_Y_SUB_R > 0) ? y_shifted_re : (y_re_pipe[current_stage_number][current_stage_number] <<< SHIFT_Y_SUB_L);
            wire signed [WIDTH-1:0] yhat_i_im = (SHIFT_Y_SUB_R > 0) ? y_shifted_im : (y_im_pipe[current_stage_number][current_stage_number] <<< SHIFT_Y_SUB_L);

            wire signed [WIDTH-1:0] sub_re = yhat_i_re - acc_chain_re[current_stage_number];
            wire signed [WIDTH-1:0] sub_im = yhat_i_im - acc_chain_im[current_stage_number];

            // 4. z = sub * inv_L
            complex_mult_comb #(
                            .WIDTH                (             WIDTH                                                                      ), 
                            .FB_IN1               (             FB_SUB_PHASE2                                                              ),
                            .FB_IN2               (             FB_INV                                                                     ),
                            .FB_OUT               (             FB_Z                                                                       ),
                            .ROUNDING_METHOD      (             ROUNDING_METHOD                                                            )
            ) eq_mult_inv (
                            .a_re                 (             sub_re                                                                     ),
                            .a_im                 (             sub_im                                                                     ),
                            .b_re                 (             inv_L   [current_stage_number]                                             ),
                            .b_im                 (             {WIDTH{1'b0}}                                                              ), // Real Inverse
                            .res_re               (             z_re_int[current_stage_number]                                             ),
                            .res_im               (             z_im_int[current_stage_number]                                             )
            );

        end
    endgenerate


    // ----------------------------------------------------------------
    // Valid Out Pipeline (Latency = N-1 cycles)
    // ----------------------------------------------------------------

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            valid_pipe <= 0                             ;
        end 
        else begin
            valid_pipe <= {valid_pipe[N-2:0], valid_in} ;
        end
    end

    // ----------------------------------------------------------------
    // Output assignments (Registered to break the Critical Path)
    // Valid Out Pipeline (Latency = N cycles)
    // ----------------------------------------------------------------
    integer current_stage;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            valid_out <= 1'b0;
            for (current_stage = 0; current_stage < N; current_stage = current_stage + 1) begin
                z_re_out[current_stage] <= {WIDTH{1'b0}};
                z_im_out[current_stage] <= {WIDTH{1'b0}};
            end
        end 
        else begin  
            for (current_stage = 0; current_stage < N; current_stage = current_stage + 1) begin
                z_re_out[current_stage] <= z_re_pipe[current_stage][N - 1 - current_stage];
                z_im_out[current_stage] <= z_im_pipe[current_stage][N - 1 - current_stage];
            end
            valid_out <= valid_pipe[N-2]; 
        end
    end

endmodule