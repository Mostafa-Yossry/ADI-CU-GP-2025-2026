%% =========================================================================
%  Generate RTL Test Vectors
%  MMSE Mode Z : Z = H^H * Y
%
%  CONVERGENT ROUNDING VERSION
%
%  MATCHES RTL TESTBENCH:
%    WL_IN  = 12  -> Q1.11 inputs
%    WL_OUT = 16  -> Q5.11 outputs
%
%  Uses:
%    systolic_matmul_8_8__8_1()
%    MULTIPLICATION_TYPES()
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
%  IMPORTANT:
%  This version uses MATLAB fi objects with:
%
%      fimath('RoundingMethod','Convergent')
%
%  so generated vectors exactly match convergent rounding
%  hardware behavior.
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
% FIXED-POINT TYPES
%% =========================================================================

T_Z = MULTIPLICATION_TYPES('fixed_point_Z_8x8', WL_IN);

%% =========================================================================
% OUTPUT DIRECTORY
%% =========================================================================

output_dir = 'rtl_vectors_conv_Z_Q1_11';

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

    H = H_real + 1j*H_imag;

    % Quantize using convergent rounding
    H = cast(H, 'like', T_Z.H);

    %% =====================================================================
    % HH = H^H
    %% =====================================================================

    HH = H';

    %% =====================================================================
    % Generate Y
    %% =====================================================================

    Y_real = (A_MAX - A_MIN) * rand(K_DEPTH,1) + A_MIN;
    Y_imag = (A_MAX - A_MIN) * rand(K_DEPTH,1) + A_MIN;

    Y = Y_real + 1j*Y_imag;

    % Quantize using convergent rounding
    Y = cast(Y, 'like', T_Z.Q6_);

    %% =====================================================================
    % Golden Output
    % Z = HH * Y
    %% =====================================================================

    Z = systolic_matmul_8_8__8_1(HH, Y, T_Z);

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

            val_r = storedInteger(real(HH(row,k)));
            val_i = storedInteger(imag(HH(row,k)));

            fprintf(fid_hh_real, '%d\n', val_r);
            fprintf(fid_hh_imag, '%d\n', val_i);

        end

    end

    %% =====================================================================
    % WRITE Y FILES
    %% =====================================================================

    for k = 1:K_DEPTH

        val_r = storedInteger(real(Y(k)));
        val_i = storedInteger(imag(Y(k)));

        fprintf(fid_y_real, '%d\n', val_r);
        fprintf(fid_y_imag, '%d\n', val_i);

    end

    %% =====================================================================
    % WRITE GOLDEN Z FILES
    %% =====================================================================

    for row = 1:ROWS

        val_r = storedInteger(real(Z(row)));
        val_i = storedInteger(imag(Z(row)));

        fprintf(fid_z_real, '%d\n', val_r);
        fprintf(fid_z_imag, '%d\n', val_i);

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