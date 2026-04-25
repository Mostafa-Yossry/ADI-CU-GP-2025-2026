module radix8_butterfly_verbose #(
    parameter IWIDTH = 16,
    parameter CWIDTH = 16,
    parameter OWIDTH = 16,
    parameter SHIFT  = 0
  )(
    input  wire                   i_clk,
    input  wire                   i_reset,
    input  wire                   i_clk_enable,
    input  wire [8:0]             i_twiddle_idx,

    // 8 Separate Complex Inputs (Real + Imag packed into 32 bits each)
    input  wire [2*IWIDTH-1:0]    i_data0, i_data1, i_data2, i_data3,
    input  wire [2*IWIDTH-1:0]    i_data4, i_data5, i_data6, i_data7,
    input  wire                   i_aux,

    // 8 Separate Complex Outputs
    output wire [2*OWIDTH-1:0]    o_data0, o_data1, o_data2, o_data3,
    output wire [2*OWIDTH-1:0]    o_data4, o_data5, o_data6, o_data7,
    output wire                   o_aux
  );
  // ---------------------------------------------------------
  // TWIDDLE ROM FETCH (Synchronous)
  // ---------------------------------------------------------
  // Note: Since this ROM is clocked, the 'w_coefs' will appear 1
  // cycle after 'i_twiddle_idx' is presented.
  wire [(7*2*CWIDTH-1):0] w_coefs;

  twiddle_rom_radix8 #(.CWIDTH(CWIDTH)) rom_inst (
                       .clk_i      (i_clk),
                       .clk_en_i   (i_clk_enable),
                       .base_idx_i (i_twiddle_idx),
                       .twiddles_o (w_coefs)
                     );

  // ---------------------------------------------------------
  // INTERNAL DATA MAPPING
  // ---------------------------------------------------------
  // We still use internal 2D arrays so the math loops don't
  // have to be rewritten as 8 separate lines of code.
  wire signed [IWIDTH-1:0] s0_r [0:7];
  wire signed [IWIDTH-1:0] s0_i [0:7];

  // Mapping the separate inputs into the internal array
  assign s0_r[0] = i_data0[2*IWIDTH-1 : IWIDTH];
  assign s0_i[0] = i_data0[IWIDTH-1 : 0];
  assign s0_r[1] = i_data1[2*IWIDTH-1 : IWIDTH];
  assign s0_i[1] = i_data1[IWIDTH-1 : 0];
  assign s0_r[2] = i_data2[2*IWIDTH-1 : IWIDTH];
  assign s0_i[2] = i_data2[IWIDTH-1 : 0];
  assign s0_r[3] = i_data3[2*IWIDTH-1 : IWIDTH];
  assign s0_i[3] = i_data3[IWIDTH-1 : 0];
  assign s0_r[4] = i_data4[2*IWIDTH-1 : IWIDTH];
  assign s0_i[4] = i_data4[IWIDTH-1 : 0];
  assign s0_r[5] = i_data5[2*IWIDTH-1 : IWIDTH];
  assign s0_i[5] = i_data5[IWIDTH-1 : 0];
  assign s0_r[6] = i_data6[2*IWIDTH-1 : IWIDTH];
  assign s0_i[6] = i_data6[IWIDTH-1 : 0];
  assign s0_r[7] = i_data7[2*IWIDTH-1 : IWIDTH];
  assign s0_i[7] = i_data7[IWIDTH-1 : 0];

  // ---------------------------------------------------------
  // STAGE 1: First Rank & W8 Rotations
  // ---------------------------------------------------------
  wire signed [IWIDTH:0] s1_r [0:7];
  wire signed [IWIDTH:0] s1_i [0:7];

  // Temporary wires for differences
  wire signed [IWIDTH:0] d1_r [0:3];
  wire signed [IWIDTH:0] d1_i [0:3];
  genvar i;
  generate
    // Calculate Sums (Even indices routing)
    for (i = 0; i < 4; i = i + 1)
    begin : s1_sums
      assign s1_r[i] = s0_r[i] + s0_r[i+4];
      assign s1_i[i] = s0_i[i] + s0_i[i+4];
      // Raw differences
      assign d1_r[i] = s0_r[i] - s0_r[i+4];
      assign d1_i[i] = s0_i[i] - s0_i[i+4];
    end
  endgenerate

  // Apply Rotations to Differences (Odd indices routing)
  // Index 4: W8^0 = 1
  assign s1_r[4] = d1_r[0];
  assign s1_i[4] = d1_i[0];

  // Index 5: W8^1 = 0.707 * (1 - j)
  wire signed [IWIDTH:0] sum1_1  = d1_r[1] + d1_i[1];
  wire signed [IWIDTH:0] diff1_1 = d1_i[1] - d1_r[1];
  assign s1_r[5] = (sum1_1 >>> 1) + (sum1_1 >>> 3) + (sum1_1 >>> 4) + (sum1_1 >>> 6);
  assign s1_i[5] = (diff1_1 >>> 1) + (diff1_1 >>> 3) + (diff1_1 >>> 4) + (diff1_1 >>> 6);

  // Index 6: W8^2 = -j
  assign s1_r[6] =  d1_i[2];
  assign s1_i[6] = -d1_r[2];

  // Index 7: W8^3 = 0.707 * (-1 - j)
  wire signed [IWIDTH:0] sum1_3  = d1_r[3] + d1_i[3];
  wire signed [IWIDTH:0] diff1_3 = d1_i[3] - d1_r[3];
  assign s1_r[7] =  ((diff1_3 >>> 1) + (diff1_3 >>> 3) + (diff1_3 >>> 4) + (diff1_3 >>> 6));
  assign s1_i[7] = -((sum1_3 >>> 1) + (sum1_3 >>> 3) + (sum1_3 >>> 4) + (sum1_3 >>> 6));

  // ---------------------------------------------------------
  // STAGE 2: Second Rank & W4 Rotations
  // ---------------------------------------------------------
  wire signed [IWIDTH+1:0] s2_r [0:7];
  wire signed [IWIDTH+1:0] s2_i [0:7];

  // Top Quad (Indices 0, 1, 2, 3)
  assign s2_r[0] = s1_r[0] + s1_r[2];
  assign s2_i[0] = s1_i[0] + s1_i[2];
  assign s2_r[1] = s1_r[1] + s1_r[3];
  assign s2_i[1] = s1_i[1] + s1_i[3];
  assign s2_r[2] = s1_r[0] - s1_r[2];
  assign s2_i[2] = s1_i[0] - s1_i[2]; // * 1
  assign s2_r[3] = s1_i[1] - s1_i[3];
  assign s2_i[3] = -(s1_r[1] - s1_r[3]); // * -j

  // Bottom Quad (Indices 4, 5, 6, 7)
  assign s2_r[4] = s1_r[4] + s1_r[6];
  assign s2_i[4] = s1_i[4] + s1_i[6];
  assign s2_r[5] = s1_r[5] + s1_r[7];
  assign s2_i[5] = s1_i[5] + s1_i[7];
  assign s2_r[6] = s1_r[4] - s1_r[6];
  assign s2_i[6] = s1_i[4] - s1_i[6]; // * 1
  assign s2_r[7] = s1_i[5] - s1_i[7];
  assign s2_i[7] = -(s1_r[5] - s1_r[7]); // * -j

  // ---------------------------------------------------------
  // STAGE 3: Final Rank (No internal twiddles)
  // ---------------------------------------------------------
  wire signed [IWIDTH+2:0] s3_r [0:7];
  wire signed [IWIDTH+2:0] s3_i [0:7];
  generate
    for (i = 0; i < 8; i = i + 2)
    begin : stage3_gen
      assign s3_r[i]   = s2_r[i] + s2_r[i+1];
      assign s3_i[i]   = s2_i[i] + s2_i[i+1];
      assign s3_r[i+1] = s2_r[i] - s2_r[i+1];
      assign s3_i[i+1] = s2_i[i] - s2_i[i+1];
    end
  endgenerate

  // ---------------------------------------------------------
  // STAGE 4: Data-ROM Alignment & Complex Multiplication
  // ---------------------------------------------------------

  // Registers for Stage 3 data to wait for the 1-cycle ROM latency.
  reg signed [IWIDTH+2:0] r_s3_r [0:7];
  reg signed [IWIDTH+2:0] r_s3_i [0:7];
  reg                     r_s3_aux;

  // Integer for the procedural for-loop (Fixes 'int' undefined error)
  integer k;

  always @(posedge i_clk)
  begin
    if (i_reset)
    begin
      r_s3_aux <= 1'b0;
    end
    else if (i_clk_enable)
    begin
      r_s3_aux <= i_aux;
      for (k = 0; k < 8; k = k + 1)
      begin
        r_s3_r[k] <= s3_r[k];
        r_s3_i[k] <= s3_i[k];
      end
    end
  end

  // Twiddle array declarations (Must be outside the generate block)
  wire signed [CWIDTH-1:0] twid_r [1:7];
  wire signed [CWIDTH-1:0] twid_i [1:7];

  genvar m; // Separate genvar for the complex multipliers
  generate
    // Unpack the 7 Twiddles from the ROM output bus (w_coefs)
    for (m = 1; m <= 7; m = m + 1)
    begin : unpack_twiddles
      assign twid_r[m] = w_coefs[(m*2*CWIDTH-1) -: CWIDTH];
      assign twid_i[m] = w_coefs[((m*2-1)*CWIDTH-1) -: CWIDTH];
    end
  endgenerate

  // Multiplier output wires: Width = (Data Width) + (Twiddle Width) + 1 for add/sub
  wire signed [IWIDTH+CWIDTH+2:0] mpy_r [0:7];
  wire signed [IWIDTH+CWIDTH+2:0] mpy_i [0:7];

  // Index 0: No complex multiply (W^0 = 1).
  // We left-shift by CWIDTH-1 to align decimal points with multiplier outputs.
  assign mpy_r[0] = { r_s3_r[0], {(CWIDTH-1){1'b0}} };
  assign mpy_i[0] = { r_s3_i[0], {(CWIDTH-1){1'b0}} };

  generate
    for (m = 1; m <= 7; m = m + 1)
    begin : complex_mpy_gen

      // -----------------------------------------------------
      // GAUSS'S 3-MULTIPLIER TRICK
      // A = r_s3_r[m]   |   C = twid_r[m]
      // B = r_s3_i[m]   |   D = twid_i[m]
      // -----------------------------------------------------

      // 1. Pre-Adders (Bit growth requires +1 bit width)
      // Data Sum: A + B (19 bits -> 20 bits)
      wire signed [IWIDTH+3:0] data_sum = r_s3_r[m] + r_s3_i[m];

      // Twiddle Sum/Diff: C + D and D - C (16 bits -> 17 bits)
      wire signed [CWIDTH:0] twid_sum  = twid_r[m] + twid_i[m];
      wire signed [CWIDTH:0] twid_diff = twid_i[m] - twid_r[m];

      // 2. The 3 Hardware Multipliers (DSP Blocks)
      // Width = 20 bits (data) + 17 bits (twid) = 37 bits max
      wire signed [IWIDTH+CWIDTH+3:0] k1 = twid_r[m] * data_sum;  // C * (A + B)
      wire signed [IWIDTH+CWIDTH+3:0] k2 = r_s3_r[m] * twid_diff; // A * (D - C)
      wire signed [IWIDTH+CWIDTH+3:0] k3 = r_s3_i[m] * twid_sum;  // B * (C + D)

      // 3. Post-Adders (Truncated implicitly to match original 35-bit width)
      // Real = K1 - K3  |  Imag = K1 + K2
      assign mpy_r[m] = k1 - k3;
      assign mpy_i[m] = k1 + k2;

    end
  endgenerate
    // ---------------------------------------------------------
  // STAGE 5: Convergent Rounding (Synchronous)
  // ---------------------------------------------------------
  // The 'convround' module introduces 1 clock cycle of latency.

  wire signed [OWIDTH-1:0] final_r [0:7];
  wire signed [OWIDTH-1:0] final_i [0:7];

  genvar p;
  generate
    for (p = 0; p < 8; p = p + 1)
    begin : rounding_gen

      // IWID Calculation:
      // Stage 3 Data (IWIDTH + 3 bits) + Twiddle (CWIDTH bits) = IWIDTH + CWIDTH + 3
      // SHIFT Calculation:
      // Drops the fractional bits of the twiddle + accounts for adder bit-growth.
      // Adjust SHIFT+3 to match your specific FFT scaling strategy.

      convround #(
                  .IWID(IWIDTH + CWIDTH + 3),
                  .OWID(OWIDTH),
                  .SHIFT(SHIFT + 4) // <--- Change this to + 4
                ) rnd_r (
                  .i_clk(i_clk),
                  .i_clk_enable(i_clk_enable),
                  .i_val(mpy_r[p]),
                  .o_val(final_r[p])
                );

      convround #(
                  .IWID(IWIDTH + CWIDTH + 3),
                  .OWID(OWIDTH),
                  .SHIFT(SHIFT + 4) // <--- Change this to + 4
                ) rnd_i (
                  .i_clk(i_clk),
                  .i_clk_enable(i_clk_enable),
                  .i_val(mpy_i[p]),
                  .o_val(final_i[p])
                );
    end
  endgenerate

  // ---------------------------------------------------------
  // CONTROL SYNCHRONIZATION & OUTPUT ASSIGNMENT
  // ---------------------------------------------------------
  // We must delay the 'aux' signal by 1 more cycle to match
  // the latency of the convround module flip-flops.
  reg o_aux_reg;

  always @(posedge i_clk)
  begin
    if (i_reset)
    begin
      o_aux_reg <= 1'b0;
    end
    else if (i_clk_enable)
    begin
      o_aux_reg <= r_s3_aux;
    end
  end

  assign o_aux = o_aux_reg;

  // ---------------------------------------------------------
  // OUTPUT ASSIGNMENT
  // ---------------------------------------------------------
  // Mapping the internal final results back to separate output ports
  assign o_data0 = {final_r[0], final_i[0]};
  assign o_data1 = {final_r[1], final_i[1]};
  assign o_data2 = {final_r[2], final_i[2]};
  assign o_data3 = {final_r[3], final_i[3]};
  assign o_data4 = {final_r[4], final_i[4]};
  assign o_data5 = {final_r[5], final_i[5]};
  assign o_data6 = {final_r[6], final_i[6]};
  assign o_data7 = {final_r[7], final_i[7]};
endmodule
