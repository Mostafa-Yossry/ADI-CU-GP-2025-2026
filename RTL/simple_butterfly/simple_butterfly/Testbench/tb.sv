`timescale 1ns / 1ps

module tb_butterfly;

  parameter IWIDTH = 12;
  parameter CWIDTH = 16;
  parameter OWIDTH = 12;

  logic clk;
  logic rst;
  logic ce;

  logic [10:0] twiddle_idx;

  logic [2*IWIDTH-1:0] left_in;
  logic [2*IWIDTH-1:0] right_in;

  logic aux_in;

  logic [2*OWIDTH-1:0] left_out;
  logic [2*OWIDTH-1:0] right_out;

  logic aux_out;

  int result_count = 0;
  int test_id      = 0;

////////////////////////////////////////////////////////////
// Cycle tracking
////////////////////////////////////////////////////////////

  int cycle_count = 0;
  int input_cycles[$];

  always @(posedge clk)
      cycle_count++;

////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////

  simple_butterfly #(
      .IWIDTH(IWIDTH),
      .CWIDTH(CWIDTH),
      .OWIDTH(OWIDTH)
  ) dut (
      .i_clk(clk),
      .i_reset(rst),
      .i_clk_enable(ce),
      .i_twiddle_idx(twiddle_idx),
      .i_left(left_in),
      .i_right(right_in),
      .i_aux(aux_in),
      .o_left(left_out),
      .o_right(right_out),
      .o_aux(aux_out)
  );

////////////////////////////////////////////////////////////
// Clock
////////////////////////////////////////////////////////////

  initial begin
      clk = 0;
      forever #5 clk = ~clk;
  end

////////////////////////////////////////////////////////////
// Stimulus task
////////////////////////////////////////////////////////////

task send_butterfly_data(
    input [10:0] idx,
    input signed [IWIDTH-1:0] l_r,
    input signed [IWIDTH-1:0] l_i,
    input signed [IWIDTH-1:0] r_r,
    input signed [IWIDTH-1:0] r_i
);
begin

    @(posedge clk);

    test_id++;

    twiddle_idx <= idx;
    left_in  <= {l_r, l_i};
    right_in <= {r_r, r_i};

    aux_in <= 1'b1;

    input_cycles.push_back(cycle_count);

    $display("\n--------------------------------------------------");
    $display("TEST %0d  |  cycle %0d", test_id, cycle_count);
    $display("Twiddle Index : %0d", idx);
    $display("LEFT  INPUT   : %0d + j%0d", l_r,l_i);
    $display("RIGHT INPUT   : %0d + j%0d", r_r,r_i);
    $display("--------------------------------------------------");

    @(posedge clk);
    aux_in <= 1'b0;

end
endtask

////////////////////////////////////////////////////////////
// Test sequence
////////////////////////////////////////////////////////////

initial begin

    rst = 1;
    ce  = 0;

    twiddle_idx = 0;
    left_in  = 0;
    right_in = 0;
    aux_in   = 0;

    repeat(5) @(posedge clk);

    rst = 0;
    ce  = 1;

    repeat(3) @(posedge clk);

    $display("\n====================================================");
    $display("        FFT Butterfly RTL Verification");
    $display("====================================================\n");

////////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////////

    send_butterfly_data(11'd0,   100,  50,   40,   10);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd1,   100,  50,   40,   10);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd2,   -80,  20,   30,  -15);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd1024, 50,   0,    0,    0);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd2047, 30,  10,    5,    2);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd512,  40,   0,    0,    0);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd300,  0,    0,    0,    0);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd100,  2047, 2047, 2047, 2047);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd200, -2048,-2048,-2048,-2048);
    repeat(3) @(posedge clk);

    send_butterfly_data(11'd750,  123, -456, -321, 111);

////////////////////////////////////////////////////////////

    repeat(200) @(posedge clk);

    $display("\n====================================================");
    $display("Simulation Finished");
    $display("====================================================\n");

    $finish;

end

////////////////////////////////////////////////////////////
// Result monitor
////////////////////////////////////////////////////////////

always @(posedge clk)
begin
    if (aux_out)
    begin

        int start_cycle;
        int latency;

        int lr;
        int li;
        int rr;
        int ri;

        start_cycle = input_cycles.pop_front();
        latency     = cycle_count - start_cycle;

        lr = $signed(left_out [2*OWIDTH-1:OWIDTH]);
        li = $signed(left_out [OWIDTH-1:0]);

        rr = $signed(right_out[2*OWIDTH-1:OWIDTH]);
        ri = $signed(right_out[OWIDTH-1:0]);

        result_count++;

        $display("\nRESULT %0d  |  cycle %0d", result_count, cycle_count);
        $display("Latency : %0d cycles", latency);
        $display("LEFT  OUTPUT  : %0d + j%0d", lr, li);
        $display("RIGHT OUTPUT  : %0d + j%0d", rr, ri);
        $display("====================================================");

    end
end

endmodule