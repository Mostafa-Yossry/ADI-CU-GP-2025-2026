`timescale 1ns/1ps

module tb_matched_filter_unrolled;

  // ---------------------------------------------------------------
  // Testbench Parameters (Consistent with DUT)
  // ---------------------------------------------------------------
  localparam int MF_ROWS   = 8;
  localparam int MF_COLS   = 8;
  localparam int MF_WL_IN  = 12;
  localparam int MF_WL_OUT = 16;
  localparam int NUM_TESTS = 100; // Total vectors to stream
  localparam int CLK_PERIOD = 10; // 100 MHz

  // Pipeline latency = 10 cycles (8 MAC steps, each split into mul+sum stage,
  // with sequential accumulator chain). Counter includes 4 overhead cycles
  // (5 reset + 2 post-reset idles + 1 hh_load, counted from rst_n=1 so +3,
  // plus checker increments before sampling = +1 net), total counter value = 14.
  localparam int EXPECTED_LATENCY = 14;

  // File paths - adjust as needed
  localparam string DIR = "testbench_files2/";

  // ---------------------------------------------------------------
  // Signals
  // ---------------------------------------------------------------
  logic clk;
  logic rst_n;
  logic en;

  logic hh_load;
  logic signed [MF_WL_IN-1:0] hh_real [0:MF_ROWS-1][0:MF_COLS-1];
  logic signed [MF_WL_IN-1:0] hh_imag [0:MF_ROWS-1][0:MF_COLS-1];

  logic valid_in;
  logic signed [MF_WL_IN-1:0] y_real [0:MF_COLS-1];
  logic signed [MF_WL_IN-1:0] y_imag [0:MF_COLS-1];

  logic valid_out;
  logic gy_enable;
  logic signed [MF_WL_OUT-1:0] z_real [0:MF_ROWS-1];
  logic signed [MF_WL_OUT-1:0] z_imag [0:MF_ROWS-1];

  // ---------------------------------------------------------------
  // Memory arrays for file IO
  // ---------------------------------------------------------------
  logic [MF_WL_IN-1:0]  mem_hh [0 : NUM_TESTS * MF_ROWS * MF_COLS * 2 - 1]; // Hold ALL matrices
  logic [MF_WL_IN-1:0]  mem_y  [0 : NUM_TESTS * MF_COLS * 2 - 1];
  logic [MF_WL_OUT-1:0] mem_z  [0 : NUM_TESTS * MF_ROWS * 2 - 1];

  // Scoreboard queue to hold expected Z data for in-flight vectors
  typedef logic signed [MF_WL_OUT-1:0] z_vec_t [0:MF_ROWS-1][2]; // [rows][0=real,1=imag]
  z_vec_t expected_q [$];

  int error_count = 0;
  int vectors_checked = 0;

  // ---------------------------------------------------------------
  // DUT Instantiation (Connect to Unrolled module)
  // ---------------------------------------------------------------
  matched_filter_unrolled #(
                            .MF_ROWS(MF_ROWS),
                            .MF_COLS(MF_COLS),
                            .MF_WL_IN(MF_WL_IN),
                            .MF_WL_OUT(MF_WL_OUT)
                          ) dut (
                            .clk(clk),
                            .rst_n(rst_n),
                            .en(en),
                            .hh_load(hh_load),
                            .hh_real(hh_real),
                            .hh_imag(hh_imag),
                            .valid_in(valid_in),
                            .y_real(y_real),
                            .y_imag(y_imag),
                            .valid_out(valid_out),
                            .gy_enable(gy_enable),
                            .z_real(z_real),
                            .z_imag(z_imag)
                          );

  // ---------------------------------------------------------------
  // Clock Generation
  // ---------------------------------------------------------------
  initial
  begin
    clk = 0;
    forever
      #(CLK_PERIOD/2) clk = ~clk;
  end

  // ===============================================================
  // Main Stimulus Process (Driver) - CONTINUOUS STREAMING
  // ===============================================================
  initial
  begin
    int hh_idx, y_idx, z_idx;
    z_vec_t temp_z_vec;

    // Load files into memory
    $readmemb({DIR, "HH_all_Convergent.txt"}, mem_hh);
    $readmemb({DIR, "Y_all_Convergent.txt"},  mem_y);
    $readmemb({DIR, "Z_all_Convergent.txt"},  mem_z);

    // 1. Initialization & Reset
    rst_n    = 0;
    en       = 1;
    hh_load  = 0;
    valid_in = 0;

    // Zero inputs
    for(int r = 0; r < MF_ROWS; r++)
    begin
      for(int c = 0; c < MF_COLS; c++)
      begin
        hh_real[r][c] = '0;
        hh_imag[r][c] = '0;
      end
      if (r < MF_COLS)
      begin
        y_real[r] = '0;
        y_imag[r] = '0;
      end
    end

    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // -----------------------------------------------------------
    // Step A: Load ONE Static Channel Estimate (H^H) Matrix
    // -----------------------------------------------------------
    $display("tb: Loading static HH matrix (Test 0)...");
    for (int r = 0; r < MF_ROWS; r++)
    begin
      for (int c = 0; c < MF_COLS; c++)
      begin
        // We only grab the VERY FIRST matrix (test = 0)
        hh_idx = (0 * MF_ROWS * MF_COLS * 2) + (r * MF_COLS * 2) + (c * 2);
        hh_real[r][c] = mem_hh[hh_idx];
        hh_imag[r][c] = mem_hh[hh_idx + 1];
      end
    end
    hh_load = 1;
    @(posedge clk);
    hh_load = 0; // Drop hh_load and leave these coefficients loaded forever

    // -----------------------------------------------------------
    // Step B: Stream 100 Y Vectors Continuously (100% Throughput)
    // -----------------------------------------------------------
    $display("tb: Starting back-to-back stream of %0d Y vectors...", NUM_TESTS);
    for (int test = 0; test < NUM_TESTS; test++)
    begin

      // Extract Y input vector
      for (int k = 0; k < MF_COLS; k++)
      begin
        y_idx = (test * MF_COLS * 2) + (k * 2);
        y_real[k] = mem_y[y_idx];
        y_imag[k] = mem_y[y_idx + 1];
      end

      // Extract corresponding expected Z output vector and push to scoreboard
      for (int r = 0; r < MF_ROWS; r++)
      begin
        z_idx = (test * MF_ROWS * 2) + (r * 2);
        temp_z_vec[r][0] = mem_z[z_idx];   // real
        temp_z_vec[r][1] = mem_z[z_idx+1]; // imag
      end
      expected_q.push_back(temp_z_vec);

      // Drive valid_in high. We DO NOT drop it to 0.
      // We just wait one clock edge and immediately feed the next Y vector.
      valid_in = 1;
      @(posedge clk);

      // Notice: The `wait(expected_q.size() == 0);` stall is completely gone!
    end

    // Stop driving stimulus after all 100 are pushed in
    valid_in = 0;
    $display("tb: Finished driving stimulus. Waiting for pipeline to empty...");

    // Wait for all in-flight vectors to be checked by parallel process
    wait(vectors_checked == NUM_TESTS);

    // ---------------------------------------------------
    // Final Reporting
    // ---------------------------------------------------

    $display("---------------------------------------------------------");
    $display("Pipeline latency: 10 cycles (%0d counter cycles incl. overhead)", EXPECTED_LATENCY);
    $display("Vectors Processed: %0d", vectors_checked);
    if (error_count == 0)
    begin
      $display("SUCCESS: Stream passed with bit-exact matches!");
    end
    else
    begin
      $display("FAILURE: %0d mismatches found.", error_count);
    end
    $display("---------------------------------------------------------");

    $finish;
  end

  // ===============================================================
  // Output Checking Process (Scoreboard) - CORRECTED
  // ===============================================================
  initial
  begin
    z_vec_t exp_vec;
    logic initial_latency_met = 0;
    int clk_cnt = 0;
    int stall_cycles = 0; // Added a standard timeout counter
    logic gy_asserted_correctly = 0;

    // Reset state
    wait(rst_n == 1);

    forever
    begin
      @(posedge clk);
      if (en)
        clk_cnt++;

      if (valid_out)
      begin
        stall_cycles = 0; // Reset stall counter when valid data arrives

        // Check initial latency requirement
        if (!initial_latency_met)
        begin
          if (clk_cnt < EXPECTED_LATENCY)
          begin
            $error("tb: valid_out asserted too early! Cycle: %0d, Expected Min: %0d", clk_cnt, EXPECTED_LATENCY);
            error_count++;
          end
          else
          begin
            $display("tb: First valid_out received at cycle %0d (Latency OK)", clk_cnt);
          end
          initial_latency_met = 1;
        end

        // Check gy_enable sticky flag
        if (!gy_enable)
        begin
          $error("tb: gy_enable not high when valid_out is high!");
          error_count++;
        end
        else if (!gy_asserted_correctly)
        begin
          $display("tb: gy_enable asserted correctly on first output.");
          gy_asserted_correctly = 1;
        end

        // Get expected data from queue
        if (expected_q.size() == 0)
        begin
          $error("tb: Spurious valid_out! No data expected in scoreboard.");
          error_count++;
        end
        else
        begin
          exp_vec = expected_q.pop_front();
          vectors_checked++;

          $display("--- Vector %0d | cycle %0d ---", vectors_checked, clk_cnt);
          for (int k = 0; k < MF_ROWS; k++)
            $display("  row[%0d]: real=%6d  imag=%6d", k, $signed(z_real[k]), $signed(z_imag[k]));

          // Check all rows of the output vector
          for (int k = 0; k < MF_ROWS; k++)
          begin
            if (z_real[k] !== exp_vec[k][0] || z_imag[k] !== exp_vec[k][1])
            begin
              $error("Mismatch: Vector %0d, Row %0d! Exp: %h+%hi, Got: %h+%hi",
                     vectors_checked, k, exp_vec[k][0], exp_vec[k][1], z_real[k], z_imag[k]);
              error_count++;
            end
          end
        end
      end
      else
      begin
        // Generic timeout check instead of probing internal DUT signals
        if (initial_latency_met && vectors_checked < NUM_TESTS)
        begin
          stall_cycles++;
          // If we wait more than EXPECTED_LATENCY cycles without a valid_out, assume it hung
          if (stall_cycles > (EXPECTED_LATENCY + 10))
          begin
            $error("tb: Pipeline stalled! valid_out has been low for %0d cycles.", stall_cycles);
            error_count++;
            $finish; // Stop simulation on stall to prevent hang
          end
        end
      end
    end
  end
endmodule
