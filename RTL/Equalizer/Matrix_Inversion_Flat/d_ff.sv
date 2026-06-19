// ============================================================
// Module      : d_ff
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
//============================================================
module d_ff #(
           parameter         WIDTH = 8 
)(
    input  logic             clk        ,    
    input  logic             rst        ,  
    input  logic [WIDTH-1:0] d          ,    
    output logic [WIDTH-1:0] q   
);

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            q  <= '0  ;
        end 
        else begin
            q  <= d   ;  
        end
    end

endmodule