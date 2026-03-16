function [Y, stage_signals] = fft_dif_sdf(x, T) %#codegen
% FFT_DIF_SDF  Radix-2 DIF SDF model (N=4096, fully unrolled for fixed-point codegen)
% Each stage is written out explicitly so the code generator sees
% statically-typed assignments with no loop-carried type changes.

    N = 4096;
    assert(numel(x)==N, 'Input x must be length 4096.');

    stage_signals = cell(1,12);
    

    %% ---- STAGE 1 ----
    [add1_vec, sub1_vec, mul1_vec, stage1_out] = butterfly_stage( ...
        cast(x, 'like', T.stage1_in), N, 1, ...
        T.add1_vec, T.sub1_vec, T.mul1_vec, T.stage1_out, T.W1);
    sig1.in  = cast(x,'like',T.stage1_in);
    sig1.add = add1_vec; sig1.sub = sub1_vec;
    sig1.mul = mul1_vec; sig1.out = stage1_out;
    stage_signals{1} = sig1;

    %% ---- STAGE 2 ----
    [add2_vec, sub2_vec, mul2_vec, stage2_out] = butterfly_stage( ...
        cast(stage1_out, 'like', T.stage2_in), N, 2, ...
        T.add2_vec, T.sub2_vec, T.mul2_vec, T.stage2_out, T.W2);
    sig2.in  = cast(stage1_out,'like',T.stage2_in);
    sig2.add = add2_vec; sig2.sub = sub2_vec;
    sig2.mul = mul2_vec; sig2.out = stage2_out;
    stage_signals{2} = sig2;

    %% ---- STAGE 3 ----
    [add3_vec, sub3_vec, mul3_vec, stage3_out] = butterfly_stage( ...
        cast(stage2_out, 'like', T.stage3_in), N, 3, ...
        T.add3_vec, T.sub3_vec, T.mul3_vec, T.stage3_out, T.W3);
    sig3.in  = cast(stage2_out,'like',T.stage3_in);
    sig3.add = add3_vec; sig3.sub = sub3_vec;
    sig3.mul = mul3_vec; sig3.out = stage3_out;
    stage_signals{3} = sig3;

    %% ---- STAGE 4 ----
    [add4_vec, sub4_vec, mul4_vec, stage4_out] = butterfly_stage( ...
        cast(stage3_out, 'like', T.stage4_in), N, 4, ...
        T.add4_vec, T.sub4_vec, T.mul4_vec, T.stage4_out, T.W4);
    sig4.in  = cast(stage3_out,'like',T.stage4_in);
    sig4.add = add4_vec; sig4.sub = sub4_vec;
    sig4.mul = mul4_vec; sig4.out = stage4_out;
    stage_signals{4} = sig4;

    %% ---- STAGE 5 ----
    [add5_vec, sub5_vec, mul5_vec, stage5_out] = butterfly_stage( ...
        cast(stage4_out, 'like', T.stage5_in), N, 5, ...
        T.add5_vec, T.sub5_vec, T.mul5_vec, T.stage5_out, T.W5);
    sig5.in  = cast(stage4_out,'like',T.stage5_in);
    sig5.add = add5_vec; sig5.sub = sub5_vec;
    sig5.mul = mul5_vec; sig5.out = stage5_out;
    stage_signals{5} = sig5;

    %% ---- STAGE 6 ----
    [add6_vec, sub6_vec, mul6_vec, stage6_out] = butterfly_stage( ...
        cast(stage5_out, 'like', T.stage6_in), N, 6, ...
        T.add6_vec, T.sub6_vec, T.mul6_vec, T.stage6_out, T.W6);
    sig6.in  = cast(stage5_out,'like',T.stage6_in);
    sig6.add = add6_vec; sig6.sub = sub6_vec;
    sig6.mul = mul6_vec; sig6.out = stage6_out;
    stage_signals{6} = sig6;

    %% ---- STAGE 7 ----
    [add7_vec, sub7_vec, mul7_vec, stage7_out] = butterfly_stage( ...
        cast(stage6_out, 'like', T.stage7_in), N, 7, ...
        T.add7_vec, T.sub7_vec, T.mul7_vec, T.stage7_out, T.W7);
    sig7.in  = cast(stage6_out,'like',T.stage7_in);
    sig7.add = add7_vec; sig7.sub = sub7_vec;
    sig7.mul = mul7_vec; sig7.out = stage7_out;
    stage_signals{7} = sig7;

    %% ---- STAGE 8 ----
    [add8_vec, sub8_vec, mul8_vec, stage8_out] = butterfly_stage( ...
        cast(stage7_out, 'like', T.stage8_in), N, 8, ...
        T.add8_vec, T.sub8_vec, T.mul8_vec, T.stage8_out, T.W8);
    sig8.in  = cast(stage7_out,'like',T.stage8_in);
    sig8.add = add8_vec; sig8.sub = sub8_vec;
    sig8.mul = mul8_vec; sig8.out = stage8_out;
    stage_signals{8} = sig8;

    %% ---- STAGE 9 ----
    [add9_vec, sub9_vec, mul9_vec, stage9_out] = butterfly_stage( ...
        cast(stage8_out, 'like', T.stage9_in), N, 9, ...
        T.add9_vec, T.sub9_vec, T.mul9_vec, T.stage9_out, T.W9);
    sig9.in  = cast(stage8_out,'like',T.stage9_in);
    sig9.add = add9_vec; sig9.sub = sub9_vec;
    sig9.mul = mul9_vec; sig9.out = stage9_out;
    stage_signals{9} = sig9;

    %% ---- STAGE 10 ----
    [add10_vec, sub10_vec, mul10_vec, stage10_out] = butterfly_stage( ...
        cast(stage9_out, 'like', T.stage10_in), N, 10, ...
        T.add10_vec, T.sub10_vec, T.mul10_vec, T.stage10_out, T.W10);
    sig10.in  = cast(stage9_out,'like',T.stage10_in);
    sig10.add = add10_vec; sig10.sub = sub10_vec;
    sig10.mul = mul10_vec; sig10.out = stage10_out;
    stage_signals{10} = sig10;

    %% ---- STAGE 11 ----
    [add11_vec, sub11_vec, mul11_vec, stage11_out] = butterfly_stage( ...
        cast(stage10_out, 'like', T.stage11_in), N, 11, ...
        T.add11_vec, T.sub11_vec, T.mul11_vec, T.stage11_out, T.W11);
    sig11.in  = cast(stage10_out,'like',T.stage11_in);
    sig11.add = add11_vec; sig11.sub = sub11_vec;
    sig11.mul = mul11_vec; sig11.out = stage11_out;
    stage_signals{11} = sig11;

    %% ---- STAGE 12 ----
    [add12_vec, sub12_vec, mul12_vec, stage12_out] = butterfly_stage( ...
        cast(stage11_out, 'like', T.stage12_in), N, 12, ...
        T.add12_vec, T.sub12_vec, T.mul12_vec, T.stage12_out, T.W12);
    sig12.in  = cast(stage11_out,'like',T.stage12_in);
    sig12.add = add12_vec; sig12.sub = sub12_vec;
    sig12.mul = mul12_vec; sig12.out = stage12_out;
    stage_signals{12} = sig12;

    %% ---- Bit-reverse output ----
    %br_idx = bitrevorder(1:N);
    %Y = cast(stage12_out(br_idx), 'like', T.Y);
    Y = cast(stage12_out, 'like', T.Y);
