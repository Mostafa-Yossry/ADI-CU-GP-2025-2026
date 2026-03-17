%% gen_testdata_4096.m
% Generates input_data4096.txt and output_data4096.txt for the 4096-point
% DIF-SDF FFT testbench, using the MEX-accelerated fft_dif_sdf_mex.
%
% OUTPUT FORMAT (matches tb_fft4096.sv / tb_fft64.sv convention):
%   Each line = one 12-bit two's-complement binary word.
%   Samples are interleaved: Real[0], Imag[0], Real[1], Imag[1], ...
%   All frames are packed back-to-back in a single file.
%
% HOW IT WORKS:
%   1. Build the instrumented MEX once (fft_dif_sdf_mex).
%   2. Loop over nSeeds random frames, run the fixed-point model,
%      quantise input & output to 12-bit two's complement, write files.
%
% USAGE:
%   Simply run this script from the folder that contains:
%       fft_dif_sdf.m, fft_types.m  (and their dependencies)
%   The two .txt files will appear in the same folder.

clear; clc;

%% ---- Parameters --------------------------------------------------------
N       = 4096;          % FFT size
nSeeds  = 10;           % number of frames  (adjust to taste)
dtype   = 'fxpt';        % must match fft_types / hardware
DW      = 12;            % DATA_WIDTH in the Verilog  (bits, signed)

%% ---- Build MEX (once) --------------------------------------------------
T = fft_types(dtype, N);

exampleInput = cast(complex(zeros(N,1)), 'like', T.stage1_in);
fprintf('Building instrumented MEX for fft_dif_sdf ...\n');
buildInstrumentedMex('fft_dif_sdf', '-args', {exampleInput, T});
fprintf('MEX build complete.\n\n');

%% ---- Pre-allocate storage ----------------------------------------------
% Each frame contributes N complex samples → 2*N 12-bit words
totalWords  = nSeeds * N * 2;   % real+imag interleaved
input_words  = zeros(totalWords, 1, 'int32');
output_words = zeros(totalWords, 1, 'int32');

%% ---- Quantisation helper (float → signed 12-bit integer) ---------------
% The input type is fi([], 1, 1+11, 11)  → range [-1, 1)  Q1.11
% The output type is fi([], 1, 9+3,  3)  → range much wider
% We simply cast via the fi type and then read the stored integer.
% For the binary file we need the raw 12-bit two's-complement value.

maxInt = 2^(DW-1) - 1;   % 2047
minInt = -2^(DW-1);       % -2048

to12bit = @(x) max(min(round(x), maxInt), minInt);

%% ---- Main generation loop ----------------------------------------------
fprintf('Generating %d frames of N=%d ...\n', nSeeds, N);
tic;

ptr = 1;   % write pointer into the word arrays

for seed = 1:nSeeds

    rng(seed);

    % Random input in [-1, +1)  (two's-complement interpretation for Q1.11:
    %   value * 2^11 must fit in [-2048, 2047])
    input_float = (2*rand(N,1)-1) + 1j*(2*rand(N,1)-1);

    % Cast to the hardware input type (fi Q1.11, 12-bit)
    x_fi = cast(input_float, 'like', T.stage1_in);

    % Run fixed-point model via MEX
    Y_fi = fft_dif_sdf_mex(x_fi, T);

    % ---- Quantise INPUT to 12-bit signed integers -----------------------
    % fi stores values as scaled integers; storedInteger gives the raw bits
    x_int_r = int32(storedInteger(real(x_fi)));
    x_int_i = int32(storedInteger(imag(x_fi)));

    % ---- Quantise OUTPUT to 12-bit signed integers ----------------------
    % Output fi type is fi(1, 9+3, 3) → 12-bit word
    y_int_r = int32(storedInteger(real(Y_fi)));
    y_int_i = int32(storedInteger(imag(Y_fi)));

    % Clamp both to [-2048, 2047] just in case of overflow
    x_int_r = max(min(x_int_r,  maxInt), minInt);
    x_int_i = max(min(x_int_i,  maxInt), minInt);
    y_int_r = max(min(y_int_r,  maxInt), minInt);
    y_int_i = max(min(y_int_i,  maxInt), minInt);

    % ---- Interleave Real / Imag, sample by sample -----------------------
    for k = 1:N
        input_words(ptr)   = x_int_r(k);
        input_words(ptr+1) = x_int_i(k);
        output_words(ptr)   = y_int_r(k);
        output_words(ptr+1) = y_int_i(k);
        ptr = ptr + 2;
    end

    if mod(seed, 50) == 0
        fprintf('  Frame %d / %d done  (%.1f s elapsed)\n', seed, nSeeds, toc);
    end
end

fprintf('All frames generated in %.2f s.\n\n', toc);

%% ---- Write text files (binary, 12 digits per line) ---------------------
fprintf('Writing input_data4096.txt  ...\n');
write_binary_txt('input_data4096.txt',  input_words,  DW);

fprintf('Writing output_data4096.txt ...\n');
write_binary_txt('output_data4096.txt', output_words, DW);

fprintf('Done.  Files written:\n');
fprintf('  input_data4096.txt   (%d words)\n',  numel(input_words));
fprintf('  output_data4096.txt  (%d words)\n',  numel(output_words));

%% ---- Local helper -------------------------------------------------------
function write_binary_txt(fname, words, nbits)
% Writes each element of int32 array 'words' as a zero-padded
% nbits-wide two's-complement binary string, one per line.

    fid = fopen(fname, 'w');
    if fid < 0
        error('Cannot open %s for writing.', fname);
    end

    mask = uint32(2^nbits - 1);   % e.g. 0x00000FFF for 12 bits

    n = numel(words);
    for i = 1:n
        % Two's complement: cast to uint32 then mask to nbits
        raw = bitand(uint32(typecast(int32(words(i)), 'uint32')), mask);
        % Format as nbits-wide binary string
        fprintf(fid, '%s\n', dec2bin(raw, nbits));
    end

    fclose(fid);
end
