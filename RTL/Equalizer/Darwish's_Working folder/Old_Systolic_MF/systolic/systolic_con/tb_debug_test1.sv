// =============================================================================
// tb_debug_test1.sv
// Minimal single-test bench for Test 1 (single non-zero PE[3][3]).
// Prints cycle-by-cycle state of the key signals to isolate the failure.
// Run this instead of the full testbench to see exactly what value
// pe_e_out_r[3][7] holds when valid_out[3][7] fires.
// =============================================================================
`timescale 1ns/1ps

module tb_debug_test1;

localparam ROWS    = 8;
localparam COLS    = 8;
localparam K_DEPTH = 8;
localparam WL_IN   = 12;
localparam WL_OUT  = 16;
localparam SCALE_IN  = 2048;
localparam SCALE_OUT = 2048;
localparam PIPE_LAT  = (ROWS-1)+(COLS-1)+K_DEPTH+1; // 23

reg clk = 0;  always #5 clk = ~clk;
reg rst_n, en, start;
reg  signed [WL_IN-1:0] hh_real [0:ROWS-1];
reg  signed [WL_IN-1:0] hh_imag [0:ROWS-1];
reg  signed [WL_IN-1:0] y_real  [0:COLS-1];
reg  signed [WL_IN-1:0] y_imag  [0:COLS-1];
wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1][0:COLS-1];
wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1][0:COLS-1];
wire                      valid_out [0:ROWS-1][0:COLS-1];

systolic_matmul #(
    .ROWS(ROWS), .COLS(COLS), .K_DEPTH(K_DEPTH),
    .WL_IN(WL_IN), .WL_INT(16), .WL_OUT(WL_OUT)
) dut (
    .clk(clk), .rst_n(rst_n), .en(en), .start(start),
    .hh_real(hh_real), .hh_imag(hh_imag),
    .y_real(y_real),   .y_imag(y_imag),
    .yhat_real(yhat_real), .yhat_imag(yhat_imag),
    .valid_out(valid_out)
);

integer row, k, cycle_cnt;

// Cycle counter
always @(posedge clk) cycle_cnt <= cycle_cnt + 1;

// ── Continuous probe: show valid_out[3][7] and yhat every cycle it fires ───
always @(posedge clk) begin
    #1;
    if (valid_out[3][7])
        $display("  [PROBE] cycle=%0d  valid_out[3][7]=1  yhat_real=%0d (%0.4f)  yhat_imag=%0d",
            cycle_cnt,
            $signed(yhat_real[3][7]),
            $itor($signed(yhat_real[3][7])) / SCALE_OUT,
            $signed(yhat_imag[3][7]));
    // Also show any other row firing for comparison
    if (valid_out[0][7])
        $display("  [PROBE] cycle=%0d  valid_out[0][7]=1  yhat_real=%0d (%0.4f)",
            cycle_cnt, $signed(yhat_real[0][7]),
            $itor($signed(yhat_real[0][7])) / SCALE_OUT);
end

// ── Main stimulus ──────────────────────────────────────────────────────────
initial begin
    cycle_cnt = 0;
    rst_n = 0; en = 1; start = 0;
    for (row = 0; row < ROWS; row = row+1) begin
        hh_real[row] = 0; hh_imag[row] = 0;
    end
    for (k = 0; k < COLS; k = k+1) begin
        y_real[k] = 0; y_imag[k] = 0;
    end
    @(negedge clk); @(negedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);

    $display("=== Test 1: H^H(3,3)=2047, y[3]=2047, all others 0 ===");
    $display("    Expect: yhat[3]=0.999, all others 0");
    $display("    (cycle numbers are posedge counts since sim start)");

    // Pre-load y (constant)
    @(negedge clk);
    start = 0;
    for (k = 0; k < COLS; k = k+1) begin
        y_real[k] = (k == 3) ? (SCALE_IN-1) : 0;
        y_imag[k] = 0;
    end

    // Drive K_DEPTH cycles of H^H columns
    for (k = 0; k < K_DEPTH; k = k+1) begin
        @(negedge clk);
        start = (k == 0) ? 1'b1 : 1'b0;
        for (row = 0; row < ROWS; row = row+1) begin
            hh_real[row] = (row == 3 && k == 3) ? (SCALE_IN-1) : 0;
            hh_imag[row] = 0;
        end
        $display("  drive negedge k=%0d: hh_real[3]=%0d  start=%0b",
                 k, hh_real[3], start);
    end

    // Zero inputs after K cycles
    @(negedge clk);
    start = 0;
    for (row = 0; row < ROWS; row = row+1) begin
        hh_real[row] = 0; hh_imag[row] = 0;
    end

    // Wait long enough for all outputs
    repeat (PIPE_LAT + ROWS + 10) @(posedge clk);

    $display("=== Done. If [PROBE] for row 3 never printed, valid never fired. ===");
    $finish;
end

initial begin
    #50000;
    $display("TIMEOUT");
    $finish;
end

endmodule
