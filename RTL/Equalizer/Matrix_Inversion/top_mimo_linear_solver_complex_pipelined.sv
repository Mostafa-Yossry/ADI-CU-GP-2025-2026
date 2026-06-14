// ============================================================
// Module      : top_mimo_linear_solver_complex_pipelined  (CONFIGURABLE NxN)
// Description : Top-level integration module for the full MIMO linear equalization
//             pipeline implementing the Matched-Filter + Cholesky linear solver
//             approach. Accepts a serialized lower-triangle G matrix (one element
//             per clock on g_re_in / g_im_in) and a stream of y vectors (N elements
//             wide, one vector per clock on y_re_flat / y_im_flat), and produces
//             a continuous stream of detected symbol vectors x. Internally
//             instantiates: 
//                          (1) G_matrix_deserializer to buffer and reconstruct
//                              the 2-D G array and assert phase1_start.
//                          (2) phase1_cholesky_complex  to decompose G = L*L^H and compute the inverse diagonal inv[0..N-1] ,
//                          (3) Unpacking_Packing_Phase_2_3 to convert between the flat N*WIDTH
//                              bus format of the top-level ports and the unpacked 1-D arrays
//                              expected by phases 2 and 3.
//                          (4) phase2_fwd_sub_vec_top_complex_Pip
//                              to solve L*z = y; and (5) phase3_back_sub_vec_top_complex_pip to
//                              solve L^H * x = z.
//             All fixed-point format parameters and the
//             ROUNDING_METHOD are propagated uniformly to every sub-module through
//             a single parameter set defined at this level.
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================

module top_mimo_linear_solver_complex_pipelined #(
           
           // General Parameters
           // ==========================================================================
           parameter                     N               = 8            , // Matrix size (NxN antennas/streams)
           parameter                     WIDTH           = 16           , // Total bit-width for all fixed-point variables
           parameter                     UPDATE_INTERVAL = 50 * N       , // Clock cycles between Cholesky matrix recomputations
           parameter                     ROUNDING_METHOD = "CONVERGENT" , // "FLOOR" or "CONVERGENT"                   
   
           // ==========================================================================
           // Phase 1: Diagonal PE Parameters (Real computations)
           // ==========================================================================
           parameter                     FB_G            = 8             , // Fractional bits for input G matrix elements
           parameter                     FB_MAG2         = 12            , // Fractional bits for squared magnitude of off-diagonals (|L_ij|^2)
           parameter                     FB_ACC_DIAG     = 10            , // Fractional bits for diagonal accumulator ( sum(|L_ij|^2) )
           parameter                     FB_SQRT_IN      = 8             , // Fractional bits for square root module input (G_ii - sum(|L_ij|^2))
           parameter                     FB_SQRT_OUT     = 11            , // Fractional bits for square root module output (L_ii)
   
           // ==========================================================================
           // Phase 1: Off-Diagonal PE Parameters (Complex computations)                                  
           // ==========================================================================
           parameter                     FB_L            = 11             , // Fractional bits for final L matrix elements
           parameter                     FB_PROD_OFF     = 13             , // Fractional bits for off-diagonal product (L_ip * conj(L_jp))
           parameter                     FB_ACC_OFF      = 10             , // Fractional bits for off-diagonal accumulator
           parameter                     FB_SUB_OFF      = 12             , // Fractional bits for off-diagonal subtraction (G_ij - acc)
           parameter                     FB_INV          = 12             , // Fractional bits for reciprocal of diagonal (1 / L_jj)
           parameter                     FB_MAG2_OUT     = 12             , // Fractional bits for squared magnitude output to next PEs
   
           // ==========================================================================
           // Phase 2: Forward Substitution Parameters (L * z = y)
           // ==========================================================================
           parameter                     FB_Y            = 11             , // Fractional bits for input vector y
           parameter                     FB_Z            = 13             , // Fractional bits for intermediate vector z output
           parameter                     FB_PROD_PHASE2  = 13             , // Fractional bits for Phase 2 product (L_ij * z_j)
           parameter                     FB_ACC_PHASE2   = 10             , // Fractional bits for Phase 2 accumulator
           parameter                     FB_SUB_PHASE2   = 10             , // Fractional bits for Phase 2 subtraction (y_i - acc)
   
           // ==========================================================================
           // Phase 3: Backward Substitution Parameters (L^H * x = z)
           // ==========================================================================
           parameter                     FB_XHAT         = 13              , // Fractional bits for final output vector x (estimated symbols)
           parameter                     FB_PROD_PHASE3  = 13              , // Fractional bits for Phase 3 product (conj(L_ji) * x_j)
           parameter                     FB_ACC_PHASE3   = 10              , // Fractional bits for Phase 3 accumulator
           parameter                     FB_SUB_PHASE3   = 10                // Fractional bits for Phase 3 subtraction (z_i - acc)

)(
    input  wire                          clk                               ,
    input  wire                          rst                               ,
    
    // G matrix (serialized lower triangle)        
    input  wire                          g_valid                           ,
    input  wire signed [WIDTH-1:0]       g_re_in                           ,
    input  wire signed [WIDTH-1:0]       g_im_in                           ,
    
    // y vector (full N elements per cycle)        
    input  wire                          y_valid                           ,
    input  wire signed [N*WIDTH-1:0]     y_re_flat                         ,
    input  wire signed [N*WIDTH-1:0]     y_im_flat                         ,
    
    output wire signed [N*WIDTH-1:0]     x_re_flat                         ,
    output wire signed [N*WIDTH-1:0]     x_im_flat         
);
    
