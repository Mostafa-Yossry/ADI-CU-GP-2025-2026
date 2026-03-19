module stg_fsm #(
    parameter FIFO_DEPTH = 4
)(
    input  wire                           clk, rst_n, valid_in, 
    output reg                            out_mux_sel, bf_en, fifo_mux_sel,
    output wire                           rot_en,
    output wire [$clog2(FIFO_DEPTH)-1: 0] twiddle_sel , 
    output wire valid_out
);
/* input - output - Parameters definition 
inputs:
valid_in : Asserted when there is a valid input and Enable the FFT block
clk , rst_n

outputs :
out_mux_sel:direct the output (from butterfly sum - from FIFO)
bf_en:enable the butterfly unit
fifo_mux_sel:direct the input of the FIFO (from input b - from the butterfly diff)
rot_en:asserted when the output is diff so it enables the mutliplier (rotator)
twiddle_sel:it's the superscript in the twilde factor w^(twiddle_sel)
valid_out:Asserted when there is a valid output of the stage


Parameters 
parameter (FIFO_DEPTH):the size of the FIFO 
*/

/*We have 4 main states 
IDLE_S : do noting
FILL_S : store the input in the FIFO
BF_S   : enable the butterfly and do the calculation (+,-)
DRAIN_S: move the difference from the FIFO to the multiplier then to the next stage
*/

localparam IDLE_S  = 2'b00,
           FILL_S  = 2'b01,
           BF_S    = 2'b11,
           DRAIN_S = 2'b10;

// FIFO MUX selection
localparam SEL_BF_DIFF   = 1'b0,
           SEL_STG_INPUT = 1'b1;

// output MUX selection
localparam SEL_FIFO_OUT = 1'b0,
           SEL_BF_SUM   = 1'b1;
          

reg [1:0] current_state, next_state;

wire count_done;
wire count_en;

assign rot_en = (next_state == DRAIN_S);
assign valid_out = (next_state == BF_S) || (next_state == DRAIN_S);

assign count_en = (current_state != IDLE_S);
wire  [$clog2(FIFO_DEPTH)-1: 0] glb_count;

/*this counter is used to move from state to another  */
modulo_N_counter #(.N(FIFO_DEPTH)) glb_counter_u0 (
.clk(clk),
.rst_n(rst_n),
.count_en(count_en),
.count_done(count_done),
.count(glb_count)
);

/*this counter is used to determine the source of the current output (sum or diff) so it enable and disable the rot_en */
modulo_N_counter #(.N(FIFO_DEPTH)) rot_counter_u1 (
.clk(clk),
.rst_n(rst_n),
.count_en(rot_en),
.count_done(rot_count_done),
.count(twiddle_sel)
);

/* next_stage -> current state*/
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        current_state <= IDLE_S;
    end
    else begin
        current_state <= next_state;
    end
end

/* determine the next_state based on the input and the current state*/
always @(*) begin
    next_state = IDLE_S;
    case(current_state)
        IDLE_S: begin
            if(valid_in) begin
                next_state = FILL_S;
            end
            else begin
                next_state = IDLE_S;
            end
        end
        
        FILL_S: begin
            if(count_done) begin
                next_state = BF_S;
            end
            else begin
                next_state = FILL_S;
            end
        end

        BF_S: begin
            if(count_done) begin
                next_state = DRAIN_S;
            end
            else begin
                next_state = BF_S;
            end            
        end

        DRAIN_S: begin
            if(count_done) begin
                if(valid_in)
                    next_state = BF_S;
                else
                    next_state = IDLE_S;
            end
            else begin
                next_state = DRAIN_S;
            end                 
        end
        default: next_state = IDLE_S;
    endcase
end

/* determine the output based on the next state (current state and input) and the current state*/
always @(*) begin
    fifo_mux_sel = SEL_STG_INPUT;
    out_mux_sel =  SEL_FIFO_OUT;
    bf_en = 1'b0;
    case(next_state) 
        IDLE_S: begin
        fifo_mux_sel = SEL_STG_INPUT;
        out_mux_sel =  SEL_FIFO_OUT;
        bf_en = 1'b0;            
        end

        FILL_S: begin
            fifo_mux_sel = SEL_STG_INPUT;
            bf_en        = 1'b0;
        end

        BF_S: begin
            fifo_mux_sel = SEL_BF_DIFF;
            out_mux_sel  = SEL_BF_SUM;
            bf_en        = 1'b1;            
        end

        DRAIN_S: begin
            fifo_mux_sel = SEL_STG_INPUT;
            out_mux_sel  = SEL_FIFO_OUT;
            bf_en        = 1'b0;            
        end

        default: begin
            fifo_mux_sel = SEL_STG_INPUT;
            out_mux_sel =  SEL_FIFO_OUT;
            bf_en = 1'b0;                 
        end
    endcase
end

endmodule