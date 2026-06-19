// ============================================================
// Module      : linear_solver_pipelined  (CONFIGURABLE NxN)
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

module linear_solver_pipelined #(
           
           // ==========================================================================
           // General Parameters
           // ==========================================================================
           parameter                     N               = 8              , // Matrix size (NxN antennas/streams)
           parameter                     WIDTH           = 16             , // Total bit-width for all fixed-point variables
           parameter                     UPDATE_INTERVAL = 50 * N         , // Clock cycles between Cholesky matrix recomputations
           parameter                     ROUNDING_METHOD = "CONVERGENT"   , // "FLOOR" or "CONVERGENT"                   
      
           // ==========================================================================
           // Phase 1: Forward Substitution Parameters (L * z = y)
           // ==========================================================================
           parameter                     FB_Y            = 11             , // Fractional bits for input vector y
           parameter                     FB_Z            = 13             , // Fractional bits for intermediate vector z output
           parameter                     FB_PROD_PHASE2  = 13             , // Fractional bits for Phase 2 product (L_ij * z_j)
           parameter                     FB_ACC_PHASE2   = 10             , // Fractional bits for Phase 2 accumulator
           parameter                     FB_SUB_PHASE2   = 10             , // Fractional bits for Phase 2 subtraction (y_i - acc)
   
           // ==========================================================================
           // Phase 2: Backward Substitution Parameters (L^H * x = z)
           // ==========================================================================
           parameter                     FB_L            = 11              , // Fractional bits for final L matrix elements
           parameter                     FB_XHAT         = 13              , // Fractional bits for final output vector x (estimated symbols)
           parameter                     FB_PROD_PHASE3  = 13              , // Fractional bits for Phase 3 product (conj(L_ji) * x_j)
           parameter                     FB_ACC_PHASE3   = 10              , // Fractional bits for Phase 3 accumulator
           parameter                     FB_SUB_PHASE3   = 10              , // Fractional bits for Phase 3 subtraction (z_i - acc)
           parameter                     FB_INV          = 12                // Fractional bits for reciprocal of diagonal (1 / L_jj)

)(
    input  wire                          clk                               ,
    input  wire                          rst                               ,
    
    // L matrix outputs (2D Unpacked Arrays)
    input wire signed [WIDTH-1:0]        l_off_re   [0:N-1][0:N-1]         ,
    input wire signed [WIDTH-1:0]        l_off_im   [0:N-1][0:N-1]         ,
    input wire signed [WIDTH-1:0]        inv_L_diag [0:N-1]                ,
    
    // y vector (full N elements per cycle)        
    input  wire                          y_valid                           ,
    input  wire signed [N*WIDTH-1:0]     y_re_flat                         ,
    input  wire signed [N*WIDTH-1:0]     y_im_flat                         ,
    
    output wire signed [N*WIDTH-1:0]     x_re_flat                         ,
    output wire signed [N*WIDTH-1:0]     x_im_flat                         ,
    output wire                          valid_out         

);
    
/*...........................................Local Parameters..................................................*/

    localparam              ELEMENTS = (N * (N + 1)) / 2; // number of lower triangular elements N=8 , ELEMENTS=64

/*...........................................Interal Signals..................................................*/
    
    // ----------------------------------------------------------------
    // Bus Unpacking/Packing for Phase 1 & 2 signals (Converts Flat to 2D Arrays)
    // ---------------------------------------------------------------- 
    wire signed [WIDTH-1:0] y_re_unpacked [0:N-1]          ;
    wire signed [WIDTH-1:0] y_im_unpacked [0:N-1]          ;
         
    wire signed [WIDTH-1:0] z_re_unpacked [0:N-1]          ;
    wire signed [WIDTH-1:0] z_im_unpacked [0:N-1]          ;
         
    wire signed [WIDTH-1:0] x_re_unpacked [0:N-1]          ;
    wire signed [WIDTH-1:0] x_im_unpacked [0:N-1]          ;

    // ----------------------------------------------------------------
    // Connecting Phase 1 & 2 signals 
    // ---------------------------------------------------------------- 
    wire                    valid_between_phases           ;

