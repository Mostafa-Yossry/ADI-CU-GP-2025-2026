%% =========================================================================
%  Generate RTL Test Vectors
%  MMSE Mode Z : Z = H^H * Y   (Matched Filter — Block 2)
%
%  CONVERGENT ROUNDING VERSION
%
%  MATCHES RTL TESTBENCH:
%    WL_IN  = 12  -> Q1.11 inputs  (H^H and y, each element in [-1, +1))
%    WL_OUT = 16  -> Q5.11 output  (yhat, max magnitude = 8x2 = 16 -> 5 integer bits)
%
%  Fixed-Point Chain (per PDF spec):
%    Inputs   : Q1.11,  12-bit  (WL_IN=12,  FL_IN=11)
%    Internal : Q1.15,  16-bit  [RTL widens by appending 4 zero LSBs — no info loss]
%    Product  : Q2.30,  32-bit  [full-precision product of two Q1.15 operands]
%    Accum    : staged bit-growth
%                k=1   -> acc_Q2_ : 16-bit Q2.14  (max <= 2)
%                k=2   -> acc_Q3_ : 16-bit Q3.13  (max <= 4)
%                k=3,4 -> acc_Q4_ : 16-bit Q4.12  (max <= 8)
%                k=5-8 -> acc_Q5_ : 16-bit Q5.11  (max <= 16)
%    Output   : Q5.11, 16-bit  (WL_OUT=16, FL_OUT=11) — acc_Q5_ IS the output
%
%  NOTE: No sigma2/P addition in this block (off-diagonal only, no diagonal term).
%
%  Output files (written to output_dir):
%    hh_real.txt          — storedInteger of real(H^H), row-major per k-slice
%    hh_imag.txt          — storedInteger of imag(H^H), row-major per k-slice
%    y_real.txt           — storedInteger of real(y)
%    y_imag.txt           — storedInteger of imag(y)
%    z_real_golden.txt    — storedInteger of real(yhat), golden reference
%    z_imag_golden.txt    — storedInteger of imag(yhat), golden reference
%
%  File layout (matches RTL testbench driving order):
%    HH files : for k=1..8, for row=1..8  -> 8 values per k-column, 64 per test
%    Y  files : for k=1..8               -> 8 values per test
%    Z  files : for row=1..8             -> 8 values per test
%
%% =========================================================================

clear;
clc;
close all;

%% =========================================================================
%  PARAMETERS
%% =========================================================================

NUM_TESTS = 100;

ROWS    = 8;
COLS    = 8;
K_DEPTH = 8;

% -------------------------------------------------------------------------
%  RTL formats
% -------------------------------------------------------------------------

WL_IN   = 12;
FL_IN   = 11;     % Q1.11  — input format for H^H and y

WL_OUT  = 16;
FL_OUT  = 11;     % Q5.11  — output format for yhat (5 int bits covers max=16)

% Internal widened format used before multiplier
WL_INT  = 16;
FL_INT  = 15;     % Q1.15  — inputs widened by appending 4 zero LSBs

% -------------------------------------------------------------------------
%  Q1.11 representable range
% -------------------------------------------------------------------------

A_MAX =  2047 / 2048;   % +0.99951171875
A_MIN = -2048 / 2048;   % -1.0

% -------------------------------------------------------------------------
%  Shared fimath: convergent rounding, wrap on overflow
% -------------------------------------------------------------------------

FM = fimath( ...
    'RoundingMethod',   'Convergent', ...
    'OverflowAction',   'Wrap', ...
    'ProductMode',      'SpecifyPrecision', ...
    'ProductWordLength',        32, ...
    'ProductFractionLength',    30, ...
    'SumMode',          'SpecifyPrecision', ...
    'SumWordLength',            16, ...
    'SumFractionLength',        11);

% -------------------------------------------------------------------------
%  Fixed-point type definitions
% -------------------------------------------------------------------------

T_IN  = fi(0, 1, WL_IN,  FL_IN,  FM);   % Q1.11  12-bit — for H^H and y inputs
T_INT = fi(0, 1, WL_INT, FL_INT, FM);   % Q1.15  16-bit — widened internal
T_OUT = fi(0, 1, WL_OUT, FL_OUT, FM);   % Q5.11  16-bit — yhat output

%% =========================================================================
%  OUTPUT DIRECTORY
%% =========================================================================

output_dir = 'rtl_vectors_conv_Z_Q5_11_16bit';

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

%% =========================================================================
%  OPEN OUTPUT FILES
%% =========================================================================

