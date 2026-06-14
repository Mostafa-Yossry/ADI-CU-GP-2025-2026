`timescale 1ns / 1ps

module tb_radix8_butterfly;

  parameter IWIDTH = 16;
  parameter CWIDTH = 16;
  parameter OWIDTH = 16;
  parameter SHIFT  = 0;

  logic clk;
  logic rst;
  logic ce;

  logic [8:0] twiddle_idx;

  // Flattened buses for 8 complex numbers
  logic [(8*2*IWIDTH-1):0] data_in;
  logic aux_in;

  logic [(8*2*OWIDTH-1):0] data_out;
  logic aux_out;

  int result_count = 0;
  int test_id      = 0;

  ////////////////////////////////////////////////////////////
  // Cycle counter (stable reference)
  ////////////////////////////////////////////////////////////

  int cycle_count;

  always @(posedge clk)
  begin
    if (rst)
      cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;
  end

  ////////////////////////////////////////////////////////////
  // Registered handshake signals (avoid race)
  ////////////////////////////////////////////////////////////

  logic aux_in_q, aux_out_q;

  always @(posedge clk)
  begin
    aux_in_q  <= aux_in;
    aux_out_q <= aux_out;
  end

  ////////////////////////////////////////////////////////////
  // Latency tracking queue
  ////////////////////////////////////////////////////////////

  int input_cycles[$];

  always @(posedge clk)
  begin
    if (aux_in_q)
    begin
      input_cycles.push_back(cycle_count);
    end
  end

  ////////////////////////////////////////////////////////////
  // DUT
  ////////////////////////////////////////////////////////////

  radix8_butterfly #(
                     .IWIDTH(IWIDTH),
                     .CWIDTH(CWIDTH),
                     .OWIDTH(OWIDTH),
                     .SHIFT(SHIFT)
                   ) dut (
                     .i_clk(clk),
                     .i_reset(rst),
                     .i_clk_enable(ce),
                     .i_twiddle_idx(twiddle_idx),
                     .i_data(data_in),
                     .i_aux(aux_in),
                     .o_data(data_out),
                     .o_aux(aux_out)
                   );

  ////////////////////////////////////////////////////////////
  // Clock
  ////////////////////////////////////////////////////////////

  initial
  begin
    clk = 0;
    forever
      #5 clk = ~clk;
  end

  ////////////////////////////////////////////////////////////
  // Stimulus task
  ////////////////////////////////////////////////////////////

  task send_radix8_data(
      input logic [10:0] idx,
      input logic signed [IWIDTH-1:0] in_r [0:7],
      input logic signed [IWIDTH-1:0] in_i [0:7]
    );
    begin
      @(posedge clk);

      test_id++;

      twiddle_idx <= idx;

      // Pack the SV arrays into the flattened DUT bus
      for (int i = 0; i < 8; i++)
      begin
        data_in[(i*2*IWIDTH) + (2*IWIDTH-1) -: IWIDTH] <= in_r[i];
        data_in[(i*2*IWIDTH) + (IWIDTH-1)   -: IWIDTH] <= in_i[i];
      end

      aux_in <= 1'b1;

      $display("\n--------------------------------------------------");
      $display("TEST %0d  | cycle %0d", test_id, cycle_count);
      $display("Twiddle Index : %0d", idx);
      for (int i = 0; i < 8; i++)
      begin
        $display("INPUT [%0d]    : %0d + j%0d", i, in_r[i], in_i[i]);
      end
      $display("--------------------------------------------------");

      @(posedge clk);
      aux_in <= 1'b0;

    end
  endtask

  ////////////////////////////////////////////////////////////
  // Test sequence
  ////////////////////////////////////////////////////////////

  initial
  begin
    rst = 1;
    ce  = 0;

    twiddle_idx = 0;
    data_in  = 0;
    aux_in   = 0;

    repeat(5) @(posedge clk);

    rst = 0;
    ce  = 1;

    repeat(3) @(posedge clk);

    $display("\n====================================================");
    $display("        Radix-8 Butterfly RTL Verification");
    $display("====================================================\n");

    // =========================================================
    // TEST 1: DC Signal (All inputs 100 + j0)
    // EXPECTED:
    // Output [0] = 800 + j0
    // Output [1] through [7] = 0 + j0
    // =========================================================
    send_radix8_data(
        11'd0,
        '{ 100, 100, 100, 100, 100, 100, 100, 100 }, // Real
        '{ 0,   0,   0,   0,   0,   0,   0,   0   }  // Imag
      );
      
    // =========================================================
    // TEST 2: Nyquist Frequency (Alternating signs)
    // EXPECTED:
    // Output [4] = 800 + j0
    // All others   = 0 + j0
    // (This heavily stresses the subtraction paths in Stage 1 & 2)
    // =========================================================
    send_radix8_data(
        11'd0,
        '{ 100, -100, 100, -100, 100, -100, 100, -100 },
        '{ 0,   0,    0,   0,    0,   0,    0,   0    }
      );

    // =========================================================
    // TEST 3: Impulse Response (Energy only in bin 0)
    // EXPECTED:
    // All outputs = 100 + j0
    // (This tests that energy spreads evenly across all butterflies)
    // =========================================================
    send_radix8_data(
        11'd0,
        '{ 100, 0, 0, 0, 0, 0, 0, 0 },
        '{ 0,   0, 0, 0, 0, 0, 0, 0 }
      );

    // =========================================================
    // TEST 4: The Twiddle Test (Non-zero index)
    // EXPECTED:
    // Output will depend on your specific "twiddle_4096.hex" values.
    // But this ensures the ROM addressing logic (k, 2k, 3k) doesn't crash.
    // =========================================================
    send_radix8_data(
        11'd128, // Arbitrary non-zero base index
        '{ 100, 100, 100, 100, 100, 100, 100, 100 },
        '{ 0,   0,   0,   0,   0,   0,   0,   0   }
      );
    // =========================================================
    // TEST 5: Single Rotating Phasor (Bin 1) + 90-Degree Twiddle
    // INPUT: A complex sinusoid exactly at frequency bin 1 (e^(j*pi*n/4))
    // TWIDDLE: Base Index 256.
    // MATH EXPLANATION:
    // 1. The internal 8-point DFT will route all 800 energy to k=1.
    // 2. In a DIF FFT, k=1 bit-reverses to output port m=4.
    // 3. Port m=4 fetches twiddle from ROM address: 4 * 256 = 1024.
    // 4. Address 1024 is exactly 1/4 of your 4096 circle, which is -j.
    // EXPECTED:
    // Output [4] = 0 - j800
    // All others = 0 + j0
    // =========================================================
    send_radix8_data(
        11'd256,
        '{ 100, 71,   0, -71, -100, -71,    0,  71 }, // Real
        '{   0, 71, 100,  71,    0, -71, -100, -71 }  // Imag
      );

    // =========================================================
    // TEST 6: Twin Tones (DC + Nyquist) + 45-Degree Twiddle
    // INPUT: Energy at Bin 0 and Bin 4. (x[n] = 100 + 100(-1)^n)
    // TWIDDLE: Base Index 512.
    // MATH EXPLANATION:
    // 1. Internal DFT routes 800 to k=0 (m=0) and 800 to k=4 (m=1).
    // 2. Port m=0 uses W^0 = 1.
    // 3. Port m=1 fetches address 1 * 512 = 512.
    // 4. Address 512 is 1/8 of the circle (0.707 - j0.707).
    // EXPECTED:
    // Output [0] = 800 + j0
    // Output [1] = 566 - j566  (which is 800 * 0.707)
    // All others = 0 + j0
    // =========================================================
    send_radix8_data(
        11'd512,
        '{ 200, 0, 200, 0, 200, 0, 200, 0 }, // Real
        '{   0, 0,   0, 0,   0, 0,   0, 0 }  // Imag
      );

    // =========================================================
    // TEST 7: The "All Bins" Multiplier Stress Test
    // INPUT: Impulse at n=0 (100, 0, 0...)
    // TWIDDLE: Base Index 256.
    // MATH EXPLANATION:
    // 1. Internal DFT sends exactly 100 to ALL 8 output ports.
    // 2. Every single complex multiplier in Stage 4 is activated simultaneously.
    // 3. They fetch addresses: 0, 256, 512, 768, 1024, 1280, 1536, 1792.
    // EXPECTED (Applying fractional cos/sin values to 100):
    // Output [0] :  100 + j0    (W^0)
    // Output [1] :   92 - j38   (W^256)
    // Output [2] :   71 - j71   (W^512)
    // Output [3] :   38 - j92   (W^768)
    // Output [4] :    0 - j100  (W^1024)
    // Output [5] :  -38 - j92   (W^1280)
    // Output [6] :  -71 - j71   (W^1536)
    // Output [7] :  -92 - j38   (W^1792)
    // =========================================================
    send_radix8_data(
        11'd256,
        '{ 100, 0, 0, 0, 0, 0, 0, 0 }, // Real
        '{   0, 0, 0, 0, 0, 0, 0, 0 }  // Imag
      );
    // =========================================================
    // TEST 8: Maximum Dynamic Range (The Overflow Edge)
    // INPUT: DC signal right at the edge of OWIDTH overflow.
    // MATH: The butterfly has a natural gain of 8. If OWIDTH is 16 bits,
    // the maximum signed positive number is 32,767.
    // 32,767 / 8 = 4095. If we input anything higher than 4095,
    // the final output register will wrap around (overflow) and turn negative.
    // EXPECTED:
    // Output [0] = 32720 + j0
    // All others = 0 + j0
    // =========================================================
    send_radix8_data(
        11'd0,
        '{ 4090, 4090, 4090, 4090, 4090, 4090, 4090, 4090 }, // Real
        '{    0,    0,    0,    0,    0,    0,    0,    0 }  // Imag
      );

    // =========================================================
    // TEST 9: Pure Imaginary Nyquist (Cross-wiring Stress)
    // INPUT: Nyquist frequency, but entirely on the imaginary axis.
    // MATH: This forces the internal adders to leave the Real path
    // completely empty (0) while pushing max data through the Imaginary
    // subtractors in Stage 1 and Stage 2.
    // EXPECTED:
    // Output [1] = 0 + j8000
    // All others = 0 + j0
    // =========================================================
    send_radix8_data(
        11'd0,
        '{    0,     0,    0,     0,    0,     0,    0,     0 }, // Real
        '{ 1000, -1000, 1000, -1000, 1000, -1000, 1000, -1000 }  // Imag
      );

    // =========================================================
    // TEST 10: The High-Resolution Staircase (Phase Matrix Check)
    // INPUT: A large impulse (10,000) with Twiddle Index = 256.
    // MATH: This tests EVERY SINGLE multiplier simultaneously with
    // high-magnitude Q15 fractions. Base index 256 fetches:
    // 0, 22.5, 45, 67.5, 90, 112.5, 135, and 157.5 degrees.
    // EXPECTED:
    // Output [0] : 10000 + j0
    // Output [1] :  9239 - j3827
    // Output [2] :  7071 - j7071
    // Output [3] :  3827 - j9239
    // Output [4] :     0 - j10000
    // Output [5] : -3827 - j9239
    // Output [6] : -7071 - j7071
    // Output [7] : -9239 - j3827
    // Note: You may see +/- 2 on the lower bits due to Q15 truncation.
    // =========================================================
    send_radix8_data(
        11'd256,
        '{ 10000, 0, 0, 0, 0, 0, 0, 0 }, // Real
        '{     0, 0, 0, 0, 0, 0, 0, 0 }  // Imag
      );

    // =========================================================
    // TEST 11: The "CSD Killer" (Bin 5 Resonance)
    // INPUT: A complex sinusoid exactly tuned to frequency bin k=5.
    // x[n] = 1000 * e^(j * 5pi * n / 4)
    // MATH: The internal 0.707 shift-add logic (CSD) happens specifically
    // on indices 5 and 7. By injecting a signal that should perfectly
    // accumulate in Bin 5, we test the exact error margin of your
    // bit-shift approximations against true trigonometic values.
    // EXPECTED:
    // Output [5] = ~8000 + j0 (This will likely be ~7960 due to CSD leakage)
    // The leakage will appear as tiny numbers (e.g., +/- 10) in the other bins.
    // =========================================================
    send_radix8_data(
        11'd0,
        '{ 1000, -707,    0,  707, -1000,  707,     0, -707 }, // Real
        '{    0, -707, 1000, -707,     0,  707, -1000,  707 }  // Imag
      );

    repeat(30) @(posedge clk);

    $display("\n====================================================");
    $display("Simulation Finished");
    $display("====================================================\n");

    $finish;
  end

  ////////////////////////////////////////////////////////////
  // Result monitor (handshake aligned)
  ////////////////////////////////////////////////////////////

  always @(posedge clk)
  begin
    if (aux_out_q)
    begin
      int start_cycle;
      int latency;
      int out_r [0:7];
      int out_i [0:7];

      start_cycle = input_cycles.pop_front();
      latency     = cycle_count - start_cycle;

      // Unpack the flattened output bus for printing
      for (int i = 0; i < 8; i++)
      begin
        out_r[i] = $signed(data_out[(i*2*OWIDTH) + (2*OWIDTH-1) -: OWIDTH]);
        out_i[i] = $signed(data_out[(i*2*OWIDTH) + (OWIDTH-1)   -: OWIDTH]);
      end

      result_count++;

      $display("\nRESULT %0d | cycle %0d", result_count, cycle_count);
      $display("Latency : %0d cycles", latency);
      for (int i = 0; i < 8; i++)
      begin
        $display("OUTPUT [%0d]   : %0d + j%0d", i, out_r[i], out_i[i]);
      end
      $display("====================================================");
    end
  end

endmodule
