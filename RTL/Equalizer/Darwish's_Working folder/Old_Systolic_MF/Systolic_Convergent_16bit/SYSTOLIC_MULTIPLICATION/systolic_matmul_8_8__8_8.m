% ---------------------------------------------------------
% Systolic Array Matrix Multiplication : 8x8 * 8x8 = 8x8
% Computes G = H^H * H + sigma2_over_P * I
%
% Dimensions (8x8 MIMO):
%   A : 8x8  (H^H)
%   B : 8x8  (H)
%   C : 8x8  (Gram matrix G)
%
% Bit-growth schedule (K=8 accumulations):
%   k=1        : Q2  (1 term,  0 extra integer bits needed)
%   k=2        : Q3  (2 terms, 1 extra integer bit)
%   k=3 to 4   : Q4  (4 terms, 2 extra integer bits)
%   k=5 to 8   : Q5  (8 terms, 3 extra integer bits)
%   diagonal   : Q6  (add sigma2_over_P regularization term)
%
% Note: For ZF, sigma2_over_P = 0, so diagonal cast to Q6 is harmless.
% ---------------------------------------------------------

function C = systolic_matmul_8_8__8_8(A, B, sigma2_over_P, T)
    [M, K]        = size(A);
    [~, N]        = size(B);
    C             = complex( zeros(M, N, 'like', T.Q6_) );
    sigma2_over_P = cast(sigma2_over_P, 'like', T.Sigma2);  % dedicated type: enough int bits for SNR=-18dB
    A             = cast(A, 'like', T.H);
    B             = cast(B, 'like', T.H);

    % Weight-stationary systolic data flow:
    %   Weights (A rows) stay in PEs
    %   Inputs  (B columns) stream through with skew
    for i = 1:M
        for j = 1:N
            acc_Q2_ = complex( zeros(1,1, 'like', T.Q2_) );
            acc_Q3_ = complex( zeros(1,1, 'like', T.Q3_) );
            acc_Q4_ = complex( zeros(1,1, 'like', T.Q4_) );
            acc_Q5_ = complex( zeros(1,1, 'like', T.Q5_) );

            for k = 1:K

                mult = cast(A(i,k) * B(k,j), 'like', T.mult);

                %% --- Bit-growth accumulation stages ---

                if (k == 1)
                    mult_Q2_ = cast(mult    , 'like', T.Q2_);
                    acc_Q2_  = cast(mult_Q2_, 'like', T.Q2_);
                end

                if (k == 2)
                    mult_Q2_ = cast(mult              , 'like', T.Q2_);
                    acc_Q3_  = cast(acc_Q2_ + mult_Q2_, 'like', T.Q3_);
                end

                if ((k >= 3) && (k <= 4))
                    if (k == 3)
                        mult_Q3_ = cast(mult              , 'like', T.Q3_);
                        acc_Q4_  = cast(acc_Q3_ + mult_Q3_, 'like', T.Q4_);
                    else
                        mult_Q4_ = cast(mult              , 'like', T.Q4_);
                        acc_Q4_  = cast(acc_Q4_ + mult_Q4_, 'like', T.Q4_);
                    end
                end

                if ((k >= 5) && (k <= 8))
                    if (k == 5)
                        mult_Q4_ = cast(mult              , 'like', T.Q4_);
                        acc_Q5_  = cast(acc_Q4_ + mult_Q4_, 'like', T.Q5_);
                    else
                        mult_Q5_ = cast(mult              , 'like', T.Q5_);
                        acc_Q5_  = cast(acc_Q5_ + mult_Q5_, 'like', T.Q5_);
                    end
                end

                %% --- Snapshot array (useful for instrumentation / debug) ---
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
            end

            %% --- Write output (add regularization on diagonal) ---
            if (i == j)
                C(i,j) = cast(acc_Q5_ + sigma2_over_P, 'like', T.Q6_);
            else
                C(i,j) = cast(acc_Q5_                , 'like', T.Q6_);
            end
        end
    end
end