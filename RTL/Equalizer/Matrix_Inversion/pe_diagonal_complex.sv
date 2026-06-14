//============================================================
// Module      : pe_diagonal  (CONFIGURABLE NxN VERSION)
// Description : The diagonal Processing Element (PE) for the systolic complex
//               Cholesky decomposition. Computes L_kk = sqrt(G_kk - sum|L_kj|^2)
//               and the reciprocal inv_k = 1/L_kk used by all off-diagonal PEs in
//               the same column. Mirrors the MATLAB bit-true reference step by step:
//               (1) Each incoming squared-magnitude contribution |L_kj|^2 from an
//               off-diagonal PE is cast to the accumulator format FB_ACC_DIAG using
//               smart_round before being added to acc_diag_reg. An N_COLS-wide
//               valid_col bus and a packed a_col_in bus carry these contributions;
//               the FSM counts received contributions and fires sqrt_start only after
//               all N_COLS values have been accumulated.
//               (2) The diagonal element G_kk is cast to FB_SQRT_IN and combined
//               with the accumulator at the highest fractional precision to avoid
//               pre-addition loss, then cast back down before the sqrt.
//               (3) A negative-value clamp prevents rounding noise from making a
//               near-zero argument negative and corrupting the unsigned square-root.
//               (4) sqrt_pipelined computes L_kk; a WIDTH-stage delay line aligns
//               the sqrt result with the output of the reciprocal divider so l_out
//               and l_inv_out are valid on the same cycle.
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================

module pe_diagonal_complex #(
           parameter                                                         WIDTH           = 16           ,
           parameter                                                         FB_G            = 8            ,   
           parameter                                                         FB_MAG2         = 12           ,  
           parameter                                                         FB_ACC_DIAG     = 10           ,  
           parameter                                                         FB_SQRT_IN      = 8            ,   
           parameter                                                         FB_SQRT_OUT     = 11           ,  
           parameter                                                         FB_L            = 11           ,
           parameter                                                         FB_INV          = 12           ,
           parameter                                                         N_COLS          = 0            ,
           parameter                                                         ROUNDING_METHOD = "CONVERGENT"
)(
    input  wire                                                              clk                            ,
    input  wire                                                              rst                            ,

    input  wire                                                              valid_in                       ,
    input  wire signed [WIDTH-1:0]                                           a_in                           ,       // Comes from G matrix

    // Flat-packed: bit k of valid_col + slice k of a_col_in            
    // Safe even when N_COLS=0 (1-bit/WIDTH-bit minimums)           
    input  wire        [(N_COLS > 0 ? N_COLS : 1)-1      :0]                 valid_col                      , 
    input  wire signed [(N_COLS > 0 ? N_COLS : 1)*WIDTH-1:0]                 a_col_in                       ,       // Comes from off-diag (mag2)

    output wire                                                              valid_out                      ,
    output wire signed [WIDTH-1:0]                                           l_out                          ,
    output wire signed [WIDTH-1:0]                                           l_inv_out
);
    

/*...........................................Local Parameters..................................................*/

    // 1.0 in Q2.14 format
    localparam signed [WIDTH-1:0] FP_ONE = (1 << 14);

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 1: SHIFT BEFORE ADD (mag2_cast = cast(mag2_full, 'like', acc_diag)) (Parameters)
    // --------------------------------------------------------------------------------------------
    localparam SHIFT_COL_L = (FB_ACC_DIAG > FB_MAG2) ? (FB_ACC_DIAG - FB_MAG2) : 0;
    localparam SHIFT_COL_R = (FB_MAG2 > FB_ACC_DIAG) ? (FB_MAG2 - FB_ACC_DIAG) : 0;

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 3: PREPARE SQRT INPUT (sqrt_in = G + acc_diag)                      (Parameters)
    // --------------------------------------------------------------------------------------------
    // 1. Gkk = cast(real(G(k,k)), 'like', T.sqrt_in);
    // Align a_in_reg (FB_G) to FB_sqrt_in
    localparam SHIFT_G_L = (FB_SQRT_IN > FB_G) ? (FB_SQRT_IN - FB_G) : 0;
    localparam SHIFT_G_R = (FB_G > FB_SQRT_IN) ? (FB_G - FB_SQRT_IN) : 0;

    // 2. Simulate double() precision addition:
    // We elevate both operands to the HIGHEST fractional precision to avoid losing bits before addition.
    localparam HIGHEST_FBITS = (FB_ACC_DIAG > FB_SQRT_IN) ? FB_ACC_DIAG : FB_SQRT_IN;
    localparam SHIFT_GKK_UP = HIGHEST_FBITS - FB_SQRT_IN;
    localparam SHIFT_ACC_UP = HIGHEST_FBITS - FB_ACC_DIAG;

    // Use an extended width (WIDTH + max shift + 1) to prevent overflow during alignment and addition
    localparam EXT_W = WIDTH + SHIFT_GKK_UP + 1;
    
    // 3. sqrt_in = cast(sum_double, 'like', T.sqrt_in);
    localparam SHIFT_SUM_DOWN = HIGHEST_FBITS - FB_SQRT_IN;