fid_hh_real = fopen(fullfile(output_dir, 'hh_real.txt'), 'w');
fid_hh_imag = fopen(fullfile(output_dir, 'hh_imag.txt'), 'w');

fid_y_real  = fopen(fullfile(output_dir, 'y_real.txt'),  'w');
fid_y_imag  = fopen(fullfile(output_dir, 'y_imag.txt'),  'w');

fid_z_real  = fopen(fullfile(output_dir, 'z_real_golden.txt'), 'w');
fid_z_imag  = fopen(fullfile(output_dir, 'z_imag_golden.txt'), 'w');

fid_H_bin = fopen(fullfile(output_dir, 'H_binary.txt'), 'w');
fid_HH_bin = fopen(fullfile(output_dir, 'HH_binary.txt'), 'w');
%% =========================================================================
%  MAIN LOOP
%% =========================================================================

for test = 1:NUM_TESTS

    fprintf('Generating test %d / %d\n', test, NUM_TESTS);

    rng(test);

    %% =====================================================================
    %  1. Generate H and quantize to Q1.11
    %% =====================================================================

    H_real_raw = (A_MAX - A_MIN) * rand(ROWS, COLS) + A_MIN;
    H_imag_raw = (A_MAX - A_MIN) * rand(ROWS, COLS) + A_MIN;

    % Quantize to Q1.11 with convergent rounding
    H_r = fi(H_real_raw, 1, WL_IN, FL_IN, FM);
    H_i = fi(H_imag_raw, 1, WL_IN, FL_IN, FM);

    %% =====================================================================
%  Write H_binary.txt
%
%  Order:
%      Real(H11)
%      Imag(H11)
%      Real(H12)
%      Imag(H12)
%      ...
%      Real(H88)
%      Imag(H88)
%
%  Each value is written as a 12-bit two's-complement binary word.
%% =====================================================================

for row = 1:ROWS
    for col = 1:COLS

        real_bin = dec2bin( ...
            mod(storedInteger(H_r(row,col)), 2^WL_IN), ...
            WL_IN);

        imag_bin = dec2bin( ...
            mod(storedInteger(H_i(row,col)), 2^WL_IN), ...
            WL_IN);

        fprintf(fid_H_bin,'%s\n', real_bin);
        fprintf(fid_H_bin,'%s\n', imag_bin);

    end
