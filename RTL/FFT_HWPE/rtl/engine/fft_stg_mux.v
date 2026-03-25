module fft_stg_mux #(
    parameter DATA_WIDTH = 12
)(
    input  wire sel,
    input  wire [DATA_WIDTH-1: 0] in0, in1,
    output wire [DATA_WIDTH-1: 0] out
);

assign out = sel ? in1 : in0;

endmodule