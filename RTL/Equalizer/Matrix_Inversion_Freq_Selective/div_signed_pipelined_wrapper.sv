// ============================================================
// Module      : div_signed_pipelined_wrapper
// Description : A thin signed wrapper around div_pipelined. Because the core divider
//               operates on unsigned values, this module extracts the signs of the
//               numerator and denominator with a single XOR to compute the output
//               sign, then passes the absolute values to the unsigned core. The
//               output sign bit is pipelined through a WIDTH+1-stage shift register
//               so it arrives at the output in the same clock cycle as the unsigned
//               quotient, and is then applied with a conditional negation. All
//               fixed-point format parameters (FB_NUM, FB_DEN, FB_OUT) and the
//               ROUNDING_METHOD are forwarded transparently to the inner core.
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================

module div_signed_pipelined_wrapper #(
           parameter                WIDTH           = 16            ,
           parameter                FB_NUM          = 12            ,
           parameter                FB_DEN          = 10            ,
           parameter                FB_OUT          = 11            ,
           parameter                ROUNDING_METHOD = "CONVERGENT"   // "FLOOR" or "CONVERGENT"

)(
    input  wire                     clk                             ,
    input  wire                     rst                             ,

    input  wire                     valid_in                        ,
    input  wire signed [WIDTH-1:0]  num_in                          ,
    input  wire signed [WIDTH-1:0]  den_in                          ,

    output wire                     valid_out                       ,
    output wire signed [WIDTH-1:0]  quo_out
);

/*...........................................Interal Signals..................................................*/
    // Determine signs
    wire num_sign                 = num_in[WIDTH-1]                         ;
    wire den_sign                 = den_in[WIDTH-1]                         ;
    wire out_sign                 = num_sign ^ den_sign                     ;
    
    // Get absolute values
    wire [WIDTH-1:0] abs_num      = num_sign ? -num_in : num_in             ;
    wire [WIDTH-1:0] abs_den      = den_sign ? -den_in : den_in             ;
    wire [WIDTH-1:0] unsigned_quo                                           ;
    
    // Pipeline the sign bit so it matches the latency of the divider
    reg [WIDTH   :0] sign_pipe                                              ;
    
/*...........................................Core Logic........................................................*/    
    
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            sign_pipe <= 0                               ; 
        end 
        else begin
            // Shift register for the sign bit (Latency = WIDTH cycles + 1 for input reg)
            sign_pipe <= {sign_pipe[WIDTH-1:0], out_sign};
        end
    end

    // Instantiate Unsigned Pipelined Divider with dynamic parameters
    div_pipelined #(
            .WIDTH                      (              WIDTH               ),
            .FB_NUM                     (              FB_NUM              ),
            .FB_DEN                     (              FB_DEN              ),
            .FB_OUT                     (              FB_OUT              ),
            .ROUNDING_METHOD            (              ROUNDING_METHOD     )
    ) eq_unsigned_div (
            .clk                        (              clk                 ),
            .rst                        (              rst                 ),
            .valid_in                   (              valid_in            ),
            .num_in                     (              abs_num             ),
            .den_in                     (              abs_den             ),
            .valid_out                  (              valid_out           ),
            .quo_out                    (              unsigned_quo        )
    );

    // Apply the delayed sign to the output
    assign quo_out = sign_pipe[WIDTH] ? -unsigned_quo : unsigned_quo;

endmodule