/*...........................................Submodules......................................................*/
   
    // ----------------------------------------------------------------
    // Unpacking and Packing for Phase1 & Phase2  
    // ----------------------------------------------------------------
    Unpacking_Packing_Phase_1_2 #(
        .N                              (             N                                         ),
        .WIDTH                          (             WIDTH                                     )
    ) eq_unpacking_Packing_Phase_1_2 (                      
        .clk                            (             clk                                       ),
        .rst                            (             rst                                       ),
        .x_re_unpacked                  (             x_re_unpacked                             ),
        .x_im_unpacked                  (             x_im_unpacked                             ),
        .y_re_flat                      (             y_re_flat                                 ),
        .y_im_flat                      (             y_im_flat                                 ),
        .y_re_unpacked                  (             y_re_unpacked                             ),
        .y_im_unpacked                  (             y_im_unpacked                             ),
        .x_re_flat                      (             x_re_flat                                 ),
        .x_im_flat                      (             x_im_flat                                 )
    );

    // ----------------------------------------------------------------
    // Phase 1 — Forward substitution
    // ----------------------------------------------------------------
    phase1_fwd_sub #(
        .N                              (             N                                         ),
        .WIDTH                          (             WIDTH                                     ),
        .FB_Y                           (             FB_Y                                      ),
        .FB_Z                           (             FB_Z                                      ),
        .FB_PROD_PHASE2                 (             FB_PROD_PHASE2                            ),
        .FB_ACC_PHASE2                  (             FB_ACC_PHASE2                             ),
        .FB_SUB_PHASE2                  (             FB_SUB_PHASE2                             ),
        .ROUNDING_METHOD                (             ROUNDING_METHOD                           )
    ) eq_phase1 (                       
        .clk                            (             clk                                       ),
        .rst                            (             rst                                       ),
        .valid_in                       (             y_valid                                   ),
        .L_re                           (             l_off_re                                  ),
        .L_im                           (             l_off_im                                  ),
        .inv_L                          (             inv_L_diag                                ),
        .y_re                           (             y_re_unpacked                             ),
        .y_im                           (             y_im_unpacked                             ),
        .valid_out                      (             valid_between_phases                      ),
        .z_re_out                       (             z_re_unpacked                             ),
        .z_im_out                       (             z_im_unpacked                             )
    );

    // ----------------------------------------------------------------
    // Phase 2 — Backward substitution (Outputs perfectly aligned)
    // ----------------------------------------------------------------
    phase2_back_sub #(
        .N                              (             N                                         ),
        .WIDTH                          (             WIDTH                                     ),
        .FB_L                           (             FB_L                                      ),
        .FB_Z                           (             FB_Z                                      ),
        .FB_XHAT                        (             FB_XHAT                                   ),
        .FB_INV                         (             FB_INV                                    ),
        .FB_PROD_PHASE3                 (             FB_PROD_PHASE3                            ),
        .FB_ACC_PHASE3                  (             FB_ACC_PHASE3                             ),
        .FB_SUB_PHASE3                  (             FB_SUB_PHASE3                             ),
        .ROUNDING_METHOD                (             ROUNDING_METHOD                           )
    ) eq_phase2 (                       
        .clk                            (             clk                                       ),
        .rst                            (             rst                                       ),
        .valid_in                       (             valid_between_phases                      ),
        .L_re                           (             l_off_re                                  ),
        .L_im                           (             l_off_im                                  ),
        .inv_L                          (             inv_L_diag                                ),
        .z_re                           (             z_re_unpacked                             ),
        .z_im                           (             z_im_unpacked                             ),
        .valid_out                      (             valid_out                                 ),
        .x_re_out                       (             x_re_unpacked                             ),
        .x_im_out                       (             x_im_unpacked                             )
    );

endmodule