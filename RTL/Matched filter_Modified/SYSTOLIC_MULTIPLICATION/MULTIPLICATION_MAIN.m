%% =========================================================
%  MMSE / ZF Equalizer - 8x8 MIMO Configuration
%  Matrix Multiplication : Systolic Array Algorithm
%  Matrix Inversion      : Float (Cholesky to be added later)
%  Supports: Floating-Point & Fixed-Point Analysis
%% =========================================================
%
%  Equations:
%    G      = H^H * H  + (sigma^2/P)*I        [8x8]
%    Z      = H^H * Y                          [8x1]
%    X_hat  = G^{-1} * Z                       [8x1]
%
%  Dimensions (8x8 MIMO):
%    H      : 8x8   (channel matrix)
%    Y      : 8x1   (received signal)
%    X_hat  : 8x1   (estimated symbols)
%    G      : 8x8   (Gram matrix + regularization)
%    Z      : 8x1   (matched filter output)
%
%% =========================================================

clear; clc; close all;

%% ---- Simulation Parameters ----
number_of_tests = 100;
Nt              = 8;                                              % Transmit antennas
Nr              = 8;                                              % Receive antennas  *** 8x8 ***
SNR_dB          = -18;                                            % SNR in dB
P               = 1;                                              % Transmit power
sigma2          = P / (10^(SNR_dB/10));                           % Noise variance
sigma2_over_P   = sigma2 / P;
SQNR_G          = zeros(1, number_of_tests);
SQNR_Z          = zeros(1, number_of_tests);
SQNR_GZ         = zeros(1, number_of_tests);
SQNR_All        = zeros(1, number_of_tests);
a               = -0.9995117188;                                  % Q1.11 min
b               =  0.9995117188;                                  % Q1.11 max
equalizer_type  = "MMSE";                                           % "ZF" or "MMSE"
% Select G types based on equalizer: ZF output needs fewer integer bits -> more fractional precision
if (equalizer_type == "ZF")
    T_G = MULTIPLICATION_TYPES('fixed_point_G_8x8_ZF',   12); % 12-bit, FL optimised for ZF
else
    T_G = MULTIPLICATION_TYPES('fixed_point_G_8x8_MMSE', 12); % 12-bit, FL sized for sigma2~63
end
T_Z             = MULTIPLICATION_TYPES('fixed_point_Z_8x8', 16); % Z = H^H*Y  types
T_GZ            = MULTIPLICATION_TYPES('fixed_point_GZ',    16); % G^{-1}*Z   types (unchanged)
mode            = "Z";                                            % Start Step 1: G only
%                                                                 % "G"   --> Gram matrix only
%                                                                 % "Z"   --> Z = H^H*Y only
%                                                                 % "GZ"  --> G^{-1}*Z only
%                                                                 % "All" --> full equalizer

%% ---- ZF: zero out regularization ----
if (equalizer_type == "ZF")
    sigma2_over_P = 0;
end

fprintf('=== 8x8 MIMO Equalizer Model (%s) ===\n', equalizer_type);
fprintf('Nt=%d, Nr=%d, SNR=%.0f dB\n\n', Nt, Nr, SNR_dB);

