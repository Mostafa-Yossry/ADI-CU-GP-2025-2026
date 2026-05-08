% ---------------------------------------------------------
% Systolic Array Matrix Multiplication : 8x8 * 8x1 = 8x1
% Computes Z = H^H * Y  (matched filter output)
%
% Dimensions (8x8 MIMO):
%   A : 8x8  (H^H)
%   B : 8x1  (Y, received signal vector)
%   C : 8x1  (Z = H^H*Y, matched filter output)
%
% Bit-growth schedule (K=8 accumulations, identical to 8x8):
%   k=1        : Q2_  (1 term,  no extra int bits beyond product)
%   k=2        : Q3_  (2 terms, +1 int bit)
%   k=3 to 4   : Q4_  (4 terms, +1 int bit)
%   k=5 to 8   : Q5_  (8 terms, +1 int bit)
%   output     : Q5_  (no regularization term for Z)
%
% Fixed-Point Notes:
%   - A (H^H rows)  cast to T.H     : Q1.(WL-1)  -- preserves input precision
%   - B (Y column)  cast to T.Q6_   : Q1.(WL-1)  -- preserves input precision
%   - Full product  cast to T.mult   : Q2.(2*WL-2)
%   - Accumulation follows staged bit-growth (same as 8x8 Gram matrix)
%   - Output        cast to T.Q1_11 : matches Q5_ accumulator format
%
% CRITICAL BUG FIXED (v2):
%   Previous version cast A to T.Q1_ (FL=6) instead of T.H (FL=11).
%   This discarded 5 fractional bits of H^H BEFORE multiplication,
%   directly causing ~33-38 dB SQNR instead of >40 dB target.
%   Also: no staged accumulation -> single flat register lost precision
%   at every intermediate step.
% ---------------------------------------------------------

function C = systolic_matmul_8_8__8_1(A, B, T)
    [M, K]    = size(A);
    [~, N]    = size(B);

    C = complex( zeros(M, N, 'like', T.Q1_11) );

    %% --- CRITICAL: cast A to T.H (Q1.11), NOT T.Q1_ ---
    %  T.H preserves the full Q1.(WL-1) precision of H^H.
    %  Casting to T.Q1_ here would truncate 5 fractional bits
    %  before any multiplication -- a catastrophic precision loss.
    A = cast(A, 'like', T.H);
    B = cast(B, 'like', T.Q6_);

    %% Weight-stationary systolic data flow:
    %   Weights (A rows) stay in PEs
    %   Inputs (B column) stream through with skew
    for i = 1:M
        for j = 1:N

            %% --- Staged accumulators (same bit-growth as 8x8) ---
            acc_Q2_ = complex( zeros(1,1, 'like', T.Q2_) );
            acc_Q3_ = complex( zeros(1,1, 'like', T.Q3_) );
            acc_Q4_ = complex( zeros(1,1, 'like', T.Q4_) );
            acc_Q5_ = complex( zeros(1,1, 'like', T.Q5_) );

            for k = 1:K

                mult = cast(A(i,k) * B(k,j), 'like', T.mult);

                %% --- Bit-growth accumulation stages ---
                %  Each stage adds 1 integer bit when the number of
                %  accumulated terms doubles. This prevents saturation
                %  while keeping maximum fractional precision at each step.

                if (k == 1)
                    mult_Q2_ = cast(mult,     'like', T.Q2_);
                    acc_Q2_  = cast(mult_Q2_, 'like', T.Q2_);
                end

                if (k == 2)
                    mult_Q2_ = cast(mult,               'like', T.Q2_);
                    acc_Q3_  = cast(acc_Q2_ + mult_Q2_, 'like', T.Q3_);
                end

                if ((k >= 3) && (k <= 4))
                    if (k == 3)
                        mult_Q3_ = cast(mult,               'like', T.Q3_);
                        acc_Q4_  = cast(acc_Q3_ + mult_Q3_, 'like', T.Q4_);
                    else
                        mult_Q4_ = cast(mult,               'like', T.Q4_);
                        acc_Q4_  = cast(acc_Q4_ + mult_Q4_, 'like', T.Q4_);
                    end
                end

                if ((k >= 5) && (k <= 8))
                    if (k == 5)
                        mult_Q4_ = cast(mult,               'like', T.Q4_);
                        acc_Q5_  = cast(acc_Q4_ + mult_Q4_, 'like', T.Q5_);
                    else
                        mult_Q5_ = cast(mult,               'like', T.Q5_);
                        acc_Q5_  = cast(acc_Q5_ + mult_Q5_, 'like', T.Q5_);
                    end
                end

                %% --- Snapshot array (for instrumentation / debug) ---
                switch k
                    case 1,  acc_array_1 = acc_Q2_;
                    case 2,  acc_array_2 = acc_Q3_;
                    case 3,  acc_array_3 = acc_Q4_;
                    case 4,  acc_array_4 = acc_Q4_;
                    case 5,  acc_array_5 = acc_Q5_;
                    case 6,  acc_array_6 = acc_Q5_;
                    case 7,  acc_array_7 = acc_Q5_;
                    case 8,  acc_array_8 = acc_Q5_;
                end

            end % k loop

            %% --- Write output ---
            %  No regularization term for Z (unlike Gram matrix G).
            C(i,j) = cast(acc_Q5_, 'like', T.Q1_11);

        end % j loop
    end % i loop
end