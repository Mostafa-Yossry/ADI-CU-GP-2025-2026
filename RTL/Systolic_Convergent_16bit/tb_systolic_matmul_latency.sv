// =============================================================================
// tb_systolic_matmul_vectors.sv
// -----------------------------------------------------------------------------
// File-based RTL verification testbench for ŷ = H^H · y  (Matched Filter)
//
// Cycle-accurate pipeline display per test:
//   - Absolute cycle number at every posedge
//   - Which cycle start pulse was sent
//   - Which cycle each row's valid output first appeared
//   - Whether ANY output is valid on that cycle
//   - Frame latency = last_valid_cycle - start_cycle
// =============================================================================

`timescale 1ns/1ps

module tb_systolic_matmul_latency;

  //////////////////////////////////////////////////////////////////////////////
  // PARAMETERS
  //////////////////////////////////////////////////////////////////////////////

  localparam ROWS    = 8;
  localparam COLS    = 1;
  localparam K_DEPTH = 8;

  localparam WL_IN   = 12;
  localparam WL_OUT  = 16;

  localparam real SCALE_RTL    = 2048.0;
  localparam real SCALE_GOLDEN = 2048.0;

  localparam NUM_TESTS  = 100;
  localparam MAX_CYCLES = 300;

  localparam real TOL = 1.0 / 2048.0;

  //////////////////////////////////////////////////////////////////////////////
  // CLOCK / RESET
  //////////////////////////////////////////////////////////////////////////////

  reg clk = 0;
  always #5 clk = ~clk;

  reg rst_n;
  reg en;
  reg start;

  integer cycle_counter;

  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      cycle_counter <= 0;
    else
      cycle_counter <= cycle_counter + 1;
  end

  //////////////////////////////////////////////////////////////////////////////
  // DUT INTERFACE
  //////////////////////////////////////////////////////////////////////////////

  reg signed [WL_IN-1:0] hh_real [0:ROWS-1];
  reg signed [WL_IN-1:0] hh_imag [0:ROWS-1];

  reg signed [WL_IN-1:0] y_real [0:COLS-1];
  reg signed [WL_IN-1:0] y_imag [0:COLS-1];

  wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1][0:COLS-1];
  wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1][0:COLS-1];

  wire valid_out [0:ROWS-1][0:COLS-1];

  //////////////////////////////////////////////////////////////////////////////
  // DUT
  //////////////////////////////////////////////////////////////////////////////

  systolic_matmul #(
    .ROWS    (ROWS),
    .COLS    (COLS),
    .K_DEPTH (K_DEPTH),
    .WL_IN   (WL_IN),
    .WL_INT  (16),
    .WL_OUT  (WL_OUT)
  ) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .en        (en),
    .start     (start),

    .hh_real   (hh_real),
    .hh_imag   (hh_imag),

    .y_real    (y_real),
    .y_imag    (y_imag),

    .yhat_real (yhat_real),
    .yhat_imag (yhat_imag),

    .valid_out (valid_out)
  );

  //////////////////////////////////////////////////////////////////////////////
  // FILE HANDLES & STORAGE
  //////////////////////////////////////////////////////////////////////////////

  integer fid_hh_real, fid_hh_imag;
  integer fid_y_real,  fid_y_imag;
  integer fid_z_real,  fid_z_imag;

  integer hh_r_mem   [0:ROWS-1][0:K_DEPTH-1];
  integer hh_i_mem   [0:ROWS-1][0:K_DEPTH-1];

  integer y_r_mem [0:K_DEPTH-1];
  integer y_i_mem [0:K_DEPTH-1];

  integer z_r_golden [0:ROWS-1];
  integer z_i_golden [0:ROWS-1];

  real got_r [0:ROWS-1];
  real got_i [0:ROWS-1];

  integer valid_count       [0:ROWS-1];
  integer first_valid_cycle [0:ROWS-1];
  integer first_valid_seen  [0:ROWS-1];

  integer status, test, row, k, r, tmp, idle;
  integer pass_cnt, fail_cnt;
  integer done_cnt, watchdog;
  integer start_cycle;

  real exp_r, exp_i, err_r, err_i;

  integer lat_min, lat_max, lat_sum, lat_count;

  //////////////////////////////////////////////////////////////////////////////
  // RESET
  //////////////////////////////////////////////////////////////////////////////

  task apply_reset;
  begin
    rst_n = 0;
    en    = 1;
    start = 0;

    for (r=0; r<ROWS; r=r+1)
    begin
      hh_real[r] = 0;
      hh_imag[r] = 0;
    end

    y_real[0] = 0;
    y_imag[0] = 0;

    @(posedge clk);
    @(posedge clk);

    rst_n = 1;

    for (idle=0; idle<(ROWS+K_DEPTH); idle=idle+1)
      @(posedge clk);
  end
  endtask

  //////////////////////////////////////////////////////////////////////////////
  // LOAD TEST VECTORS
  //////////////////////////////////////////////////////////////////////////////

  task load_test_vectors;
  begin

    for (k=0; k<K_DEPTH; k=k+1)
    begin
      for (row=0; row<ROWS; row=row+1)
      begin
        status = $fscanf(fid_hh_real, "%d\n", tmp);
        hh_r_mem[row][k] = tmp;

        status = $fscanf(fid_hh_imag, "%d\n", tmp);
        hh_i_mem[row][k] = tmp;
      end
    end

    for (k=0; k<K_DEPTH; k=k+1)
    begin
      status = $fscanf(fid_y_real, "%d\n", tmp);
      y_r_mem[k] = tmp;

      status = $fscanf(fid_y_imag, "%d\n", tmp);
      y_i_mem[k] = tmp;
    end

    for (row=0; row<ROWS; row=row+1)
    begin
      status = $fscanf(fid_z_real, "%d\n", tmp);
      z_r_golden[row] = tmp;

      status = $fscanf(fid_z_imag, "%d\n", tmp);
      z_i_golden[row] = tmp;
    end

  end
  endtask

  //////////////////////////////////////////////////////////////////////////////
  // DRIVE INPUTS
  //////////////////////////////////////////////////////////////////////////////

  task drive_inputs;
  begin

    for (k=0; k<K_DEPTH; k=k+1)
    begin
      @(negedge clk);

      start = (k == 0);

      for (r=0; r<ROWS; r=r+1)
      begin
        hh_real[r] = hh_r_mem[r][k];
        hh_imag[r] = hh_i_mem[r][k];
      end

      y_real[0] = y_r_mem[k];
      y_imag[0] = y_i_mem[k];
    end

    @(negedge clk);

    start = 0;

    for (r=0; r<ROWS; r=r+1)
    begin
      hh_real[r] = 0;
      hh_imag[r] = 0;
    end

    y_real[0] = 0;
    y_imag[0] = 0;

  end
  endtask

  //////////////////////////////////////////////////////////////////////////////
  // COLLECT AND LOG
  //////////////////////////////////////////////////////////////////////////////

  task collect_and_log;

    integer any_valid;
    integer row_valid [0:ROWS-1];
    integer frame_end;
    integer frame_lat;

    reg [8*38-1:0] event_msg;

  begin

    for (row=0; row<ROWS; row=row+1)
    begin
      valid_count[row]       = 0;
      got_r[row]             = 0.0;
      got_i[row]             = 0.0;
      first_valid_cycle[row] = -1;
      first_valid_seen[row]  = 0;
    end

    done_cnt    = 0;
    watchdog    = 0;
    start_cycle = -1;
    frame_end   = -1;

    $display("");
    $display("  +-------+-------+----+----+----+----+----+----+----+----+-----+--------------------------------------+");
    $display("  | Cycle | START | R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 | ANY | Event                                |");
    $display("  +-------+-------+----+----+----+----+----+----+----+----+-----+--------------------------------------+");

    while ((done_cnt < ROWS) && (watchdog < MAX_CYCLES))
    begin

      @(posedge clk);
      #1;

      watchdog = watchdog + 1;

      if (start && (start_cycle == -1))
        start_cycle = cycle_counter - 1;

      any_valid = 0;

      for (row=0; row<ROWS; row=row+1)
      begin

        row_valid[row] = valid_out[row][0];

        if (row_valid[row])
        begin

          any_valid = 1;

          got_r[row] =
            $itor($signed(yhat_real[row][0])) / SCALE_RTL;

          got_i[row] =
            $itor($signed(yhat_imag[row][0])) / SCALE_RTL;

          valid_count[row] = valid_count[row] + 1;

          if (!first_valid_seen[row])
          begin
            first_valid_cycle[row] = cycle_counter;
            first_valid_seen[row]  = 1;
          end

          if (valid_count[row] == K_DEPTH)
            done_cnt = done_cnt + 1;

        end
      end

      if (any_valid)
        frame_end = cycle_counter;

      if ((start_cycle >= 0) &&
          (cycle_counter >= start_cycle))
      begin

        event_msg = " ";

        if (cycle_counter == start_cycle)
        begin
          event_msg = "FRAME START (k=0 driven)";
        end
        else if (any_valid)
        begin

          for (row=0; row<ROWS; row=row+1)
          begin
            if (row_valid[row] &&
                (first_valid_cycle[row] == cycle_counter))
            begin
              $swrite(
                event_msg,
                "%0srow%0d VALID ",
                event_msg,
                row
              );
            end
          end
        end
        else
        begin
          event_msg = "pipeline filling...";
        end

        $display(
          "  | %5d |   %1d   |  %1d |  %1d |  %1d |  %1d |  %1d |  %1d |  %1d |  %1d |  %1d  | %-36s |",
          cycle_counter,
          (start),

          row_valid[0],
          row_valid[1],
          row_valid[2],
          row_valid[3],
          row_valid[4],
          row_valid[5],
          row_valid[6],
          row_valid[7],

          any_valid,
          event_msg
        );

      end
    end

    $display("  +-------+-------+----+----+----+----+----+----+----+----+-----+--------------------------------------+");

    //==========================================================================
    // FRAME SUMMARY
    //==========================================================================

    $display("");
    $display("  +---------------------------------------------------------------+");
    $display("  |                        FRAME SUMMARY                          |");
    $display("  +---------------------------------------------------------------+");

    $display(
      "  | Frame START cycle : %4d                                      |",
      start_cycle
    );

    $display(
      "  | Frame END cycle   : %4d                                      |",
      frame_end
    );

    $display(
      "  | Frame latency     : %4d cycles                               |",
      (frame_end >= 0 && start_cycle >= 0) ?
      (frame_end - start_cycle) : -1
    );

    $display("  +---------------------------------------------------------------+");
    $display("  | Row | First Valid Cycle | Latency from START                 |");
    $display("  +-----+-------------------+------------------------------------+");

    for (row=0; row<ROWS; row=row+1)
    begin

      if (first_valid_cycle[row] >= 0)
      begin

        frame_lat = first_valid_cycle[row] - start_cycle;

        $display(
          "  |  %0d  |      cycle %4d   |         %2d cycles               |",
          row,
          first_valid_cycle[row],
          frame_lat
        );

        if (frame_lat < lat_min)
          lat_min = frame_lat;

        if (frame_lat > lat_max)
          lat_max = frame_lat;

        lat_sum   = lat_sum + frame_lat;
        lat_count = lat_count + 1;

      end
      else
      begin

        $display(
          "  |  %0d  |      TIMEOUT     |            --                    |",
          row
        );

      end
    end

    $display("  +-----+-------------------+------------------------------------+");
    $display("");

    if (watchdog >= MAX_CYCLES)
    begin

      $display(
        "  !! TIMEOUT test=%0d done_cnt=%0d !!",
        test,
        done_cnt
      );

      for (row=0; row<ROWS; row=row+1)
      begin
        if (valid_count[row] < K_DEPTH)
          fail_cnt = fail_cnt + 1;
      end
    end

  end
  endtask

  //////////////////////////////////////////////////////////////////////////////
  // CHECK RESULTS
  //////////////////////////////////////////////////////////////////////////////

  task check_results;
  begin

    for (row=0; row<ROWS; row=row+1)
    begin

      exp_r = $itor(z_r_golden[row]) / SCALE_GOLDEN;
      exp_i = $itor(z_i_golden[row]) / SCALE_GOLDEN;

      err_r = got_r[row] - exp_r;
      if (err_r < 0.0)
        err_r = -err_r;

      err_i = got_i[row] - exp_i;
      if (err_i < 0.0)
        err_i = -err_i;

      if ((err_r > TOL) || (err_i > TOL))
      begin

        $display(
          "  FAIL row=%0d  got=(%.6f, %.6f)  exp=(%.6f, %.6f)  err=(%.6f, %.6f)",
          row,
          got_r[row],
          got_i[row],
          exp_r,
          exp_i,
          err_r,
          err_i
        );

        fail_cnt = fail_cnt + 1;

      end
      else
      begin

        $display(
          "  PASS row=%0d  got=(%.6f, %.6f)  exp=(%.6f, %.6f)",
          row,
          got_r[row],
          got_i[row],
          exp_r,
          exp_i
        );

        pass_cnt = pass_cnt + 1;

      end
    end
  end
  endtask

  //////////////////////////////////////////////////////////////////////////////
  // MAIN
  //////////////////////////////////////////////////////////////////////////////

  initial
  begin

    pass_cnt = 0;
    fail_cnt = 0;

    lat_min  = 32767;
    lat_max  = 0;
    lat_sum  = 0;
    lat_count= 0;

    fid_hh_real =
      $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_real.txt", "r");

    fid_hh_imag =
      $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_imag.txt", "r");

    fid_y_real =
      $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt", "r");

    fid_y_imag =
      $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt", "r");

    fid_z_real =
      $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt", "r");

    fid_z_imag =
      $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt", "r");

    if (!fid_hh_real || !fid_hh_imag ||
        !fid_y_real  || !fid_y_imag  ||
        !fid_z_real  || !fid_z_imag)
    begin
      $display("ERROR: could not open vector files");
      $finish;
    end

    $display("");
    $display("==========================================================");
    $display("  SYSTOLIC MATCHED FILTER TESTBENCH");
    $display(
      "  ROWS=%0d  COLS=%0d  K_DEPTH=%0d  WL_IN=%0d  WL_OUT=%0d",
      ROWS,
      COLS,
      K_DEPTH,
      WL_IN,
      WL_OUT
    );

    $display(
      "  Expected latency : %0d cycles (row0) .. %0d cycles (row7)",
      K_DEPTH,
      K_DEPTH + ROWS - 1
    );

    $display("==========================================================");

    apply_reset();

    for (test=0; test<NUM_TESTS; test=test+1)
    begin

      $display("");
      $display("==========================================================");
      $display("  TEST %0d", test);
      $display("==========================================================");

      load_test_vectors();

      fork
        drive_inputs();
        collect_and_log();
      join

      check_results();

      apply_reset();

    end

    //==========================================================================
    // GLOBAL SUMMARY
    //==========================================================================

    $display("");
    $display("==========================================================");
    $display(
      "  GLOBAL LATENCY SUMMARY (%0d row measurements)",
      lat_count
    );

    $display("  Min latency  : %0d cycles", lat_min);
    $display("  Max latency  : %0d cycles", lat_max);

    $display(
      "  Mean latency : %.2f cycles",
      $itor(lat_sum)/$itor(lat_count)
    );

    $display(
      "  Expected     : %0d cycles (row0) .. %0d cycles (row7)",
      K_DEPTH,
      K_DEPTH + ROWS - 1
    );

    $display("==========================================================");
    $display("  FUNCTIONAL SUMMARY");
    $display("  PASS = %0d / %0d", pass_cnt, NUM_TESTS*ROWS);
    $display("  FAIL = %0d / %0d", fail_cnt, NUM_TESTS*ROWS);
    $display("==========================================================");

    if (fail_cnt == 0)
      $display("  ALL TESTS PASSED");
    else
      $display("  SOME TESTS FAILED");

    $fclose(fid_hh_real);
    $fclose(fid_hh_imag);

    $fclose(fid_y_real);
    $fclose(fid_y_imag);

    $fclose(fid_z_real);
    $fclose(fid_z_imag);

    $finish;

  end

  initial
  begin
    #10000000;
    $display("GLOBAL TIMEOUT");
    $finish;
  end

endmodule