end
    %% =====================================================================
    %  2. Form H^H  (conjugate transpose)
    %     HH(i,k) = H_r(k,i) - j*H_i(k,i)
    %% =====================================================================

    HH_r = fi(double(H_r)', 1, WL_IN, FL_IN, FM);
    HH_i = fi(-double(H_i)', 1, WL_IN, FL_IN, FM);
    %% =====================================================================
%  Write HH_binary.txt
%
%  Order:
%      Real(HH11)
%      Imag(HH11)
%      Real(HH12)
%      Imag(HH12)
%      ...
%      Real(HH88)
%      Imag(HH88)
%
%  Row-by-row traversal of H^H
%% =====================================================================

for row = 1:ROWS
    for col = 1:COLS

        real_bin = dec2bin( ...
            mod(storedInteger(HH_r(row,col)), 2^WL_IN), ...
            WL_IN);

        imag_bin = dec2bin( ...
            mod(storedInteger(HH_i(row,col)), 2^WL_IN), ...
            WL_IN);

        fprintf(fid_HH_bin, '%s\n', real_bin);
        fprintf(fid_HH_bin, '%s\n', imag_bin);

    end
end

    %% =====================================================================
    %  3. Generate y and quantize to Q1.11
    %% =====================================================================

    Y_real_raw = (A_MAX - A_MIN) * rand(K_DEPTH, 1) + A_MIN;
    Y_imag_raw = (A_MAX - A_MIN) * rand(K_DEPTH, 1) + A_MIN;

    Y_r = fi(Y_real_raw, 1, WL_IN, FL_IN, FM);
    Y_i = fi(Y_imag_raw, 1, WL_IN, FL_IN, FM);

    %% =====================================================================
    %  4. Widen inputs from Q1.11 to Q1.15
    %     RTL does this by appending 4 zero LSBs — equivalent to left-shift by 4
    %     in fractional domain, i.e. multiply stored integer by 16.
    %     We represent the same value but in Q1.15 format.
    %% =====================================================================

    HH_r_w = fi(double(HH_r), 1, WL_INT, FL_INT, FM);
    HH_i_w = fi(double(HH_i), 1, WL_INT, FL_INT, FM);

    Y_r_w  = fi(double(Y_r),  1, WL_INT, FL_INT, FM);
    Y_i_w  = fi(double(Y_i),  1, WL_INT, FL_INT, FM);

    %% =====================================================================
    %  5. Compute Z = HH * Y  (complex MAC, K=8 terms)
    %
    %  Complex product: (a+jb)(c+jd) = (ac - bd) + j(ad + bc)
    %  Accumulate 8 such products per output row.
    %  Final accumulator is Q5.11 (16-bit), matching acc_Q5_ in RTL.
    %
    %  The fi SumMode above directly enforces the Q5.11 16-bit accumulation.
    %% =====================================================================

    Z_r = fi(zeros(ROWS, 1), 1, WL_OUT, FL_OUT, FM);
    Z_i = fi(zeros(ROWS, 1), 1, WL_OUT, FL_OUT, FM);

    for row = 1:ROWS

        acc_r = fi(0, 1, WL_OUT, FL_OUT, FM);
        acc_i = fi(0, 1, WL_OUT, FL_OUT, FM);

        for k = 1:K_DEPTH

            a = HH_r_w(row, k);
            b = HH_i_w(row, k);
            c = Y_r_w(k);
            d = Y_i_w(k);

            % Full-precision 32-bit products (Q2.30)
            ac = fi(double(a) * double(c), 1, 32, 30, FM);
            bd = fi(double(b) * double(d), 1, 32, 30, FM);
            ad = fi(double(a) * double(d), 1, 32, 30, FM);
            bc = fi(double(b) * double(c), 1, 32, 30, FM);

            % Truncate products to Q5.11 before accumulation (mirrors RTL)
            prod_r = fi(double(ac) - double(bd), 1, WL_OUT, FL_OUT, FM);
            prod_i = fi(double(ad) + double(bc), 1, WL_OUT, FL_OUT, FM);

            acc_r = fi(double(acc_r) + double(prod_r), 1, WL_OUT, FL_OUT, FM);
            acc_i = fi(double(acc_i) + double(prod_i), 1, WL_OUT, FL_OUT, FM);

        end

        Z_r(row) = acc_r;
        Z_i(row) = acc_i;

    end

    %% =====================================================================
    %  6. Write H^H to files
    %     Outer loop = k (column of HH = row-index of H)
    %     Inner loop = row  (output index of yhat)
    %     This matches RTL testbench driving order.
    %% =====================================================================

    for k = 1:K_DEPTH
        for row = 1:ROWS
            fprintf(fid_hh_real, '%d\n', storedInteger(HH_r(row, k)));
            fprintf(fid_hh_imag, '%d\n', storedInteger(HH_i(row, k)));
        end
    end

    %% =====================================================================
    %  7. Write y to files
    %% =====================================================================

    for k = 1:K_DEPTH
        fprintf(fid_y_real, '%d\n', storedInteger(Y_r(k)));
        fprintf(fid_y_imag, '%d\n', storedInteger(Y_i(k)));
    end

    %% =====================================================================
    %  8. Write golden yhat to files
    %% =====================================================================

    for row = 1:ROWS
        fprintf(fid_z_real, '%d\n', storedInteger(Z_r(row)));
        fprintf(fid_z_imag, '%d\n', storedInteger(Z_i(row)));
    end

end

%% =========================================================================
%  CLOSE FILES
%% =========================================================================

fclose(fid_hh_real);
fclose(fid_hh_imag);
fclose(fid_y_real);
fclose(fid_y_imag);
fclose(fid_z_real);
fclose(fid_z_imag);
fclose(fid_H_bin);
fclose(fid_HH_bin);

%% =========================================================================
%  SUMMARY
%% =========================================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf('RTL vector generation completed — Block 2 Matched Filter\n');
fprintf('Output dir : %s\n', output_dir);
fprintf('Input  fmt : Q1.11, %d-bit  (FL_IN=%d)\n',  WL_IN,  FL_IN);
fprintf('Internal   : Q1.15, %d-bit  (zero-extended, no rounding)\n', WL_INT);
fprintf('Product    : Q2.30, 32-bit  (full precision)\n');
fprintf('Output fmt : Q5.11, %d-bit  (FL_OUT=%d)\n', WL_OUT, FL_OUT);
fprintf('storedInt scale : 2^%d = %d\n', FL_OUT, 2^FL_OUT);
fprintf('====================================================\n\n');