%% =========================================================
%  MAIN LOOP
%% =========================================================
for test = 1 : number_of_tests
    rng(test);

    %% ---- Generate H (8x8) in Q1.11 range ----
    H_real  = (b-a)*rand(Nr, Nt) + a;
    H_imag  = (b-a)*rand(Nr, Nt) + a;
    H       = H_real + 1j*H_imag;
    H       = cast(H, 'like', T_G.H);   % quantise to Q1.(L-1)
    HH      = H';                        % 8x8 conjugate transpose

    %% ---- Generate Y (8x1) in Q1.11 range ----
    if (mode == "Z" || mode == "GZ" || mode == "All")
        Y_real  = (b-a)*rand(Nr, 1) + a;
        Y_imag  = (b-a)*rand(Nr, 1) + a;
        Y       = Y_real + 1j*Y_imag;
        Y       = cast(Y, 'like', T_Z.Q6_);  % Q6_ = Y input type in fixed_point_Z_8x8
    end

    %% ---- Float reference for GZ step ----
    if (mode == "GZ" || mode == "All")
        G_inv_float = inv(double(HH) * double(H) + sigma2_over_P * eye(Nt));
        Z_float     = double(HH) * double(Y);
    end

    %% =========================================================
    %  BUILD INSTRUMENTED MEX (first test only)
    %% =========================================================
    if (test == 1)
        if (mode == "G")
            buildInstrumentedMex systolic_matmul_8_8__8_8 ...
                -args {HH, H, sigma2_over_P, T_G};
        elseif (mode == "Z")
            % Z reuses systolic_matmul_8_8__8_1 with Z_8x8 types
            buildInstrumentedMex systolic_matmul_8_8__8_1 ...
                -args {HH, Y, T_Z};
        elseif (mode == "GZ")
            buildInstrumentedMex systolic_matmul_8_8__8_1 ...
                -args {G_inv_float, Z_float, T_GZ};
        end
    end

    %% =========================================================
    %  COMPUTE
    %% =========================================================

    %% ---- G = H^H * H + sigma2_over_P * I ----
    if (mode == "G")
        % Instrumented mex logs data for showInstrumentationResults
        G_fixed = systolic_matmul_8_8__8_8_mex(HH, H, sigma2_over_P, T_G);
        G_float = double(HH) * double(H) + sigma2_over_P * eye(Nt);
    end
    if (mode == "All")
        G_fixed = systolic_matmul_8_8__8_8(HH, H, sigma2_over_P, T_G);
        G_float = double(HH) * double(H) + sigma2_over_P * eye(Nt);
    end

    %% ---- Z = H^H * Y ----
    if (mode == "Z")
        % Instrumented mex logs data for showInstrumentationResults
        Z_fixed = systolic_matmul_8_8__8_1_mex(HH, Y, T_Z);
        Z_float = double(HH) * double(Y);
    end
    if (mode == "All")
        Z_fixed = systolic_matmul_8_8__8_1(HH, Y, T_Z);
        Z_float = double(HH) * double(Y);
    end

    %% ---- X_hat = G^{-1} * Z ----
    if (mode == "GZ")
        GZ_fixed = systolic_matmul_8_8__8_1_mex(G_inv_float, Z_float, T_GZ);
        GZ_float = G_inv_float * Z_float;
    end

    if (mode == "All")
        G_inv_fixed  = inv(double(G_fixed));                             % float inversion
        X_hat_fixed  = systolic_matmul_8_8__8_1(G_inv_fixed, Z_fixed, T_GZ);
        GZ_fixed     = systolic_matmul_8_8__8_1(G_inv_float, Z_float, T_GZ);
        X_hat_float  = G_float \ double(Z_float);
        GZ_float     = X_hat_float;
    end

    %% =========================================================
    %  SQNR COMPUTATION
    %% =========================================================
    if (mode == "G" || mode == "All")
        signal_power  = mean(abs(G_float(:)).^2);
        noise_power   = mean(abs(G_float(:) - double(G_fixed(:))).^2);
        SQNR_G(test)  = 10 * log10(signal_power / noise_power);
    end

    if (mode == "Z" || mode == "All")
        signal_power  = mean(abs(Z_float(:)).^2);
        noise_power   = mean(abs(Z_float(:) - double(Z_fixed(:))).^2);
        SQNR_Z(test)  = 10 * log10(signal_power / noise_power);
    end

    if (mode == "GZ" || mode == "All")
        signal_power   = mean(abs(GZ_float(:)).^2);
        noise_power    = mean(abs(GZ_float(:) - double(GZ_fixed(:))).^2);
        SQNR_GZ(test)  = 10 * log10(signal_power / noise_power);
    end

    if (mode == "All")
        signal_power    = mean(abs(X_hat_float(:)).^2);
        noise_power     = mean(abs(X_hat_float(:) - double(X_hat_fixed(:))).^2);
        SQNR_All(test)  = 10 * log10(signal_power / noise_power);
    end
end

%% =========================================================
%  INSTRUMENTATION RESULTS (run after loop to get statistics)
%% =========================================================
if (mode == "G")
    showInstrumentationResults systolic_matmul_8_8__8_8_mex ...
        -proposeFL -defaultDT numerictype(1,12,11)
end

if (mode == "Z")
    showInstrumentationResults systolic_matmul_8_8__8_1_mex ...
        -proposeFL -defaultDT numerictype(1,12,11)
end

if (mode == "GZ")
    showInstrumentationResults systolic_matmul_8_8__8_1_mex ...
        -proposeFL -defaultDT numerictype(1,12)
end

%% =========================================================
%  REPORT SQNR
%% =========================================================
fprintf('\n--- SQNR Results (%s mode) ---\n', mode);

if (mode == "G" || mode == "All")
    fprintf('SQNR_G  : min=%.1f dB  mean=%.1f dB  max=%.1f dB\n', ...
        min(SQNR_G), mean(SQNR_G), max(SQNR_G));
end
if (mode == "Z" || mode == "All")
    fprintf('SQNR_Z  : min=%.1f dB  mean=%.1f dB  max=%.1f dB\n', ...
        min(SQNR_Z), mean(SQNR_Z), max(SQNR_Z));
