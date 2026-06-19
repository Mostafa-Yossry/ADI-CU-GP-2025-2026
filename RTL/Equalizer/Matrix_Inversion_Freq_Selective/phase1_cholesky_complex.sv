// ============================================================
// Module      : phase1_cholesky_complex  (CONFIGURABLE NxN VERSION)
// Description : Top-level orchestrator for the NxN complex Cholesky decomposition.
//               Instantiates N diagonal PEs (pe_diagonal_complex) and N*(N-1)/2
//               off-diagonal PEs (pe_off_diagonal_complex) and connects them into a
//               true systolic array using two nested generate loops: the outer loop
//               over diagonal index k builds PE_diag(k,k) with N_COLS=k column
//               contributions; the inner double loop over (row, col) builds
//               PE_off(row,col) with N_PRIOR=col prior columns and wires the
//               flat-packed l_left / l_top buses from previously computed L elements.
//               An update-trigger counter waits UPDATE_INTERVAL cycles after valid_in
//               before latching all PE outputs into output registers; this ensures
//               the registers hold fully settled values regardless of the pipeline
//               depth of the deepest PE. The valid_out pulse signals downstream
//               modules that a fresh L matrix and inverse vector are available.
// 
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================

module phase1_cholesky_complex #(
           parameter                N               = 3         ,
           parameter                WIDTH           = 12        ,
           parameter                ELEMENTS        = 36        ,
           //Diagonal Parameters        
           parameter                FB_G            = 8         ,   
           parameter                FB_MAG2         = 12        ,  
           parameter                FB_ACC_DIAG     = 10        ,  
           parameter                FB_SQRT_IN      = 8         ,   
           parameter                FB_SQRT_OUT     = 11        ,  
           //off-Diagonal Parameters   
           parameter                FB_L            = 11        ,
           parameter                FB_PROD_OFF     = 13        , 
           parameter                FB_ACC_OFF      = 10        , 
           parameter                FB_SUB_OFF      = 12        , 
           parameter                FB_INV          = 12        ,
           parameter                FB_MAG2_OUT     = 12        ,
           parameter                UPDATE_INTERVAL = 150       ,
           parameter                ROUNDING_METHOD = "CONVERGENT" // "FLOOR" or "CONVERGENT"                   

)(                  
    input  wire                     clk                         ,
    input  wire                     rst                         ,
    input  wire                     valid_in                    ,

    // Lower-triangle of G matrix (2D Unpacked Arrays)
    // Diagonals (real only):  g_diag_in[i]
    // Off-diagonals (complex): g_off_re_in[i][j], i>j
    input  wire signed [WIDTH-1:0]  g_diag_in   [0:N-1]         ,
    input  wire signed [WIDTH-1:0]  g_off_re_in [0:N-1][0:N-1]  ,
    input  wire signed [WIDTH-1:0]  g_off_im_in [0:N-1][0:N-1]  ,

    output wire                     valid_out                   ,

    // L matrix outputs (2D Unpacked Arrays)
    output wire signed [WIDTH-1:0]  l_off_re_out [0:N-1][0:N-1] ,
    output wire signed [WIDTH-1:0]  l_off_im_out [0:N-1][0:N-1] ,
    output wire signed [WIDTH-1:0]  inv_out      [0:N-1]
);

/*...........................................Local Parameters..................................................*/

    localparam              MAX_COUNT = UPDATE_INTERVAL - ELEMENTS - 2  ; // wait 400 cycle until all L elements be reay

/*...........................................Interal Signals..................................................*/
    
    // ------------------------------------------------------------------------
    // Internal wires for diagonal PEs 
    // ------------------------------------------------------------------------
    wire signed [WIDTH-1:0] l_diag_re [0:N-1]                           ;
    wire signed [WIDTH-1:0] adiag_off [0:N-1][0:N-1]                    ;
    
    // ------------------------------------------------------------------------
    // Internal wires for off-diagonal PEs
    // ------------------------------------------------------------------------
    wire signed [WIDTH-1:0] l_off_re  [0:N-1][0:N-1]                    ;
    wire signed [WIDTH-1:0] l_off_im  [0:N-1][0:N-1]                    ;
    
    // ------------------------------------------------------------------------
    // Internal wires for diagonal and off-diagonal PEs
    // ------------------------------------------------------------------------
    wire signed [WIDTH-1:0] inv_arr   [0:N-1]                           ;
    wire                    v_diag    [0:N-1]                           ;
    wire                    v_off     [0:N-1][0:N-1]                    ;
    wire                    vd_off    [0:N-1][0:N-1]                    ;

    // ------------------------------------------------------------------------
    // Configurable update trigger Signals
    // ------------------------------------------------------------------------
    reg [$clog2(UPDATE_INTERVAL)-1:0] counter                           ;
    reg counting, l_ready                                               ;
    wire update_trigger                                                 ;
    // ------------------------------------------------------------------------
    // Output registers signals — latch L and inv on update_trigger (2D Arrays)
    // ------------------------------------------------------------------------
    
    reg signed [WIDTH-1:0] l_off_re_reg [0:N-1][0:N-1]                  ;
    reg signed [WIDTH-1:0] l_off_im_reg [0:N-1][0:N-1]                  ;
    reg signed [WIDTH-1:0] inv_reg      [0:N-1]                         ;
    reg                    valid_out_reg                                ;

