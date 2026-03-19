module convergent_rounding #(parameter DATA_WIDTH=12) (
    input  wire signed [DATA_WIDTH:0]       inter_sum_r, inter_sum_i,
    input  wire signed [2*DATA_WIDTH+1:0]   temp_mult_out_r, temp_mult_out_i,
    input  wire        [3:0]                Q_in, Q_sum, Q_diff, Q_mult, Q_out,
    input  wire                             rot_en,
    output reg  signed [DATA_WIDTH-1:0]     out_r, out_i  
);

    /*convergent for summition*/ 
    reg                       round_bit_r, round_bit_i;
    reg signed [DATA_WIDTH:0] rounded_sum_r, rounded_sum_i;
    reg signed [DATA_WIDTH:0] sum_r, sum_i;

    /*convergent for Multiplication*/ 
    // 26-bit wide registers to hold the rounded results safely before saturation
    reg signed [2*DATA_WIDTH+1:0] rounded_mult_r, rounded_mult_i;
    reg signed [DATA_WIDTH-1:0]   mult_out_r, mult_out_i;

    // Convergent Rounding Variables
    reg L_r, R_r, S_r, L_i, R_i, S_i;

always @(*) begin 
    
    // Default assignments to prevent inferred latches
    out_r = 0; out_i = 0;
    sum_r = 0; sum_i = 0;
    rounded_mult_r = 0; rounded_mult_i = 0;
    mult_out_r = 0; mult_out_i = 0;

    /* the output from the multiplication */
    if(rot_en) begin
        /* -----------------------------------------------------------------
           1. APPLY L-R-S CONVERGENT ROUNDING BASED ON SHIFT AMOUNT
           ----------------------------------------------------------------- */
        if((Q_diff == Q_mult) && (Q_in==Q_diff)) begin 
            // 10-bit shift
            L_r = temp_mult_out_r[10]; R_r = temp_mult_out_r[9]; S_r = |temp_mult_out_r[8:0];
            L_i = temp_mult_out_i[10]; R_i = temp_mult_out_i[9]; S_i = |temp_mult_out_i[8:0];
            
            round_bit_r = R_r & (L_r | S_r);
            round_bit_i = R_i & (L_i | S_i);
            
            rounded_mult_r = (temp_mult_out_r >>> 10) + $signed({1'b0, round_bit_r});
            rounded_mult_i = (temp_mult_out_i >>> 10) + $signed({1'b0, round_bit_i});
        end  
        else if ((Q_diff>Q_in && Q_diff==Q_mult) || (Q_diff==Q_in && Q_diff<Q_mult)) begin    
            // 11-bit shift
            L_r = temp_mult_out_r[11]; R_r = temp_mult_out_r[10]; S_r = |temp_mult_out_r[9:0];
            L_i = temp_mult_out_i[11]; R_i = temp_mult_out_i[10]; S_i = |temp_mult_out_i[9:0];
            
            round_bit_r = R_r & (L_r | S_r);
            round_bit_i = R_i & (L_i | S_i);
            
            rounded_mult_r = (temp_mult_out_r >>> 11) + $signed({1'b0, round_bit_r});
            rounded_mult_i = (temp_mult_out_i >>> 11) + $signed({1'b0, round_bit_i});
        end   
        else if ((Q_diff>Q_in && Q_diff<Q_mult)) begin    
            // 12-bit shift
            L_r = temp_mult_out_r[12]; R_r = temp_mult_out_r[11]; S_r = |temp_mult_out_r[10:0];
            L_i = temp_mult_out_i[12]; R_i = temp_mult_out_i[11]; S_i = |temp_mult_out_i[10:0];
            
            round_bit_r = R_r & (L_r | S_r);
            round_bit_i = R_i & (L_i | S_i);
            
            rounded_mult_r = (temp_mult_out_r >>> 12) + $signed({1'b0, round_bit_r});
            rounded_mult_i = (temp_mult_out_i >>> 12) + $signed({1'b0, round_bit_i});
        end 
        else begin
            // Safety fallback
            rounded_mult_r = temp_mult_out_r;
            rounded_mult_i = temp_mult_out_i;
        end

        /* -----------------------------------------------------------------
           2. APPLY SATURATION TO 12 BITS
           ----------------------------------------------------------------- */
        // Real Saturation
        if (rounded_mult_r > 26'sd2047)
            mult_out_r = 12'h7FF; // Max Positive
        else if (rounded_mult_r < -26'sd2048)
            mult_out_r = 12'h800; // Max Negative
        else
            mult_out_r = rounded_mult_r[11:0]; // Fits perfectly

        // Imaginary Saturation
        if (rounded_mult_i > 26'sd2047)
            mult_out_i = 12'h7FF; 
        else if (rounded_mult_i < -26'sd2048)
            mult_out_i = 12'h800; 
        else
            mult_out_i = rounded_mult_i[11:0]; 

        out_r = mult_out_r;
        out_i = mult_out_i;
    end

    /* the output from the summition */    
    else begin
        //No extending at all 
        if(Q_sum==Q_in && Q_sum==Q_mult) begin
            sum_r=inter_sum_r;
            sum_i=inter_sum_i;
        end 
        //extending in just one of them
        else if((Q_sum>Q_in && Q_sum==Q_mult) || (Q_sum==Q_in && Q_sum<Q_mult) ) begin
            // 1. Calculate the Convergent Rounding Bit
            round_bit_r = inter_sum_r[1] & inter_sum_r[0];
            round_bit_i = inter_sum_i[1] & inter_sum_i[0];
    
            // 2. Apply the shift and the rounding bit
            rounded_sum_r = (inter_sum_r >>> 1) + $signed({1'b0, round_bit_r});
            rounded_sum_i = (inter_sum_i >>> 1) + $signed({1'b0, round_bit_i});
    
            // 3. Apply Saturation to fit into 12 bits
            case (rounded_sum_r[12:11])
                2'b01:   sum_r = {1'b0,12'h7FF}; // Positive Overflow
                2'b10:   sum_r = {1'b1,12'h800}; // Negative Overflow
                default: sum_r = rounded_sum_r;  // Safely Truncate
            endcase
    
            case (rounded_sum_i[12:11])
                2'b01:   sum_i = {1'b0,12'h7FF}; 
                2'b10:   sum_i = {1'b1,12'h800}; 
                default: sum_i = rounded_sum_i; 
            endcase
        end
        //extending in both of them
        else if ((Q_sum>Q_in && Q_sum<Q_mult)) begin
            L_r = inter_sum_r[2]; R_r = inter_sum_r[1]; S_r = inter_sum_r[0]; 
            L_i = inter_sum_i[2]; R_i = inter_sum_i[1]; S_i = inter_sum_i[0]; 
    
            // 3. Calculate the Convergent Round bit
            round_bit_r = R_r & (L_r | S_r);
            round_bit_i = R_i & (L_i | S_i);
    
            // 4. Shift by 2 and add the round bit
            rounded_sum_r = (inter_sum_r >>> 2) + $signed({1'b0, round_bit_r});
            rounded_sum_i = (inter_sum_i >>> 2) + $signed({1'b0, round_bit_i});
    
            case (rounded_sum_r[12:11])
                2'b01:   sum_r = {1'b0,12'h7FF};
                2'b10:   sum_r = {1'b1,12'h800};
                default: sum_r = rounded_sum_r ;
            endcase 
            case (rounded_sum_i[12:11])
                2'b01:   sum_i = {1'b0,12'h7FF};
                2'b10:   sum_i = {1'b1,12'h800};
                default: sum_i = rounded_sum_i ;
            endcase 
        end 

        out_r = sum_r[DATA_WIDTH-1:0];
        out_i = sum_i[DATA_WIDTH-1:0];
    end    
end

endmodule 