// ============================================================================
// Module: convround
// ============================================================================
// Purpose:	A convergent rounding routine, also known as banker's
//		rounding, Dutch rounding, Gaussian rounding, unbiased
//	rounding, or ... more, at least according to Wikipedia.
//
//	This form of rounding works by rounding, when the direction is in
//	question, towards the nearest even value.

`default_nettype	none

module  convround(i_clk, i_clk_enable, i_val, o_val);
    // --- Configuration ---
    parameter   IWID=16;       // Input Bit Width
    parameter   OWID=8;        // Output Bit Width
    parameter   SHIFT=0;       // Optional MSB bit-drop (scaling)
    
    input   wire                        i_clk, i_clk_enable;
    input   wire    signed  [(IWID-1):0]    i_val;
    output  reg     signed  [(OWID-1):0]    o_val;

    // Use Verilog 'generate' to create different hardware based on 
    // the relationship between Input Width and Output Width.
    generate
    // ========================================================================
    // CASE 1: Pass-Through (No Rounding)
    // ========================================================================
    // If input and output widths match, just pass the data.
    if (IWID == OWID) 
    begin : NO_ROUNDING 
        always @(posedge i_clk)
        if (i_clk_enable)   o_val <= i_val[(IWID-1):0];
    end 
    // ========================================================================
    // CASE 2: Sign Extension (Bit Growth)
    // ========================================================================
    // If Output > Input, we need to pad the MSBs with the sign bit.
    // Example: Input 16 bit, Output 18 bit.
    else if (IWID-SHIFT < OWID)
    begin : ADD_BITS_TO_OUTPUT 
        always @(posedge i_clk)
        if (i_clk_enable)   
            // Concatenate {Sign Bits, Original Value}
            o_val <= { {(OWID-IWID+SHIFT){i_val[IWID-SHIFT-1]}}, i_val[(IWID-SHIFT-1):0] };
    end 
    // ========================================================================
    // CASE 3: MSB Drop Only (Rare)
    // ========================================================================
    // If the difference is exactly accounted for by the SHIFT parameter.
    else if (IWID-SHIFT == OWID)
    begin : SHIFT_ONE_BIT
        always @(posedge i_clk)
        if (i_clk_enable)   o_val <= i_val[(IWID-SHIFT-1):0];
    end 
    // ========================================================================
    // CASE 4: Dropping Exactly 1 Bit (The 0.5 Bit)
    // ========================================================================
    // We are dropping the LSB. This LSB represents exactly 0.5.
    // Rule: Round to the nearest EVEN number.
    else if (IWID-SHIFT-1 == OWID)
    begin : DROP_ONE_BIT 
        wire    [(OWID-1):0]    truncated_value, rounded_up;
        wire                    last_valid_bit, first_lost_bit;
        // The bits we intend to keep (Floor)
        assign  truncated_value = i_val[(IWID-1-SHIFT):(IWID-SHIFT-OWID)];
        // The value if we were to round up (Add 1)
        assign  rounded_up      = truncated_value + {{(OWID-1){1'b0}}, 1'b1 };
        // "Last Valid": The LSB of the part we keep.
        assign  last_valid_bit  = truncated_value[0];
        // "First Lost": The bit we are dropping.
        assign  first_lost_bit  = i_val[0]; // (assuming slicing aligns to 0)
        always @(posedge i_clk)
        if (i_clk_enable)
        begin
            // Logic:
            // 1. If lost bit is 0: Value was X.0 -> Stay at X (Truncate).
            if (!first_lost_bit) 
                o_val <= truncated_value;
            
            // 2. If lost bit is 1: Value was X.5 (Exactly halfway).
            //    We must round to EVEN.
            //    - If last_valid is 1 (Odd), add 1 to make it Even (Round Up).
            else if (last_valid_bit)
                o_val <= rounded_up; 
            //    - If last_valid is 0 (Even), add 0 to keep it Even (Round Down).
            else 
                o_val <= truncated_value; 
        end
    end 
    // ========================================================================
    // CASE 5: Dropping Multiple Bits (Standard 5G Case)
    // ========================================================================
    // Example: 16 bits -> 12 bits (Drop 4 bits).
    // The MSB of the dropped bits is 0.5 (Guard Bit).
    // All lower dropped bits form the "Sticky Bit" (Remainder).
    else 
    begin : ROUND_RESULT
        wire    [(OWID-1):0]    truncated_value, rounded_up;
        wire                    last_valid_bit, first_lost_bit;
        // Extract the integer part (Truncated)
        assign  truncated_value = i_val[(IWID-1-SHIFT):(IWID-SHIFT-OWID)];
        // Calculate the value + 1
        assign  rounded_up      = truncated_value + {{(OWID-1){1'b0}}, 1'b1 };
        // LSB of the kept part (Determines Odd/Even)
        assign  last_valid_bit  = truncated_value[0];
        // MSB of the dropped part (The 0.5 place)
        assign  first_lost_bit  = i_val[(IWID-SHIFT-OWID-1)];
        // OR-reduce all remaining lower bits (The Sticky Bit)
        // If ANY of these are 1, the value is strictly > 0.5
        wire    [(IWID-SHIFT-OWID-2):0] other_lost_bits;
        assign  other_lost_bits = i_val[(IWID-SHIFT-OWID-2):0];

        always @(posedge i_clk)
            if (i_clk_enable)
            begin
                // Condition 1: Fraction < 0.5 (Guard bit is 0)
                // Action: Round Down.
                if (!first_lost_bit) 
                    o_val <= truncated_value;        
                // Condition 2: Fraction > 0.5 (Guard is 1, and Sticky is 1)
                // Action: Round Up (Standard rounding).
                else if (|other_lost_bits) 
                    o_val <= rounded_up; 
                // Condition 3: Fraction == 0.5 (Guard is 1, Sticky is 0)
                // Action: Convergent Rounding (Round to Even).
                // If current LSB is 1 (Odd), Round Up to make it Even.
                else if (last_valid_bit) 
                    o_val <= rounded_up; 
                // If current LSB is 0 (Even), Round Down to keep it Even.
                else                    
                    o_val <= truncated_value;
            end
    end
    endgenerate
endmodule