/*...........................................Interal Signals..................................................*/
    
    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 1: SHIFT BEFORE ADD (mag2_cast = cast(mag2_full, 'like', acc_diag)) (Signals)
    // --------------------------------------------------------------------------------------------
    
    wire signed [WIDTH-1        :0] a_col_aligned [0:(N_COLS > 0 ? N_COLS - 1 : 0)] ;

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 2: ACCUMULATE THE SHIFTED VALUES (acc_diag = acc_diag + mag2_cast)  (Signals)
    // --------------------------------------------------------------------------------------------
    reg signed [WIDTH-1         :0] a_in_reg                                        ;    
    reg signed [WIDTH-1         :0] acc_diag_reg                                    ;    
    reg        [$clog2(N_COLS+2):0] col_done                                        ;
    reg                             sqrt_start                                      ;

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 3: PREPARE SQRT INPUT (sqrt_in = G + acc_diag)                      (Signals)
    // --------------------------------------------------------------------------------------------
    wire signed [WIDTH-1        :0] Gkk                                             ;
    wire signed [WIDTH-1        :0] Gkk_shifted                                     ;        
    wire signed [EXT_W-1        :0] Gkk_double                                      ;
    wire signed [EXT_W-1        :0] acc_double                                      ;
    wire signed [EXT_W-1        :0] sum_double                                      ;
    wire signed [EXT_W-1        :0] sum_double_shifted                              ;
    wire signed [WIDTH-1        :0] sqrt_in_raw                                     ;
    wire signed [WIDTH-1        :0] sqrt_in                                         ;
    
    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 4: Square Root                                                      (Signals)
    // --------------------------------------------------------------------------------------------
    wire                            sqrt_valid                                      ;
    wire         [WIDTH-1       :0] sqrt_res                                        ;

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 5: Divider: 1.0 / sqrt result (used) for pe_off_diagonal            (Signals)
    // --------------------------------------------------------------------------------------------
    wire signed  [WIDTH-1       :0] unused_quo_im                                   ;

