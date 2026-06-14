// ============================================================
// Module      : smart_round
// Description : Parameterized Rounding Module supporting both 
//               CONVERGENT (Banker's) and FLOOR (Truncation) modes.
//               (Bulletproof Signed Arithmetic Version)
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// ============================================================  
module smart_round #(
    parameter WIDTH           = 16,
    parameter SHIFT           = 0,
    parameter ROUNDING_METHOD = "CONVERGENT"  // "FLOOR" or "CONVERGENT"
)(
    input  wire signed [WIDTH-1:0] d_in,
    output wire signed [WIDTH-1:0] d_out
);
    generate
        if (SHIFT > 0) begin : gen_shift
            wire signed [WIDTH-1:0] shifted_val = d_in >>> SHIFT;

            if (ROUNDING_METHOD == "CONVERGENT") begin : gen_convergent
                wire round_bit  = d_in[SHIFT - 1];
                wire lsb        = d_in[SHIFT];

                wire [31:0] mask_32 = (32'd1 << (SHIFT - 1)) - 1;
                wire [WIDTH-1:0] mask = mask_32[WIDTH-1:0];
                wire sticky_bit = |(d_in & mask);

                wire round_up   = round_bit & (sticky_bit | lsb);

                wire signed [WIDTH-1:0] round_val = round_up;
                
                assign d_out = shifted_val + round_val;
            end 
            else begin : gen_floor
                assign d_out = shifted_val;
            end
        end else begin : gen_no_shift
            assign d_out = d_in;
        end
    endgenerate
endmodule