// ============================================================
// Module      : G_matrix_deserializer
// Description : Receives the lower triangle of the Hermitian Gram matrix G one
//               element per clock cycle over a serial interface and reconstructs
//               the full 2-D unpacked register arrays g_diag, g_off_re, and g_off_im
//               needed by phase1_cholesky_complex. A (row, col) counter walks the
//               lower-triangle in column-major order: diagonal elements (row == col)
//               are stored as real-only scalars in g_diag; off-diagonal elements
//               (row > col) are stored as complex pairs in g_off_re / g_off_im.
//               When the element counter reaches ELEMENTS - 1 (all lower-triangle
//               entries received), the module asserts phase1_start for one clock
//               cycle to trigger the Cholesky engine, then resets the counter for
//               the next G matrix. If g_valid deasserts mid-frame the counters
//               reset to zero, preventing partially loaded matrices from being
//               processed.
//
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================    

module G_matrix_deserializer #(
           parameter                     N               = 8        ,
           parameter                     WIDTH           = 16       ,
           parameter                     ELEMENTS        = 36        
)(
    input  wire                          clk                        ,
    input  wire                          rst                        ,

    // G matrix (serialized lower triangle)
    input  wire                          g_valid                    ,
    input  wire  signed [WIDTH-1:0]      g_re_in                    ,
    input  wire  signed [WIDTH-1:0]      g_im_in                    ,
    
    // G matrix (De-serialized lower triangle)
    output reg   signed [WIDTH-1:0]      g_diag     [0:N-1]         ,
    output reg   signed [WIDTH-1:0]      g_off_re   [0:N-1][0:N-1]  ,
    output reg   signed [WIDTH-1:0]      g_off_im   [0:N-1][0:N-1]  ,
             
    // Phase1 Valid_in
    output reg   signed                  phase1_start
);

/*...........................................Interal Signals..................................................*/

    reg [$clog2(ELEMENTS)-1:0] g_cnt       ;
    reg [$clog2(N)-1:0]        g_row, g_col;

/*...........................................Internal Logic.......................................................*/

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            g_cnt        <= 0;
            phase1_start <= 0;
            g_row        <= 0;
            g_col        <= 0;
            begin : rst_loop
                for (integer current_row_indx = 0; current_row_indx < N; current_row_indx = current_row_indx + 1) begin
                    g_diag[current_row_indx] <= 0;
                    for (integer current_col_indx = 0; current_col_indx < N; current_col_indx = current_col_indx + 1) begin
                        g_off_re[current_row_indx][current_col_indx] <= 0;
                        g_off_im[current_row_indx][current_col_indx] <= 0;
                    end
                end
            end
        end 
        else begin
            phase1_start <= 1'b0;
            if (g_valid) begin
                if (g_row == g_col) begin
                    g_diag[g_row] <= g_re_in ;
                end 
                else begin
                    g_off_re[g_row][g_col] <= g_re_in;
                    g_off_im[g_row][g_col] <= g_im_in;
                end

                if (g_cnt == ELEMENTS - 1) begin
                    g_cnt        <= 0   ;
                    g_row        <= 0   ;
                    g_col        <= 0   ;
                    phase1_start <= 1'b1;
                end 
                else begin
                    g_cnt <= g_cnt + 1;
                    if (g_col == g_row) begin
                        g_row <= g_row + 1;
                        g_col <= 0        ;
                    end 
                    else begin
                        g_col <= g_col + 1;
                    end
                end
            end 
            else begin
                g_cnt <= 0;
                g_row <= 0;
                g_col <= 0;
            end
        end
    end
endmodule