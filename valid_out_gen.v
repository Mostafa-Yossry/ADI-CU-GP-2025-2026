module valid_out_gen #(
    parameter FRAME_SIZE = 64
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,       // trigger signal from stage3
    output reg [$clog2(FRAME_SIZE)-1:0] count,
    output reg  frame_done   // pulse after FRAME_SIZE outputs
);
/*The counter is triggered by the assertion of the final stage's valid output. It increments until it reaches the Frame Size, at which point it asserts the frame_done signal for a single clock cycle*/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_done <= 1'b0;
            count      <= {($clog2(FRAME_SIZE)){1'b0}};
        end 

        else 
        begin
            frame_done <= 1'b0; // default low every cycle
            if(start)
            begin
                if (count == FRAME_SIZE-1) 
                begin
                    // Last output in this frame
                    frame_done <= 1'b1; // pulse for 1 cycle
                    count      <= 0;
                end 
                else 
                begin
                    count <= count + 1'b1;
                end
            end 
        end
    end

endmodule
