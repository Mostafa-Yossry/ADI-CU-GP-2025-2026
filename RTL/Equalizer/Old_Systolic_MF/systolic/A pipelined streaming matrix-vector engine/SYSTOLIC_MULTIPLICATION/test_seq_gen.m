%% =========================================================================
%  Generate RTL Test Vectors
%  MMSE Mode Z : Z = H^H * Y
%
%  MATCHES RTL TESTBENCH:
%    WL_IN  = 12  -> Q1.11 inputs
%    WL_OUT = 16  -> Q5.11 outputs
%
%  Generates vectors for 100 deterministic seeds
%
%  Output files:
%    hh_real.txt
%    hh_imag.txt
%    y_real.txt
%    y_imag.txt
%    z_real_golden.txt
%    z_imag_golden.txt
%
%  File format matches tb_systolic_matmul.sv exactly:
%
%    HH files:
%      cycle0_row0
%      cycle0_row1
%      ...
%      cycle0_row7
%      cycle1_row0
%      ...
%
%    Y files:
%      y[0]
%      y[1]
%      ...
%      y[7]
%
%    Z files:
%      z[0]
%      z[1]
%      ...
%      z[7]
%
%% =========================================================================

clear;
clc;
close all;

%% =========================================================================
% PARAMETERS
%% =========================================================================

NUM_TESTS = 100;

ROWS    = 8;
COLS    = 8;
K_DEPTH = 8;

% -------------------------------------------------------------------------
% RTL formats
% -------------------------------------------------------------------------

WL_IN   = 12;
FL_IN   = 11;     % Q1.11

WL_OUT  = 16;
FL_OUT  = 11;     % Q5.11

% -------------------------------------------------------------------------
% Q1.11 limits
% -------------------------------------------------------------------------

A_MAX =  2047 / 2048;   % +0.99951171875
A_MIN = -2048 / 2048;   % -1.0

%% =========================================================================
% OUTPUT DIRECTORY
%% =========================================================================

output_dir = 'rtl_vectors_Z_Q1_11';

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

%% =========================================================================
% OPEN FILES
%% =========================================================================

fid_hh_real = fopen(fullfile(output_dir, 'hh_real.txt'), 'w');
fid_hh_imag = fopen(fullfile(output_dir, 'hh_imag.txt'), 'w');

fid_y_real  = fopen(fullfile(output_dir, 'y_real.txt'),  'w');
fid_y_imag  = fopen(fullfile(output_dir, 'y_imag.txt'),  'w');

fid_z_real  = fopen(fullfile(output_dir, 'z_real_golden.txt'), 'w');
fid_z_imag  = fopen(fullfile(output_dir, 'z_imag_golden.txt'), 'w');

%% =========================================================================
% MAIN LOOP
%% =========================================================================

for test = 1:NUM_TESTS

    fprintf('Generating test %d / %d\n', test, NUM_TESTS);

    rng(test);

    %% =====================================================================
    % Generate H
    %% =====================================================================

    H_real = (A_MAX - A_MIN) * rand(ROWS, COLS) + A_MIN;
    H_imag = (A_MAX - A_MIN) * rand(ROWS, COLS) + A_MIN;

    % Quantize to Q1.11
    H_real_q = round(H_real * 2^FL_IN);
    H_imag_q = round(H_imag * 2^FL_IN);

    % Saturate to 12-bit signed
    H_real_q = max(min(H_real_q,  2^(WL_IN-1)-1), ...
                              -2^(WL_IN-1));

    H_imag_q = max(min(H_imag_q,  2^(WL_IN-1)-1), ...
                              -2^(WL_IN-1));

    % Convert back to floating for exact MATLAB compute
    H_q = (H_real_q + 1j*H_imag_q) / 2^FL_IN;

    %% =====================================================================
    % HH = H^H
    %% =====================================================================

    HH_q = H_q';

    %% =====================================================================
    % Generate Y
    %% =====================================================================

    Y_real = (A_MAX - A_MIN) * rand(K_DEPTH,1) + A_MIN;
    Y_imag = (A_MAX - A_MIN) * rand(K_DEPTH,1) + A_MIN;

    % Quantize Y to Q1.11
    Y_real_q = round(Y_real * 2^FL_IN);
    Y_imag_q = round(Y_imag * 2^FL_IN);

    % Saturate
    Y_real_q = max(min(Y_real_q,  2^(WL_IN-1)-1), ...
                              -2^(WL_IN-1));

    Y_imag_q = max(min(Y_imag_q,  2^(WL_IN-1)-1), ...
                              -2^(WL_IN-1));

    % Back to floating
    Y_q = (Y_real_q + 1j*Y_imag_q) / 2^FL_IN;

    %% =====================================================================
    % Golden Output
    % Z = HH * Y
    %% =====================================================================

    Z = HH_q * Y_q;

    %% =====================================================================
    % Quantize Output to Q5.11
    %% =====================================================================

    Z_real_q = round(real(Z) * 2^FL_OUT);
    Z_imag_q = round(imag(Z) * 2^FL_OUT);

    % Saturate to 16-bit signed
    Z_real_q = max(min(Z_real_q,  2^(WL_OUT-1)-1), ...
                              -2^(WL_OUT-1));

    Z_imag_q = max(min(Z_imag_q,  2^(WL_OUT-1)-1), ...
                              -2^(WL_OUT-1));

    %% =====================================================================
    % WRITE HH FILES
    %
    % IMPORTANT:
    % TB drives:
    %   hh_real[row] = hh_r_test[row][k]
    %
    % Therefore:
    %   outer loop = k
    %   inner loop = row
    %
    %% =====================================================================

    for k = 1:K_DEPTH

        for row = 1:ROWS

            val_r = round(real(HH_q(row,k)) * 2^FL_IN);
            val_i = round(imag(HH_q(row,k)) * 2^FL_IN);

            fprintf(fid_hh_real, '%d\n', val_r);
            fprintf(fid_hh_imag, '%d\n', val_i);

        end

    end

    %% =====================================================================
    % WRITE Y FILES
    %% =====================================================================

    for k = 1:K_DEPTH

        fprintf(fid_y_real, '%d\n', Y_real_q(k));
        fprintf(fid_y_imag, '%d\n', Y_imag_q(k));

    end

    %% =====================================================================
    % WRITE GOLDEN Z FILES
    %% =====================================================================

    for row = 1:ROWS

        fprintf(fid_z_real, '%d\n', Z_real_q(row));
        fprintf(fid_z_imag, '%d\n', Z_imag_q(row));

    end

end

%% =========================================================================
% CLOSE FILES
%% =========================================================================

fclose(fid_hh_real);
fclose(fid_hh_imag);

fclose(fid_y_real);
fclose(fid_y_imag);

fclose(fid_z_real);
fclose(fid_z_imag);

%% =========================================================================
% DONE
%% =========================================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf('RTL vector generation completed successfully\n');
fprintf('Output folder : %s\n', output_dir);
fprintf('====================================================\n');
fprintf('\n');