/*...........................................Internal Logic..................................................*/

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 1: SHIFT BEFORE ADD (mag2_cast = cast(mag2_full, 'like', acc_diag))
    // --------------------------------------------------------------------------------------------

    genvar current_col_indx;
    generate
        for (current_col_indx = 0; current_col_indx < (N_COLS > 0 ? N_COLS : 1); current_col_indx = current_col_indx + 1) begin : gen_col_align
            wire signed [WIDTH-1:0] temp_col = a_col_in[current_col_indx*WIDTH +: WIDTH]                                        ; // mag2_full
            wire signed [WIDTH-1:0] temp_col_shifted                                                                            ;
            // performs arithmetic right shift (truncation just like MATLAB's cast)
                smart_round #(
                    .WIDTH                (              WIDTH                    ), 
                    .SHIFT                (              SHIFT_COL_R              ),    
                    .ROUNDING_METHOD      (              ROUNDING_METHOD          )    
                ) eq_rnd_mag2 (
                    .d_in                 (              temp_col                 ), 
                    .d_out                (              temp_col_shifted         )
                ); 
            
            assign a_col_aligned[current_col_indx] = (SHIFT_COL_L > 0) ? (temp_col <<< SHIFT_COL_L) : temp_col_shifted           ;
        
        end
    endgenerate

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 2: ACCUMULATE THE SHIFTED VALUES (acc_diag = acc_diag + mag2_cast)
    // --------------------------------------------------------------------------------------------
  
    generate
        if (N_COLS == 0) begin : gen_no_cols
            // No contributions to wait for
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    a_in_reg     <= 0;
                    acc_diag_reg <= 0;
                    col_done     <= 0;
                    sqrt_start   <= 0;
                end 
                else begin
                    sqrt_start <= 0;
                    if (valid_in) begin
                        a_in_reg     <= a_in;
                        acc_diag_reg <= 0;
                        col_done     <= 0;
                        sqrt_start   <= 1;
                    end
                end
            end
        end 
        else begin : gen_with_cols
            // Wait for N_COLS contributions
            integer k;
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    a_in_reg     <= 0;
                    acc_diag_reg <= 0;
                    col_done     <= 0;
                    sqrt_start   <= 0;
                end 
                else begin
                    sqrt_start   <= 0;
                    if (valid_in) begin
                        a_in_reg     <= a_in; 
                        acc_diag_reg <= 0   ;    
                        col_done     <= 0   ;
                    end

                    // Accumulate ALREADY SHIFTED values 
                    for (k = 0; k < N_COLS; k = k + 1) begin
                        if (valid_col[k]) begin
                            acc_diag_reg <= acc_diag_reg + a_col_aligned[k]; // acc_diag + mag2_cast
                            col_done     <= col_done + 1                   ;
                            if ( (col_done + 1) == N_COLS[$clog2(N_COLS+2):0]) begin
                                sqrt_start <= 1                            ;
                            end
                        end
                    end
                end
            end
        end
    endgenerate

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 3: PREPARE SQRT INPUT (sqrt_in = G + acc_diag)
    // --------------------------------------------------------------------------------------------
    
    // Gkk = cast(real(G(k,k)), 'like', T.sqrt_in);
    // Align a_in_reg (FB_G) to FB_sqrt_in
    smart_round #(
        .WIDTH                (              WIDTH                    ), 
        .SHIFT                (              SHIFT_G_R                ),    
        .ROUNDING_METHOD      (              ROUNDING_METHOD          )    
    ) eq_rnd_Gkk (
        .d_in                 (              a_in_reg                 ), 
        .d_out                (              Gkk_shifted              )
    ); 
    
    assign Gkk = (SHIFT_G_L > 0) ? (a_in_reg <<< SHIFT_G_L) : Gkk_shifted;

    // Promote both to HIGHEST_FBITS (This mimics casting to double)
    assign Gkk_double = $signed(Gkk) <<< SHIFT_GKK_UP                                 ;
    assign acc_double = $signed(acc_diag_reg) <<< SHIFT_ACC_UP                        ;

    // Perform the high-precision addition
    assign sum_double = Gkk_double + acc_double                                       ;

    smart_round #(
        .WIDTH               (              EXT_W                       ), 
        .SHIFT               (              SHIFT_SUM_DOWN              ),    
        .ROUNDING_METHOD     (              ROUNDING_METHOD             )    
    ) eq_rnd_sum (
        .d_in                (              sum_double                  ), 
        .d_out               (              sum_double_shifted          )
    ); 
    
    // Calculate raw input
    assign sqrt_in_raw = sum_double_shifted[WIDTH-1:0]                                ;
    
    // MATLAB CLAMP: if (sqrt_in < 0) sqrt_in = 0;
    // This prevents negative rounding noise from destroying the Unsigned Sqrt
    assign sqrt_in = (sqrt_in_raw < 0) ? {WIDTH{1'b0}} : sqrt_in_raw                  ;

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 4: Square Root
    // --------------------------------------------------------------------------------------------

    sqrt_pipelined #(
        .WIDTH               (              WIDTH               ), 
        .F_IN                (              FB_SQRT_IN          ),    
        .F_OUT               (              FB_SQRT_OUT         ),
        .ROUNDING_METHOD     (              ROUNDING_METHOD     )     
    ) eq_sqrt_inst (
        .clk                 (              clk                 ), 
        .rst                 (              rst                 ),
        .valid_in            (              sqrt_start          ), 
        .x_in                (              sqrt_in             ),         
        .valid_out           (              sqrt_valid          ), 
        .result              (              sqrt_res            )
    ); 

    // --------------------------------------------------------------------------------------------
    // MATLAB STEP 5: Divider: 1.0 / sqrt result (used) for pe_off_diagonal
    // --------------------------------------------------------------------------------------------

    div_complex_by_real #(
        .WIDTH               (              WIDTH               ), 
        .FB_NUM              (              14                  ),       
        .FB_DEN              (              FB_L                ),     
        .FB_OUT              (              FB_INV              ),
        .ROUNDING_METHOD     (              ROUNDING_METHOD     )       
    ) eq_div_inst (
        .clk                 (              clk                 ), 
        .rst                 (              rst                 ),
        .valid_in            (              sqrt_valid          ),
        .num_re              (              FP_ONE              ),
        .num_im              (              {WIDTH{1'b0}}       ),
        .den_real            (              sqrt_res            ),
        .valid_out           (              valid_out           ),
        .quo_re              (              l_inv_out           ),
        .quo_im              (              unused_quo_im       )
    );

    // --------------------------------------------------------------------------------------------
    // Delay line: align l_out with l_inv_out
    // Divider latency = WIDTH+1 cycles after sqrt_valid
    // --------------------------------------------------------------------------------------------
    reg signed [WIDTH-1:0] delay_pipe [0:WIDTH];
    integer ii;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            for (ii = 0; ii <= WIDTH; ii = ii + 1)
                delay_pipe[ii] <= 0               ;
        end 
        else begin
            delay_pipe[0] <= sqrt_res             ;
            for (ii = 0; ii < WIDTH; ii = ii + 1)
                delay_pipe[ii+1] <= delay_pipe[ii];
        end
    end

    assign l_out = delay_pipe[WIDTH]              ;

endmodule