/*........................................... generate blocks......................................................*/

    // ----------------------------------------------------------------
    // Generate diagonal PEs
    // ----------------------------------------------------------------

    genvar diag_indx , column_indx;
    generate
        for (diag_indx = 0 ; diag_indx < N ; diag_indx = diag_indx + 1) begin : gen_diag_pe

            localparam                       NUM_BITS = ( diag_indx > 0 ) ? diag_indx : 1        ;
            wire        [NUM_BITS-1 : 0]     vcol                                                ;
            wire signed [NUM_BITS*WIDTH-1:0] acol                                                ;

            // Preparing the needed off-diagonal elements e.g : for L11 we need L10  
            for (column_indx = 0 ; column_indx < diag_indx ; column_indx = column_indx + 1) begin : build_col_inputs
                assign vcol[column_indx]                    = vd_off   [diag_indx][column_indx]  ;
                assign acol[column_indx*WIDTH +: WIDTH]     = adiag_off[diag_indx][column_indx]  ;
            end

            pe_diagonal_complex #(
                .WIDTH                      (       WIDTH                                               ),
                .FB_G                       (       FB_G                                                ), 
                .FB_MAG2                    (       FB_MAG2                                             ),
                .FB_ACC_DIAG                (       FB_ACC_DIAG                                         ),
                .FB_SQRT_IN                 (       FB_SQRT_IN                                          ), 
                .FB_SQRT_OUT                (       FB_SQRT_OUT                                         ),
                .FB_L                       (       FB_L                                                ),
                .FB_INV                     (       FB_INV                                              ),
                .N_COLS                     (       diag_indx                                           ),
                .ROUNDING_METHOD            (       ROUNDING_METHOD                                     )
            ) eq_diag (       
                .clk                        (       clk                                                 ),
                .rst                        (       rst                                                 ),
                .valid_in                   (       valid_in                                            ),
                .a_in                       (       g_diag_in[diag_indx]                                ), 
                .valid_col                  (       diag_indx > 0 ? vcol : 1'b0                         ),
                .a_col_in                   (       diag_indx > 0 ? acol : {WIDTH{1'b0}}                ),
                .valid_out                  (       v_diag    [diag_indx]                               ),
                .l_out                      (       l_diag_re [diag_indx]                               ),
                .l_inv_out                  (       inv_arr   [diag_indx]                               )
            );
        end
    endgenerate

    // ----------------------------------------------------------------
    // Generate off-diagonal PEs
    // ----------------------------------------------------------------

    genvar current_row_indx, current_col_indx, current_prior_indx;
    generate
        for (current_row_indx = 0 ; current_row_indx < N ; current_row_indx = current_row_indx + 1) begin : gen_row
            for (current_col_indx = 0; current_col_indx < current_row_indx; current_col_indx = current_col_indx + 1) begin : gen_col
                localparam                             N_PRIOR = ( current_col_indx > 0 ) ? current_col_indx : 1               ;
                wire signed [( N_PRIOR * WIDTH ) -1:0] ll_re_flat, ll_im_flat                                                  ;
                wire signed [( N_PRIOR * WIDTH ) -1:0] lt_re_flat, lt_im_flat                                                  ;
                
                for (current_prior_indx = 0 ; current_prior_indx < current_col_indx ; current_prior_indx = current_prior_indx + 1) begin : build_prior
                    assign ll_re_flat[( current_prior_indx * WIDTH) +: WIDTH] = l_off_re[current_row_indx][current_prior_indx] ;
                    assign ll_im_flat[( current_prior_indx * WIDTH) +: WIDTH] = l_off_im[current_row_indx][current_prior_indx] ;
                    assign lt_re_flat[( current_prior_indx * WIDTH) +: WIDTH] = l_off_re[current_col_indx][current_prior_indx] ;
                    assign lt_im_flat[( current_prior_indx * WIDTH) +: WIDTH] = l_off_im[current_col_indx][current_prior_indx] ;
                end

                pe_off_diagonal_complex #(
                    .WIDTH                  (      WIDTH                                                   ),
                    .FB_L                   (      FB_L                                                    ), 
                    .FB_G                   (      FB_G                                                    ),  
                    .FB_PROD_OFF            (      FB_PROD_OFF                                             ), 
                    .FB_ACC_OFF             (      FB_ACC_OFF                                              ), 
                    .FB_SUB_OFF             (      FB_SUB_OFF                                              ), 
                    .FB_INV                 (      FB_INV                                                  ), 
                    .FB_MAG2_OUT            (      FB_MAG2_OUT                                             ), 
                    .N_PRIOR                (      current_col_indx                                        ),
                    .ROUNDING_METHOD        (      ROUNDING_METHOD                                         )
                ) eq_off (
                    .clk                    (       clk                                                    ),
                    .rst                    (       rst                                                    ),
                    .valid_in               (       v_diag     [current_col_indx]                          ),          
                    .a_in_re                (       g_off_re_in[current_row_indx][current_col_indx]        ), 
                    .a_in_im                (       g_off_im_in[current_row_indx][current_col_indx]        ), 
                    .l_left_flat_re         (       current_col_indx > 0 ? ll_re_flat : {WIDTH{1'b0}}      ),
                    .l_left_flat_im         (       current_col_indx > 0 ? ll_im_flat : {WIDTH{1'b0}}      ),
                    .l_top_flat_re          (       current_col_indx > 0 ? lt_re_flat : {WIDTH{1'b0}}      ),
                    .l_top_flat_im          (       current_col_indx > 0 ? lt_im_flat : {WIDTH{1'b0}}      ),
                    .l_inv                  (       inv_arr    [current_col_indx]                          ),
                    .valid_out              (       v_off      [current_row_indx][current_col_indx]        ),
                    .l_out_re               (       l_off_re   [current_row_indx][current_col_indx]        ),
                    .l_out_im               (       l_off_im   [current_row_indx][current_col_indx]        ),
                    .valid_diag             (       vd_off     [current_row_indx][current_col_indx]        ),
                    .a_diag_out             (       adiag_off  [current_row_indx][current_col_indx]        )
                );                 
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // Configurable update trigger (waiting until all L elemtns be ready)
    // ------------------------------------------------------------------

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            counter  <= 0;
            counting <= 0; 
            l_ready  <= 0;
        end 
        else begin
            if (valid_in) begin
                counting <= 1;
                counter  <= 0;
                l_ready  <= 0;
            end 
            else if (counting) begin
                if (counter == MAX_COUNT) begin
                    counting <= 0;
                end 
                else begin
                    counter  <= counter + 1;
                end
            end
            if (v_diag[N-1]) begin
                l_ready <= 1;
            end
        end
    end

    assign update_trigger = (counting && counter == MAX_COUNT) && (l_ready);

    // ----------------------------------------------------------------
    // Output registers — latch L and inv on update_trigger (2D Arrays)
    // ----------------------------------------------------------------

    integer current_row_indx_out, current_col_indx_out; // loop variables for easy Synthesis
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            valid_out_reg <= 0;
            for (current_row_indx_out = 0; current_row_indx_out < N; current_row_indx_out = current_row_indx_out + 1) begin
                inv_reg[current_row_indx_out] <= 0;
                for (current_col_indx_out = 0; current_col_indx_out < N; current_col_indx_out = current_col_indx_out + 1) begin
                    l_off_re_reg[current_row_indx_out][current_col_indx_out] <= 0;
                    l_off_im_reg[current_row_indx_out][current_col_indx_out] <= 0;
                end
            end
        end 
        else begin
            valid_out_reg <= update_trigger;
            if (update_trigger) begin
                for (current_row_indx_out = 0; current_row_indx_out < N; current_row_indx_out = current_row_indx_out + 1) begin
                    inv_reg[current_row_indx_out] <= inv_arr[current_row_indx_out];
                    for (current_col_indx_out = 0; current_col_indx_out < current_row_indx_out; current_col_indx_out = current_col_indx_out + 1) begin
                        l_off_re_reg[current_row_indx_out][current_col_indx_out] <= l_off_re[current_row_indx_out][current_col_indx_out];
                        l_off_im_reg[current_row_indx_out][current_col_indx_out] <= l_off_im[current_row_indx_out][current_col_indx_out];
                    end
                end
            end
        end
    end
   
    // ----------------------------------------------------------------
    // Direct assignment to the output
    // ----------------------------------------------------------------
    
    assign valid_out    = valid_out_reg;
    assign l_off_re_out = l_off_re_reg ; 
    assign l_off_im_out = l_off_im_reg ; 
    assign inv_out      = inv_reg      ;

endmodule