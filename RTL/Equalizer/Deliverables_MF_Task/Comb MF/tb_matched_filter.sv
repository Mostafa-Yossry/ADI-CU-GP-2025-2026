`timescale 1ns/1ps

module tb_matched_filter_unrolled;

  // ---------------------------------------------------------------
  // Testbench Parameters (Consistent with DUT)
  // ---------------------------------------------------------------
  localparam int MF_ROWS    = 8;
  localparam int MF_COLS    = 8;
  localparam int MF_WL_IN   = 12;
  localparam int MF_WL_OUT  = 16;
  localparam int NUM_TESTS  = 100;
  localparam int CLK_PERIOD = 10;   // 100 MHz

  // Pipeline latency = 2 cycles (input register + output register).
  // Counter starts from rst_n=1.  Overhead before first valid_in:
  //   2 idle cycles + 1 hh_load cycle = 3 cycles.
  // So first valid_out is expected at counter cycle  3 + 2 = 5.
  // We give one cycle of margin → EXPECTED_LATENCY = 5.
  localparam int EXPECTED_LATENCY = 5;

  // Stall timeout: after first valid_out, if valid_out goes low for
  // more than this many cycles we declare a hang.  4 is generous for
  // a 2-cycle design with continuous streaming.
  localparam int STALL_TIMEOUT = 4;

  // File paths
  localparam string DIR = "testbench_files2/";

  // ---------------------------------------------------------------
  // Signals
  // ---------------------------------------------------------------
  logic clk;
  logic rst_n;
  logic en;

  logic hh_load;
  logic signed [MF_WL_IN-1:0]  hh_real [0:MF_ROWS-1][0:MF_COLS-1];
  logic signed [MF_WL_IN-1:0]  hh_imag [0:MF_ROWS-1][0:MF_COLS-1];

  logic valid_in;
  logic signed [MF_WL_IN-1:0]  y_real  [0:MF_COLS-1];
  logic signed [MF_WL_IN-1:0]  y_imag  [0:MF_COLS-1];

  logic valid_out;
  logic signed [MF_WL_OUT-1:0] z_real  [0:MF_ROWS-1];
  logic signed [MF_WL_OUT-1:0] z_imag  [0:MF_ROWS-1];

  // ---------------------------------------------------------------
  // Memory arrays for file IO
  // ---------------------------------------------------------------
  logic [MF_WL_IN-1:0]  mem_hh [0 : NUM_TESTS * MF_ROWS * MF_COLS * 2 - 1];
  logic [MF_WL_IN-1:0]  mem_y  [0 : NUM_TESTS * MF_COLS * 2           - 1];
  logic [MF_WL_OUT-1:0] mem_z  [0 : NUM_TESTS * MF_ROWS * 2           - 1];

  // Scoreboard queue
  typedef logic signed [MF_WL_OUT-1:0] z_vec_t [0:MF_ROWS-1][2]; // [row][0=real,1=imag]
  z_vec_t expected_q [$];

  int error_count    = 0;
  int vectors_checked = 0;

  // ---------------------------------------------------------------
  // DUT Instantiation
  // ---------------------------------------------------------------
  matched_filter_unrolled #(
    .MF_ROWS   (MF_ROWS  ),
    .MF_COLS   (MF_COLS  ),
    .MF_WL_IN  (MF_WL_IN ),
    .MF_WL_OUT (MF_WL_OUT)
  ) dut (
    .clk      (clk      ),
    .rst_n    (rst_n    ),
    .en       (en       ),
    .hh_load  (hh_load  ),
    .hh_real  (hh_real  ),
    .hh_imag  (hh_imag  ),
    .valid_in (valid_in ),
    .y_real   (y_real   ),
    .y_imag   (y_imag   ),
    .valid_out(valid_out),
    .z_real   (z_real   ),
    .z_imag   (z_imag   )
  );

  // ---------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // ===============================================================
  // Driver — continuous 100% throughput streaming
  // ===============================================================
  initial begin
    int hh_idx, y_idx, z_idx;
    z_vec_t temp_z_vec;

    // Load stimulus files
    $readmemb({DIR, "HH_all_Convergent.txt"}, mem_hh);
    $readmemb({DIR, "Y_all_Convergent.txt"},  mem_y );
    $readmemb({DIR, "Z_all_Convergent.txt"},  mem_z );

    // ---- Initialise & reset ----
    rst_n    = 0;
    en       = 1;
    hh_load  = 0;
    valid_in = 0;

    for (int r = 0; r < MF_ROWS; r++) begin
      for (int c = 0; c < MF_COLS; c++) begin
        hh_real[r][c] = '0;
        hh_imag[r][c] = '0;
      end
    end
    for (int k = 0; k < MF_COLS; k++) begin
      y_real[k] = '0;
      y_imag[k] = '0;
    end

    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);   // 2 idle cycles after reset

    // ---- Load the static H^H matrix (test-vector 0) ----
    $display("tb: Loading static HH matrix (from test 0)...");
    for (int r = 0; r < MF_ROWS; r++)
      for (int c = 0; c < MF_COLS; c++) begin
        hh_idx = (0 * MF_ROWS * MF_COLS * 2) + (r * MF_COLS * 2) + (c * 2);
        hh_real[r][c] = mem_hh[hh_idx    ];
        hh_imag[r][c] = mem_hh[hh_idx + 1];
      end
    hh_load = 1;
    @(posedge clk);
    hh_load = 0;

    // ---- Stream 100 Y vectors back-to-back (100 % throughput) ----
    // Each Y lands in the input register on the next rising edge;
    // the result appears exactly 2 cycles later at z_real/z_imag.
    $display("tb: Streaming %0d Y vectors at 100%% throughput...", NUM_TESTS);
    for (int test = 0; test < NUM_TESTS; test++) begin

      // Drive Y inputs
      for (int k = 0; k < MF_COLS; k++) begin
        y_idx = (test * MF_COLS * 2) + (k * 2);
        y_real[k] = mem_y[y_idx    ];
        y_imag[k] = mem_y[y_idx + 1];
      end

      // Push expected Z into scoreboard queue
      for (int r = 0; r < MF_ROWS; r++) begin
        z_idx = (test * MF_ROWS * 2) + (r * 2);
        temp_z_vec[r][0] = mem_z[z_idx    ];   // real
        temp_z_vec[r][1] = mem_z[z_idx + 1];   // imag
      end
      expected_q.push_back(temp_z_vec);

      valid_in = 1;
      @(posedge clk);
    end

    valid_in = 0;
    $display("tb: Stimulus done. Waiting for output checker...");

    // Allow pipeline to drain (2 cycles is enough; use NUM_TESTS as safe ceiling)
    wait(vectors_checked == NUM_TESTS);

    // ---- Final report ----
    $display("---------------------------------------------------------");
    $display("Architecture : pure combinational + I/O registers");
    $display("Pipeline latency : 2 cycles");
    $display("Vectors processed: %0d", vectors_checked);
    if (error_count == 0)
      $display("RESULT : SUCCESS — all vectors bit-exact.");
    else
      $display("RESULT : FAILURE — %0d mismatch(es).", error_count);
    $display("---------------------------------------------------------");
    $finish;
  end

  // ===============================================================
  // Checker / Scoreboard
  // ===============================================================
  initial begin
    z_vec_t exp_vec;
    logic   first_valid_seen = 0;
    int     clk_cnt          = 0;
    int     stall_cycles     = 0;

    wait(rst_n == 1);

    forever begin
      @(posedge clk);
      if (en) clk_cnt++;

      if (valid_out) begin
        stall_cycles = 0;

        // ---- Latency check (first output only) ----
        if (!first_valid_seen) begin
          if (clk_cnt < EXPECTED_LATENCY)
            $error("tb: valid_out too early! cycle=%0d expected_min=%0d",
                   clk_cnt, EXPECTED_LATENCY);
          else
            $display("tb: First valid_out at cycle %0d (latency OK, expected >= %0d)",
                     clk_cnt, EXPECTED_LATENCY);
          first_valid_seen = 1;
        end

        // ---- Scoreboard comparison ----
        if (expected_q.size() == 0) begin
          $error("tb: Spurious valid_out — scoreboard is empty!");
          error_count++;
        end else begin
          exp_vec = expected_q.pop_front();
          vectors_checked++;

          $display("--- Vector %0d | cycle %0d ---", vectors_checked, clk_cnt);
          for (int k = 0; k < MF_ROWS; k++)
            $display("  row[%0d]: real=%6d  imag=%6d",
                     k, $signed(z_real[k]), $signed(z_imag[k]));

          for (int k = 0; k < MF_ROWS; k++) begin
            if (z_real[k] !== exp_vec[k][0] || z_imag[k] !== exp_vec[k][1]) begin
              $error("Mismatch v%0d row%0d  exp=%h+%hi  got=%h+%hi",
                     vectors_checked, k,
                     exp_vec[k][0], exp_vec[k][1],
                     z_real[k],     z_imag[k]);
              error_count++;
            end
          end
        end

      end else begin
        // ---- Stall / hang detection ----
        if (first_valid_seen && vectors_checked < NUM_TESTS) begin
          stall_cycles++;
          if (stall_cycles > STALL_TIMEOUT) begin
            $error("tb: Pipeline stalled — valid_out low for %0d cycles.", stall_cycles);
            error_count++;
            $finish;
          end
        end
      end
    end // forever
  end

endmodule