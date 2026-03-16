clear; clc; close all;

% PARAMETERS
N = 4096;             
nSeeds = 1000;
dtype = 'fxpt';      % try 'double', 'single', 'fxpt'

% load types
T = fft_types(dtype, N);


% prepare example input for instrumented mex build
exampleInput = cast(complex(zeros(N,1)), 'like', T.stage1_in);
buildInstrumentedMex('fft_dif_sdf', '-args', {exampleInput, T});

errPerSeed = zeros(1, nSeeds);
sqnrPerSeed = zeros(1, nSeeds);

for seed = 1:nSeeds
    rng(seed);

    input = (2*rand(N,1)-1) + 1j*(2*rand(N,1)-1);
    x = cast(input, 'like', T.stage1_in);

    if seed == 1
        buildInstrumentedMex fft_dif_sdf -args {x, T }
    end
    
    [Y_my] = fft_dif_sdf_mex(x, T);

    % MATLAB reference FFT, bit-reversed for DIF order
    Y_ref = fft(double(input));
    Y_ref = Y_ref(bitrevorder(1:N));

    errPerSeed(seed) = abs(mean(Y_ref - double(Y_my)));

    sigP = sum(abs(Y_ref).^2);
    noiseP = sum(abs(Y_ref - double(Y_my)).^2) + eps;
    sqnrPerSeed(seed) = 10*log10(sigP / noiseP);
end

% plots
figure;
plot(1:nSeeds, errPerSeed, 'LineWidth', 1.5);
xlabel('Seed'); ylabel('Mean error magnitude'); grid on;
title(sprintf('FFT mean error vs seed (%s, N=%d)', dtype, N));

figure;
plot(1:nSeeds, sqnrPerSeed, 'LineWidth', 1.5);
xlabel('Seed'); ylabel('SQNR (dB)'); grid on;
title(sprintf('FFT SQNR vs seed (%s, N=%d)', dtype, N));

fprintf('Average SQNR over %d seeds: %.2f dB\n', nSeeds, mean(sqnrPerSeed));
fprintf('Average mean error over %d seeds: %.3e\n', nSeeds, mean(errPerSeed));

% show instrumentation GUI
fprintf('\nTo run fractional-length proposal (example):\n');
fprintf(' showInstrumentationResults fft_dif_sdf_mex -proposeFL -defaultDT numerictype(1,32)\n\n');

showInstrumentationResults('fft_dif_sdf_mex');

% Example: access stage outputs
[Y_my, stage_outs] = fft_dif_sdf_mex(x, T);
disp(['Number of stages: ', num2str(numel(stage_outs))]);