/*...........................................Local Parameters..................................................*/

    localparam              ELEMENTS = (N * (N + 1)) / 2; // number of lower triangular elements N=8 , ELEMENTS=64

/*...........................................Interal Signals..................................................*/
    
    // ----------------------------------------------------------------
    // G matrix deserializer signals 
    // ----------------------------------------------------------------
    reg signed [WIDTH-1:0]  g_diag        [0:N-1]          ;
    reg signed [WIDTH-1:0]  g_off_re      [0:N-1][0:N-1]   ;
    reg signed [WIDTH-1:0]  g_off_im      [0:N-1][0:N-1]   ;
    reg                     phase1_start                   ;
    
    // ----------------------------------------------------------------
    // Phase 1 — Cholesky signals
    // ----------------------------------------------------------------
    wire signed [WIDTH-1:0] l_off_re_bus  [0:N-1][0:N-1]   ;
    wire signed [WIDTH-1:0] l_off_im_bus  [0:N-1][0:N-1]   ;
    wire signed [WIDTH-1:0] inv_bus       [0:N-1]          ;

    // ----------------------------------------------------------------
    // Bus Unpacking/Packing for Phase 2 & 3 signals (Converts Flat to 2D Arrays)
    // ---------------------------------------------------------------- 
    wire signed [WIDTH-1:0] y_re_unpacked [0:N-1]          ;
    wire signed [WIDTH-1:0] y_im_unpacked [0:N-1]          ;
         
    wire signed [WIDTH-1:0] z_re_unpacked [0:N-1]          ;
    wire signed [WIDTH-1:0] z_im_unpacked [0:N-1]          ;
         
    wire signed [WIDTH-1:0] x_re_unpacked [0:N-1]          ;
    wire signed [WIDTH-1:0] x_im_unpacked [0:N-1]          ;