end

%--------------------------------------------------------------------------
function [add_vec, sub_vec, mul_vec, stage_out] = butterfly_stage( ...
        stage_in, N, s, T_add, T_sub, T_mul, T_out, T_W) %#codegen
% BUTTERFLY_STAGE  One radix-2 DIF butterfly stage.
% All type information comes in as typed prototype scalars so the code
% generator sees a fully-typed, self-contained function.

    halfSize  = N / 2^s;
    groupSize = 2 * halfSize;
    numGroups = N / groupSize;

    % Twiddle factors for this stage: W_N^k, k=0..halfSize-1
    W = cast(exp(-1j*2*pi*(0:halfSize-1)/(2*halfSize)).', 'like', T_W);

    add_vec = cast(zeros(N/2,1) + 1i*zeros(N/2,1), 'like', T_add);
    sub_vec = cast(zeros(N/2,1) + 1i*zeros(N/2,1), 'like', T_sub);
    mul_vec = cast(zeros(N/2,1) + 1i*zeros(N/2,1), 'like', T_mul);
    stage_out = cast(zeros(N,1) + 1i*zeros(N,1), 'like', T_out);

    pos = 1;
    for g = 0:(numGroups-1)
        groupStart = g*groupSize + 1;
        for j = 0:(halfSize-1)
            idxA = groupStart + j;
            idxB = idxA + halfSize;

            % keep inputs in stage_in precision for the arithmetic
            a_full = stage_in(idxA);
            b_full = stage_in(idxB);
            
            % do the math at this (wider) precision, then quantize to the add/sub prototypes
            tmp_add = a_full + b_full;
            tmp_sub = a_full - b_full;
            
            add_vec(pos) = cast(tmp_add, 'like', T_add);
            sub_vec(pos) = cast(tmp_sub, 'like', T_sub);
            
            % multiply with twiddle (do multiplication in higher precision, then cast)
            tmp_mul = tmp_sub .* W(j+1);
            mul_vec(pos) = cast(tmp_mul, 'like', T_mul);
            stage_out(idxA) = cast(tmp_add, 'like', T_out);
            stage_out(idxB) = cast(tmp_mul, 'like', T_out);
            pos = pos + 1;
         end
    end

    % Cast BOTH halves to stage_out type before vertical-cat.
    % The code generator requires both operands of [;] to be the same type.
    % top = cast(add_vec, 'like', T_out);
    % bot = cast(mul_vec, 'like', T_out);
    % stage_out = [top; bot];
end