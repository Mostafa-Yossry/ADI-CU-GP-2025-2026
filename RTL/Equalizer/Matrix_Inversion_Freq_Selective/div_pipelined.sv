// ============================================================
// Module      : div_pipelined
// Description : Fully Unrolled/Pipelined Unsigned Divider
//               Supports dynamic fractional alignment.
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// Latency     : WIDTH clock cycles
// Throughput  : 1 result per clock cycle
//
// Rounding methods (parameter ROUNDING_METHOD):
//   "FLOOR"       — quo_pipe[WIDTH] directly (current behaviour).
//                   Always rounds toward zero (truncation).
//
//   "CONVERGENT"  — round-half-to-even (banker's rounding).
//                   Eliminates systematic bias at half-points.
//
//                   Rule: round_up = (2r > den) | (2r == den & q[0])
//                   result = q + round_up
//
//                   Derivation:
//                     true quotient = q + r/den,  0 <= r < den
//                     round up  ↔  r/den >  0.5  ↔  2r > den   (above half)
//                     stay down ↔  r/den <  0.5  ↔  2r < den   (below half)
//                     at half   ↔  r/den == 0.5  ↔  2r == den  → round to even (q[0])
//                   Cost: one left-shift, two comparators, one AND/OR gate,
//                         one incrementer — all combinational at the output.
// ============================================================  


module div_pipelined #(
           parameter            WIDTH           = 16            ,
           parameter            FB_NUM          = 12            ,
           parameter            FB_DEN          = 10            ,
           parameter            FB_OUT          = 11            ,
           parameter            ROUNDING_METHOD = "CONVERGENT"   // "FLOOR" or "CONVERGENT"
)(
    input  wire                 clk                             ,
    input  wire                 rst                             ,

    input  wire                 valid_in                        ,
    input  wire [WIDTH-1:0]     num_in                          ,
    input  wire [WIDTH-1:0]     den_in                          ,

    output reg                  valid_out                       ,
    output reg  [WIDTH-1:0]     quo_out
);

/*...........................................Local Parameters..................................................*/

    // ----------------------------------------------------------------
    // 1. Input Preparation (Dynamic Fixed-point Alignment)
    // ----------------------------------------------------------------
    
    localparam TARGET_NUM_FBITS = FB_OUT + FB_DEN                                       ;
    localparam SHIFT_L = (TARGET_NUM_FBITS > FB_NUM) ? (TARGET_NUM_FBITS - FB_NUM) : 0  ;
    localparam SHIFT_R = (FB_NUM > TARGET_NUM_FBITS) ? (FB_NUM - TARGET_NUM_FBITS) : 0  ;

/*...........................................Interal Signals..................................................*/

    // ----------------------------------------------------------------
    // 1. Input Preparation (Dynamic Fixed-point Alignment) (signals)
    // ----------------------------------------------------------------

    wire [(2*WIDTH)-1:0] num_ext                            ;
    wire [(2*WIDTH)-1:0] num_aligned                        ;

    // ----------------------------------------------------------------
    // 2. Pipeline Register Arrays                          (signals)
    // ----------------------------------------------------------------

    reg  [WIDTH-1:0]   num_pipe [0:WIDTH]                   ;
    reg  [WIDTH-1:0]   den_pipe [0:WIDTH]                   ;
    reg  [WIDTH-1:0]   quo_pipe [0:WIDTH]                   ;
    reg  [WIDTH  :0]   rem_pipe [0:WIDTH]                   ;
    reg                val_pipe [0:WIDTH]                   ;

    // ----------------------------------------------------------------
    // 5. Output Assignment                                 (signals)
    // ----------------------------------------------------------------
    
    wire [WIDTH:0]   doubled_rem                            ;
    wire             above_half                             ;
    wire             at_half                                ;
    wire             lsb_q                                  ;
    wire             round_up                               ;