/*...........................................Submodules......................................................*/
   
    // ----------------------------------------------------------------
    // G matrix deserializer  
    // ----------------------------------------------------------------
    G_matrix_deserializer #(
            .N                          (              N                   ),
            .WIDTH                      (              WIDTH               ),
            .ELEMENTS                   (              ELEMENTS            )
    ) eq_g_matrix_deserializer (        
            .clk                        (              clk                 ),
            .rst                        (              rst                 ),
            .g_valid                    (              g_valid             ),
            .g_re_in                    (              g_re_in             ),
            .g_im_in                    (              g_im_in             ),
            .g_diag                     (              g_diag              ),
            .g_off_re                   (              g_off_re            ),
            .g_off_im                   (              g_off_im            ),
            .phase1_start               (              phase1_start        )
        );

    // ----------------------------------------------------------------
    // Phase 1 — Cholesky signals
    // ----------------------------------------------------------------
    phase1_cholesky_complex #(
            .N                          (              N                   ),
            .WIDTH                      (              WIDTH               ),
            .ELEMENTS                   (              ELEMENTS            ),
            //Diagonal Parameters   
            .FB_G                       (              FB_G                ), 
            .FB_MAG2                    (              FB_MAG2             ), 
            .FB_ACC_DIAG                (              FB_ACC_DIAG         ), 
            .FB_SQRT_IN                 (              FB_SQRT_IN          ), 
            .FB_SQRT_OUT                (              FB_SQRT_OUT         ), 
            //off-Diagonal Parameters                              
            .FB_L                       (              FB_L                ), 
            .FB_PROD_OFF                (              FB_PROD_OFF         ),
            .FB_ACC_OFF                 (              FB_ACC_OFF          ), 
            .FB_SUB_OFF                 (              FB_SUB_OFF          ), 
            .FB_INV                     (              FB_INV              ),
            .FB_MAG2_OUT                (              FB_MAG2_OUT         ),
            .UPDATE_INTERVAL            (              UPDATE_INTERVAL     ),
            .ROUNDING_METHOD            (              ROUNDING_METHOD     )
    ) eq_phase1 (
            .clk                        (              clk                 ),
            .rst                        (              rst                 ),
            .valid_in                   (              phase1_start        ),
            .g_diag_in                  (              g_diag              ),
            .g_off_re_in                (              g_off_re            ),
            .g_off_im_in                (              g_off_im            ),
            .valid_out                  (                                  ),
            .l_off_re_out               (              l_off_re_bus        ),
            .l_off_im_out               (              l_off_im_bus        ),
            .inv_out                    (              inv_bus             )
        );

    // ----------------------------------------------------------------
    // Unpacking and Packing for Phase2 & Phase3  
    // ----------------------------------------------------------------
    Unpacking_Packing_Phase_2_3 #(
        .N                              (             N                   ),
        .WIDTH                          (             WIDTH               )
    ) eq_unpacking_Packing_Phase_2_3 (
        .clk                            (             clk                 ),
        .rst                            (             rst                 ),
        .x_re_unpacked                  (             x_re_unpacked       ),
        .x_im_unpacked                  (             x_im_unpacked       ),
        .y_re_flat                      (             y_re_flat           ),
        .y_im_flat                      (             y_im_flat           ),
        .y_re_unpacked                  (             y_re_unpacked       ),
        .y_im_unpacked                  (             y_im_unpacked       ),
        .x_re_flat                      (             x_re_flat           ),
        .x_im_flat                      (             x_im_flat           )
    );

    // ----------------------------------------------------------------
    // Phase 2 — Forward substitution
    // ----------------------------------------------------------------
    phase2_fwd_sub_vec_top_complex_Pip #(
        .N                              (             N                   ),
        .WIDTH                          (             WIDTH               ),
        .FB_Y                           (             FB_Y                ),
        .FB_Z                           (             FB_Z                ),
        .FB_PROD_PHASE2                 (             FB_PROD_PHASE2      ),
        .FB_ACC_PHASE2                  (             FB_ACC_PHASE2       ),
        .FB_SUB_PHASE2                  (             FB_SUB_PHASE2       ),
        .ROUNDING_METHOD                (             ROUNDING_METHOD     )
    ) eq_phase2 (
        .clk                            (             clk                 ),
        .rst                            (             rst                 ),
        .valid_in                       (             y_valid             ),
        .L_re                           (             l_off_re_bus        ),
        .L_im                           (             l_off_im_bus        ),
        .inv_L                          (             inv_bus             ),
        .y_re                           (             y_re_unpacked       ),
        .y_im                           (             y_im_unpacked       ),
        .valid_out                      (                                 ),
        .z_re_out                       (             z_re_unpacked       ),
        .z_im_out                       (             z_im_unpacked       )
    );

    // ----------------------------------------------------------------
    // Phase 3 — Backward substitution (Outputs perfectly aligned)
    // ----------------------------------------------------------------
    phase3_back_sub_vec_top_complex_pip #(
        .N                              (             N                  ),
        .WIDTH                          (             WIDTH              ),
        .FB_L                           (             FB_L               ),
        .FB_Z                           (             FB_Z               ),
        .FB_XHAT                        (             FB_XHAT            ),
        .FB_INV                         (             FB_INV             ),
        .FB_PROD_PHASE3                 (             FB_PROD_PHASE3     ),
        .FB_ACC_PHASE3                  (             FB_ACC_PHASE3      ),
        .FB_SUB_PHASE3                  (             FB_SUB_PHASE3      ),
        .ROUNDING_METHOD                (             ROUNDING_METHOD     )
    ) eq_phase3 (
        .clk                            (             clk                ),
        .rst                            (             rst                ),
        .valid_in                       (             y_valid            ),
        .L_re                           (             l_off_re_bus       ),
        .L_im                           (             l_off_im_bus       ),
        .inv_L                          (             inv_bus            ),
        .z_re                           (             z_re_unpacked      ),
        .z_im                           (             z_im_unpacked      ),
        .valid_out                      (                                ),
        .x_re_out                       (             x_re_unpacked      ),
        .x_im_out                       (             x_im_unpacked      )
    );

endmodule