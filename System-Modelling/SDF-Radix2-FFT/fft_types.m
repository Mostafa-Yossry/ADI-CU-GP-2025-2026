function T = fft_types(dtype, N)
% FFT_TYPES  Type table for FFT SDF model (N=4096)
% Supports: 'double', 'single', 'fxpt'

    nStages = log2(N);
    if mod(nStages,1)~=0
        error('N must be a power of 2');
    end

    switch lower(dtype)
        case 'double'
            for s = 1:nStages
                T.(sprintf('stage%d_in',s))  = double([]);
                T.(sprintf('add%d_vec',s))   = double([]);
                T.(sprintf('sub%d_vec',s))   = double([]);
                T.(sprintf('mul%d_vec',s))   = double([]);
                T.(sprintf('stage%d_out',s)) = double([]);
                T.(sprintf('W%d',s))         = double([]);
            end
            T.Y = double([]);

        case 'single'
            for s = 1:nStages
                T.(sprintf('stage%d_in',s))  = single([]);
                T.(sprintf('add%d_vec',s))   = single([]);
                T.(sprintf('sub%d_vec',s))   = single([]);
                T.(sprintf('mul%d_vec',s))   = single([]);
                T.(sprintf('stage%d_out',s)) = single([]);
                T.(sprintf('W%d',s))         = single([]);
            end
            T.Y = single([]);

        case 'fxpt'
            % === From instrumentation results (WL=12) ===

            % Twiddles (complex)
            T.W1  = fi([], 1, 2+10, 10);
            T.W2  = fi([], 1, 2+10, 10);
            T.W3  = fi([], 1, 2+10, 10);
            T.W4  = fi([], 1, 2+10, 10);
            T.W5  = fi([], 1, 2+10, 10);
            T.W6  = fi([], 1, 2+10, 10);
            T.W7  = fi([], 1, 2+10, 10);
            T.W8  = fi([], 1, 2+10, 10);
            T.W9  = fi([], 1, 2+10, 10);
            T.W10 = fi([], 1, 2+10, 10);
            T.W11 = fi([], 1, 2+10, 10);
            T.W12 = fi([], 1, 2+10, 10); % constant 1

            % Stage 1
            T.stage1_in  = fi([], 1, 1+11, 11); %
            T.add1_vec   = fi([], 1, 2+10, 10); %
            T.sub1_vec   = fi([], 1, 2+10, 10); %
            T.mul1_vec   = fi([], 1, 3+9, 9);
            T.stage1_out = fi([], 1, 3+9, 9);

            % Stage 2
            T.stage2_in  = fi([], 1, 3+9, 9);
            T.add2_vec   = fi([], 1, 4+8, 8);
            T.sub2_vec   = fi([], 1, 4+8, 8);
            T.mul2_vec   = fi([], 1, 4+8, 8);
            T.stage2_out = fi([], 1, 4+8, 8);

            % Stage 3
            T.stage3_in  = fi([], 1, 4+8, 8);
            T.add3_vec   = fi([], 1, 4+8, 8);
            T.sub3_vec   = fi([], 1, 4+8, 8);
            T.mul3_vec   = fi([], 1, 4+8, 8);
            T.stage3_out = fi([], 1, 4+8, 8);

            % Stage 4
            T.stage4_in  = fi([], 1, 4+8, 8);
            T.add4_vec   = fi([], 1, 5+7, 7);
            T.sub4_vec   = fi([], 1, 5+7, 7);
            T.mul4_vec   = fi([], 1, 5+7, 7);
            T.stage4_out = fi([], 1, 5+7, 7);

            % Stage 5
            T.stage5_in  = fi([], 1, 5+7, 7);
            T.add5_vec   = fi([], 1, 6+6, 6);
            T.sub5_vec   = fi([], 1, 6+6, 6);
            T.mul5_vec   = fi([], 1, 6+6, 6);
            T.stage5_out = fi([], 1, 6+6, 6);

            % Stage 6
            T.stage6_in  = fi([], 1, 6+6, 6);
            T.add6_vec   = fi([], 1, 6+6, 6);
            T.sub6_vec   = fi([], 1, 6+6, 6);
            T.mul6_vec   = fi([], 1, 6+6, 6);
            T.stage6_out = fi([], 1, 6+6, 6);

            % Stage 7
            T.stage7_in  = fi([], 1, 6+6, 6);
            T.add7_vec   = fi([], 1, 7+5, 5);
            T.sub7_vec   = fi([], 1, 7+5, 5);
            T.mul7_vec   = fi([], 1, 7+5, 5);
            T.stage7_out = fi([], 1, 7+5, 5);

            % Stage 8
            T.stage8_in  = fi([], 1, 7+5, 5);
            T.add8_vec   = fi([], 1, 7+5, 5);
            T.sub8_vec   = fi([], 1, 7+5, 5);
            T.mul8_vec   = fi([], 1, 7+5, 5);
            T.stage8_out = fi([], 1, 7+5,5);

            % Stage 9
            T.stage9_in  = fi([], 1, 7+5, 5);
            T.add9_vec   = fi([], 1, 8+4, 4); %
            T.sub9_vec   = fi([], 1, 8+4, 4);
            T.mul9_vec   = fi([], 1, 8+4, 4);
            T.stage9_out = fi([], 1, 8+4, 4);

            % Stage 10
            T.stage10_in  = fi([], 1, 8+4, 4);
            T.add10_vec   = fi([], 1, 8+4, 4);
            T.sub10_vec   = fi([], 1, 8+4, 4);
            T.mul10_vec   = fi([], 1, 8+4, 4);
            T.stage10_out = fi([], 1, 8+4, 4);

            % Stage 11
            T.stage11_in  = fi([], 1, 8+4, 4);
            T.add11_vec   = fi([], 1, 9+3, 3);
            T.sub11_vec   = fi([], 1, 9+3, 3);
            T.mul11_vec   = fi([], 1, 9+3, 3);
            T.stage11_out = fi([], 1, 9+3, 3);

            % Stage 12
            T.stage12_in  = fi([], 1, 9+3, 3);
            T.add12_vec   = fi([], 1, 9+3, 3);
            T.sub12_vec   = fi([], 1, 9+3, 3);
            T.mul12_vec   = fi([], 1, 9+3, 3);
            T.stage12_out = fi([], 1, 9+3, 3);

            % Output
            T.Y = fi([], 1, 9+3, 3);

            % Loop/index vars (unsigned integers)
            idxBits = ceil(log2(N));
            T.N          = fi([], 0, idxBits, 0);
            T.groupStart = fi([], 0, idxBits, 0);
            T.halfSize   = fi([], 0, idxBits, 0);
            T.idxA       = fi([], 0, idxBits, 0);
            T.idxB       = fi([], 0, idxBits, 0);
            T.j          = fi([], 0, idxBits, 0);
            T.pos        = fi([], 0, idxBits, 0);
            T.br_idx     = fi([], 0, idxBits, 0);

            % ========================================
            % APPLY UNBIASED ROUNDING FIMATH
            % ========================================
            F = fimath( ...
                'RoundingMethod','Convergent', ...
                'OverflowAction','Saturate', ...
                'ProductMode','FullPrecision', ...
                'SumMode','FullPrecision');

            fields = fieldnames(T);
            for k = 1:length(fields)
                if isa(T.(fields{k}), 'embedded.fi')
                    T.(fields{k}).fimath = F;
                end
            end

        otherwise
            error('Unsupported dtype: %s', dtype);
    end
end