/*...........................................Interal Logic..................................................*/

    // ----------------------------------------------------------------
    // 1. Input Preparation (Dynamic Fixed-point Alignment)
    // ----------------------------------------------------------------

    assign num_ext     = { {WIDTH{1'b0}}, num_in };
    assign num_aligned = (SHIFT_L > 0) ? (num_ext << SHIFT_L) : (num_ext >> SHIFT_R);

    // ----------------------------------------------------------------
    // 3. Input Registration
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            num_pipe[0] <= 0                                        ;
            den_pipe[0] <= 0                                        ;
            quo_pipe[0] <= 0                                        ;
            rem_pipe[0] <= 0                                        ;
            val_pipe[0] <= 1'b0                                     ;
        end 
        else begin
            num_pipe[0] <= num_aligned[WIDTH-1:0]                   ;
            den_pipe[0] <= den_in                                   ;
            quo_pipe[0] <= 0                                        ;
            rem_pipe[0] <= {1'b0, num_aligned[(2*WIDTH)-1:WIDTH]}   ;
            val_pipe[0] <= valid_in                                 ;
        end
    end

    // ----------------------------------------------------------------
    // 4. Generate Blocks: Unrolled Restoring Division
    // ----------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : gen_div_stages

            wire [WIDTH:0]   rem_shifted = {rem_pipe[i][WIDTH-1:0], num_pipe[i][WIDTH-1-i]}            ;
            wire             can_sub     = (rem_shifted >= {1'b0, den_pipe[i]})                        ;
            wire [WIDTH:0]   rem_next    = can_sub ? (rem_shifted - {1'b0, den_pipe[i]}) : rem_shifted ;
            wire [WIDTH-1:0] quo_next    = {quo_pipe[i][WIDTH-2:0], can_sub}                           ;

            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    num_pipe[i+1] <= 0                  ;
                    den_pipe[i+1] <= 0                  ;
                    quo_pipe[i+1] <= 0                  ;
                    rem_pipe[i+1] <= 0                  ;
                    val_pipe[i+1] <= 1'b0               ;
                end 
                else begin
                    num_pipe[i+1] <= num_pipe[i]        ;
                    den_pipe[i+1] <= den_pipe[i]        ;
                    quo_pipe[i+1] <= quo_next           ;
                    rem_pipe[i+1] <= rem_next           ;
                    val_pipe[i+1] <= val_pipe[i]        ;
                end
            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // 5. Output Assignment
    // ----------------------------------------------------------------
    // CONVERGENT rounding signals:
    //   doubled_rem : 2 * remainder — compare against denominator
    //   above_half  : remainder strictly above halfway → always round up
    //   at_half     : remainder exactly halfway → round to even (use LSB of q)
    //   lsb_q       : LSB of floor quotient — determines even/odd for tie-break
    //   round_up    : final round decision
    // ----------------------------------------------------------------

    generate
        if (ROUNDING_METHOD == "CONVERGENT") begin : gen_convergent

            // Shift rem left by 1 — use WIDTH+1 bits to avoid overflow
            // rem_pipe[WIDTH] is WIDTH+1 bits; its value is 0..den-1 < 2^WIDTH
            // so rem_pipe[WIDTH][WIDTH-1:0] << 1 is safe in WIDTH+1 bits
            assign doubled_rem = {rem_pipe[WIDTH][WIDTH-1:0], 1'b0}         ;
            assign above_half  = (doubled_rem >  {1'b0, den_pipe[WIDTH]})   ;
            assign at_half     = (doubled_rem == {1'b0, den_pipe[WIDTH]})   ;
            assign lsb_q       = quo_pipe[WIDTH][0]                         ;                    
            assign round_up    = above_half | (at_half & lsb_q)             ;

        end 
        else begin : gen_floor

            assign doubled_rem = {(WIDTH+1){1'b0}}                          ;
            assign above_half  = 1'b0                                       ;
            assign at_half     = 1'b0                                       ;
            assign lsb_q       = 1'b0                                       ;
            assign round_up    = 1'b0                                       ;

        end
    endgenerate

    always @(*) begin
        valid_out = val_pipe[WIDTH]                                  ;
        quo_out   = quo_pipe[WIDTH] + {{(WIDTH-1){1'b0}}, round_up}  ;
    end

endmodule