// ============================================================
// Module      : sqrt_pipelined
// Description : Fully Unrolled/Pipelined Square Root for Q-format
//               Supports Asymmetric Fixed-Point Arithmetic (e.g., Q8.8 to Q5.11)
//
// Latency     : WIDTH clock cycles (e.g., 16 cycles for 16-bit)
// Throughput  : 1 result per clock cycle
//
// Rounding methods (parameter ROUNDING_METHOD):
//   "FLOOR"       — q_pipe[WIDTH] directly (current behaviour).
//                   Always rounds toward zero (down for positive sqrt).
//
//   "CONVERGENT"  — round-to-nearest, which equals convergent rounding
//                   for sqrt because the half-point (q+0.5)^2 = q^2+q+0.25
//                   is never an integer, so no tie-breaking is ever needed.
//
//                   Rule: round_up = (r_pipe[WIDTH] > q_pipe[WIDTH])
//                   result = q_pipe[WIDTH] + round_up
//
//                   Derivation:
//                     true sqrt = q + frac,  frac ∈ [0,1)
//                     round up  ↔ frac >= 0.5
//                               ↔ x_ext >= (q+0.5)^2 = q^2 + q + 0.25
//                               ↔ r = x_ext - q^2 >= q + 0.25
//                               ↔ r > q  (r is integer, q+0.25 is not)
//                   Cost: one WIDTH-bit comparator + one incrementer.
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================  

module sqrt_pipelined #(
           parameter WIDTH           = 16             ,
           parameter F_IN            = 8              ,
           parameter F_OUT           = 11             ,
           parameter ROUNDING_METHOD = "CONVERGENT"   // "FLOOR" or "CONVERGENT"
)(
    input  wire             clk                       ,
    input  wire             rst                       ,
            
    input  wire             valid_in                  ,
    input  wire [WIDTH-1:0] x_in                      ,
            
    output reg              valid_out                 ,
    output reg  [WIDTH-1:0] result
);

/*...........................................Local Parameters..................................................*/
    
    // ----------------------------------------------------------------
    // 1. Input Preparation                             (Parameters)
    // ----------------------------------------------------------------
    localparam SHIFT = (2 * F_OUT) - F_IN;

/*...........................................Interal Signals..................................................*/

    // ----------------------------------------------------------------
    // 1. Input Preparation                             (Signals)
    // ---------------------------------------------------------------
    wire [2*WIDTH-1:0]   x_ext           ;

    // ----------------------------------------------------------------
    // 2. Pipeline Register Arrays                      (Signals)
    // ----------------------------------------------------------------
    reg  [2*WIDTH-1:0]   x_pipe [0:WIDTH];
    reg  [WIDTH-1  :0]   q_pipe [0:WIDTH];
    reg  [WIDTH+1  :0]   r_pipe [0:WIDTH];
    reg                  v_pipe [0:WIDTH];

    // ----------------------------------------------------------------
    // 5. Output Assignment                             (Signals)
    // ----------------------------------------------------------------
    wire                 round_up        ;  

/*...........................................Interal Logic..................................................*/
    
    // ----------------------------------------------------------------
    // 1. Input Preparation                             
    // ---------------------------------------------------------------
    assign x_ext = { {(WIDTH-SHIFT){1'b0}}, x_in, {SHIFT{1'b0}} };

    // ----------------------------------------------------------------
    // 3. Input Registration
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            x_pipe[0] <= 0           ;
            q_pipe[0] <= 0           ;
            r_pipe[0] <= 0           ;
            v_pipe[0] <= 1'b0        ;
        end 
        else begin
            x_pipe[0] <= x_ext       ;
            q_pipe[0] <= 0           ;
            r_pipe[0] <= 0           ;
            v_pipe[0] <= valid_in    ;
        end
    end

    // ----------------------------------------------------------------
    // 4. Generate Blocks: Unrolled Square Root Algorithm (Non-Restoring)
    // ----------------------------------------------------------------
    genvar current_stage;
    generate
        for (current_stage = 0; current_stage < WIDTH; current_stage = current_stage + 1) begin : gen_sqrt_stages

            wire [1:0]       x_bits  = x_pipe[current_stage][2*WIDTH - 1 - 2*(current_stage) : 2*WIDTH - 2 - 2*(current_stage)] ;
            wire [WIDTH+1:0] r_shift = {r_pipe[current_stage][WIDTH-1:0], x_bits}                                               ;
            wire [WIDTH+1:0] trial   = {q_pipe[current_stage], 2'b01}                                                           ;
            wire             can_sub = (r_shift >= trial)                                                                       ;
            wire [WIDTH+1:0] r_next  = can_sub ? (r_shift - trial) : r_shift                                                    ;       
            wire [WIDTH-1:0] q_next  = {q_pipe[current_stage][WIDTH-2:0], can_sub}                                              ;

            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    x_pipe[current_stage+1] <= 0                            ;
                    q_pipe[current_stage+1] <= 0                            ;
                    r_pipe[current_stage+1] <= 0                            ;
                    v_pipe[current_stage+1] <= 1'b0                         ;
                end 
                else begin
                    x_pipe[current_stage+1] <= x_pipe[current_stage]        ;
                    q_pipe[current_stage+1] <= q_next                       ;
                    r_pipe[current_stage+1] <= r_next                       ;
                    v_pipe[current_stage+1] <= v_pipe[current_stage]        ;
                end
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // 5. Output Assignment
    // ----------------------------------------------------------------
    // CONVERGENT: round_up = 1 when the remainder exceeds the quotient,
    //             meaning the true sqrt is closer to q+1 than to q.
    // FLOOR:      always output q as-is.
    // ----------------------------------------------------------------

    generate
        if (ROUNDING_METHOD == "CONVERGENT") begin : gen_convergent
            // r_pipe[WIDTH] is WIDTH+2 bits; q_pipe[WIDTH] is WIDTH bits.
            // Compare the lower WIDTH+1 bits of r against q (zero-extended).
            // r > q  ↔  r[WIDTH:0] > {1'b0, q_pipe[WIDTH]}
            assign round_up = (r_pipe[WIDTH][WIDTH:0] > {1'b0, q_pipe[WIDTH]});
        end 
        else begin : gen_floor
            assign round_up = 1'b0;
        end
    endgenerate

    always @(*) begin
        valid_out = v_pipe[WIDTH]                                ;
        result    = q_pipe[WIDTH] + {{(WIDTH-1){1'b0}}, round_up};
    end

endmodule