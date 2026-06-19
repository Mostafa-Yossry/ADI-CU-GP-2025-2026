`timescale 1ns/1ps

module tb_top_system_stress;

    parameter N            = 8                       ;
    parameter WIDTH        = 16                      ;
    parameter TOTAL_FRAMES = 400                     ; // 400 frames for Flat Channel

    logic                    clk                     ;
    logic                    rst                     ;
    logic                    y_valid                 ;
     
    // Inputs for Fixed Arrays (L & inv_L)  
    logic signed [WIDTH-1:0] l_re_in [0:N-1][0:N-1]  ;
    logic signed [WIDTH-1:0] l_im_in [0:N-1][0:N-1]  ;
    logic signed [WIDTH-1:0] inv_in  [0:N-1]         ;
 
    // Inputs/Outputs for Flat Y and X  
    logic signed [N*WIDTH-1:0] y_re_flat, y_im_flat  ;
    wire  signed [N*WIDTH-1:0] x_re_flat, x_im_flat  ;
    wire                       valid_out             ;
 
    // Memory arrays to read MATLAB files
    localparam ELEMENTS = (N * (N + 1)) / 2          ;
    reg [WIDTH-1:0] mem_L_re [0:ELEMENTS-1]          ;
    reg [WIDTH-1:0] mem_L_im [0:ELEMENTS-1]          ;
    reg [WIDTH-1:0] mem_inv  [0:N-1]                 ;
    
    reg [WIDTH-1:0] mem_y_re [0:(TOTAL_FRAMES * N)-1];
    reg [WIDTH-1:0] mem_y_im [0:(TOTAL_FRAMES * N)-1];
    reg [WIDTH-1:0] exp_x_re [0:(TOTAL_FRAMES * N)-1];
    reg [WIDTH-1:0] exp_x_im [0:(TOTAL_FRAMES * N)-1];

    // Instantiate Top Module
    linear_solver_pipelined #(
                .N                  (       N                       ),
                .WIDTH              (       WIDTH                   )
        ) uut (
                .clk                (       clk                     ),
                .rst                (       rst                     ),
                .l_off_re           (       l_re_in                 ),
                .l_off_im           (       l_im_in                 ),
                .inv_L_diag         (       inv_in                  ),
                .y_valid            (       y_valid                 ),
                .y_re_flat          (       y_re_flat               ),
                .y_im_flat          (       y_im_flat               ),
                .x_re_flat          (       x_re_flat               ),
                .x_im_flat          (       x_im_flat               ),
                .valid_out          (       valid_out               )
    );              

    // Read Memory Files
    initial begin
        $readmemh("top_L_re.txt", mem_L_re);
        $readmemh("top_L_im.txt", mem_L_im);
        $readmemh("top_inv.txt" , mem_inv );
        $readmemh("top_y_re.txt", mem_y_re);
        $readmemh("top_y_im.txt", mem_y_im);
        $readmemh("top_x_re.txt", exp_x_re);
        $readmemh("top_x_im.txt", exp_x_im);
    end

    // Clock Generation
    initial
        begin 
            clk = 0   ;
            forever #5
            clk = ~clk; 
        end

    // =========================================================
    // TASK: Load L and inv_L into the 2D Arrays
    // =========================================================
    task load_flat_channel();
        integer idx;  
        idx = 0    ;     
        for (integer r = 0; r < N; r = r + 1) begin
            for (integer c = 0; c <= r; c = c + 1) begin
                l_re_in[r][c] = mem_L_re[idx];
                l_im_in[r][c] = mem_L_im[idx];
                idx = idx + 1                ;
            end
            inv_in[r] = mem_inv[r];
        end
    endtask

    // =========================================================
    // TASK: Stream Y Vectors
    // =========================================================
    task send_Y();
        for (integer f = 0; f < TOTAL_FRAMES; f = f + 1) begin
            for (integer i = 0; i < N; i = i + 1) begin
                y_re_flat[i*WIDTH +: WIDTH] <= mem_y_re[f*N + i];
                y_im_flat[i*WIDTH +: WIDTH] <= mem_y_im[f*N + i];
            end
            y_valid <= 1;
            @(posedge clk);
        end
        y_valid <= 0;
    endtask

    // =========================================================
    // AUTO-CHECKER VARIABLES 
    // =========================================================
    integer check_f = 0                                    ;
    integer err_cnt = 0                                    ;
    integer row_idx                                        ;
    logic signed [WIDTH-1:0] act_re, act_im, exp_re, exp_im;

    // =========================================================
    // MAIN TEST SEQUENCE
    // =========================================================
    initial begin
        rst       <= 0      ;
        y_valid   <= 0      ;
        y_re_flat <= 0      ;
        y_im_flat <= 0      ;
         
        // Zeroing L Matrix Default
        for(integer i=0; i<N; i++) begin
            for(integer j=0; j<N; j++) begin
                l_re_in[i][j] = 0;
                l_im_in[i][j] = 0;
            end
        end

        #25 rst <= 1;
        @(posedge clk);
        
        $display(">>> Loading Fixed L Matrix and inv_L...");
        load_flat_channel();
        @(posedge clk);

        $display(">>> Streaming 400 Y Frames Back-to-Back...");
        send_Y();
        
        // Wait for pipeline to flush
        repeat(50) @(posedge clk);
        
        if (check_f < TOTAL_FRAMES) begin
            $display("[ERROR] Simulation timeout! Missing frames.");
            $stop;
        end
    end

    // =========================================================
    // AUTO-CHECKER LOGIC (Driven by valid_out)
    // =========================================================
    always @(posedge clk) begin
        if (valid_out) begin 
            for (row_idx = 0; row_idx < N; row_idx = row_idx + 1) begin
                act_re = x_re_flat[row_idx*WIDTH +: WIDTH];
                act_im = x_im_flat[row_idx*WIDTH +: WIDTH];
                exp_re = exp_x_re[check_f*N + row_idx];
                exp_im = exp_x_im[check_f*N + row_idx];
                
                if (act_re !== exp_re || act_im !== exp_im) begin
                    $display("Mismatch Frame %0d, Element %0d | RTL: %h+j%h | MAT: %h+j%h", 
                              check_f+1, row_idx, act_re, act_im, exp_re, exp_im);
                    err_cnt++;
                end
            end
            check_f++;
            
            if (check_f == TOTAL_FRAMES) begin
                $display("\n========================================================");
                if (err_cnt == 0)
                    $display("SUCCESS! ALL 400 FRAMES PASSED THE SUBSTITUTION PIPELINE! ");
                else
                    $display("FAILED WITH %0d MISMATCHES ", err_cnt);
                $display("========================================================\n");
                $stop;
            end
        end
    end

endmodule