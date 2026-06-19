// ============================================================
// Module      : Unpacking_Packing_Phase_1_2
// Author      : Marwan Khaled
// Email       : khaleryad816@gmail.com
// Date        : June 2026
// Description : A pure combinational format-conversion shim between the flat packed
//               bus interface of top_mimo_linear_solver_complex_pipelined and the
//               unpacked 1-D array interfaces of phase2 and phase3. In one direction
//               it unpacks the N*WIDTH-bit flat buses y_re_flat and y_im_flat into
//               N individual WIDTH-bit wires y_re_unpacked[0..N-1] and
//               y_im_unpacked[0..N-1] for consumption by phase2. In the other
//               direction it packs the N individual WIDTH-bit wires
//               x_re_unpacked[0..N-1] and x_im_unpacked[0..N-1] from phase3 back
//               into N*WIDTH-bit flat output buses x_re_flat and x_im_flat. All
//               conversions are done with a single generate-for loop of plain assign
//               statements; there are no registers, no clock, and no latency.
// 
// ============================================================  
module Unpacking_Packing_Phase_1_2 #(         
           parameter                     N                    = 8  ,
           parameter                     WIDTH                = 16      


)(
    input  wire                          clk                       ,
    input  wire                          rst                       ,

  
    input  wire signed [WIDTH-1:0]       x_re_unpacked [0:N-1]     ,
    input  wire signed [WIDTH-1:0]       x_im_unpacked [0:N-1]     ,
    input  wire signed [N*WIDTH-1:0]     y_re_flat                 ,
    input  wire signed [N*WIDTH-1:0]     y_im_flat                 ,

    output wire signed [WIDTH-1:0]       y_re_unpacked [0:N-1]     ,
    output wire signed [WIDTH-1:0]       y_im_unpacked [0:N-1]     ,
    output wire signed [N*WIDTH-1:0]     x_re_flat                 ,
    output wire signed [N*WIDTH-1:0]     x_im_flat
);    
    
    
    genvar element_index;
    generate
        for (element_index = 0; element_index < N; element_index = element_index + 1) begin : unpack_interfaces
            // 1D Arrays: Extract from flat bus phase (2)
            assign y_re_unpacked[element_index]  = y_re_flat[element_index*WIDTH +: WIDTH];
            assign y_im_unpacked[element_index]  = y_im_flat[element_index*WIDTH +: WIDTH];
            
            // Pack outputs back to flat bus phase (3)
            assign x_re_flat[element_index*WIDTH +: WIDTH] = x_re_unpacked[element_index];
            assign x_im_flat[element_index*WIDTH +: WIDTH] = x_im_unpacked[element_index];
        end
    endgenerate
endmodule