end
if (mode == "GZ" || mode == "All")
    fprintf('SQNR_GZ : min=%.1f dB  mean=%.1f dB  max=%.1f dB\n', ...
        min(SQNR_GZ), mean(SQNR_GZ), max(SQNR_GZ));
end
if (mode == "All")
    fprintf('SQNR_All: min=%.1f dB  mean=%.1f dB  max=%.1f dB\n', ...
        min(SQNR_All), mean(SQNR_All), max(SQNR_All));
end

%% =========================================================
%  PLOTS
%% =========================================================
if (mode == "G" || mode == "All")
    PLOT('SQNR_G', number_of_tests, SQNR_G);
end
if (mode == "Z" || mode == "All")
    PLOT('SQNR_Z', number_of_tests, SQNR_Z);
end
if (mode == "GZ" || mode == "All")
    PLOT('SQNR_GZ', number_of_tests, SQNR_GZ);
end
if (mode == "All")
    PLOT('SQNR_All', number_of_tests, SQNR_All);
end
%% =========================================================
%  BINARY TESTBENCH FILE GENERATION
%  All seeds concatenated into one file per matrix
%  H  : row-major, real(H_ij) then imag(H_ij), row by row
%  Y  : column-major, real(Yi) then imag(Yi)
%  Z  : column-major, real(Zi) then imag(Zi)
%  Format : binary string (2's complement bits) per line
%  H  : Q1.11 (12-bit) 
%  Y  : Q1.11 (12-bit)
%  Z  : fixed-point output of systolic_matmul_8_8__8_1
%% =========================================================
if (mode == "Z" || mode == "All")
    output_dir = 'testbench_files';
    if ~exist(output_dir, 'dir'), mkdir(output_dir); end
    
    % Critical Requirement: One RNG seed before the loop
    rng(42); 
    
    % Open files with the "_Convergent" suffix
    fid_H = fopen(fullfile(output_dir, 'H_all_Convergent.txt'), 'w');
    fid_Y = fopen(fullfile(output_dir, 'Y_all_Convergent.txt'), 'w');
    fid_Z = fopen(fullfile(output_dir, 'Z_all_Convergent.txt'), 'w');
    
    % Critical Requirement: Single loop for all generations and writes
    for n = 1 : number_of_tests
        
        %% -- Generate continuous H and Y for this iteration --
        H_real_s = (b-a)*rand(Nr, Nt) + a;
        H_imag_s = (b-a)*rand(Nr, Nt) + a;
        H_s      = cast(H_real_s + 1j*H_imag_s, 'like', T_G.H);
        HH_s     = H_s';
        
        Y_real_s = (b-a)*rand(Nr, 1) + a;
        Y_imag_s = (b-a)*rand(Nr, 1) + a;
        Y_s      = cast(Y_real_s + 1j*Y_imag_s, 'like', T_Z.Q6_);
        
        %% -- Compute Z --
        Z_s      = systolic_matmul_8_8__8_1(HH_s, Y_s, T_Z);
        
        % Debug output for the first frame
        if n == 1
            fprintf('\n===== MATLAB TEST 1 (Seed 42) =====\n');
            disp('H(1,1)');
            disp(H_s(1,1));
            disp('Y(1)');
            disp(Y_s(1));
            disp('Z_s');
            disp(Z_s);
            disp('real(Z_s)');
            disp(real(Z_s));
            disp('imag(Z_s)');
            disp(imag(Z_s));
        end
        
        %% -- H: row-major, real then imag per element (128 lines, 12-bit binary) --
        for r = 1 : Nr
            for c = 1 : Nt
                fprintf(fid_H, '%s\n', bin(fi(real(H_s(r,c)), 1, 12, 11)));
                fprintf(fid_H, '%s\n', bin(fi(imag(H_s(r,c)), 1, 12, 11)));
            end
        end
        
        %% -- Y: real then imag per element (16 lines, 12-bit binary) --
        for k = 1 : Nr
            fprintf(fid_Y, '%s\n', bin(fi(real(Y_s(k)), 1, 12, 11)));
            fprintf(fid_Y, '%s\n', bin(fi(imag(Y_s(k)), 1, 12, 11)));
        end
        
        %% -- Z: real then imag per element (16 lines, e.g., 16-bit Q5.11 binary) --
        for k = 1 : Nr
            % Z_s is already a fixed-point object from the mex/function, format is preserved
            fprintf(fid_Z, '%s\n', bin(real(Z_s(k))));
            fprintf(fid_Z, '%s\n', bin(imag(Z_s(k))));
        end
        
    end
    
    % Close all files
    fclose(fid_H);
    fclose(fid_Y);
    fclose(fid_Z);
    fprintf('\nDone. 100 frames written to Convergent files in ./%s/\n', output_dir);
end
