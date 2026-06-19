// ============================================================
// Module      : d_ff_complex
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
//============================================================
module d_ff_complex #(
           parameter         WIDTH = 8 
)(
    input  logic             clk        ,    
    input  logic             rst        ,  
    input  logic [WIDTH-1:0] d_r        ,    
    input  logic [WIDTH-1:0] d_im       ,   
    output logic [WIDTH-1:0] q_r        ,    
    output logic [WIDTH-1:0] q_im 
);

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            q_r  <= '0   ;
            q_im <= '0   ; 
        end 
        else begin
            q_r  <= d_r  ;  
            q_im <= d_im ; 
        end
    end

endmodule