% ---------------------------------------------------------
% Systolic Array Matrix Multiplication (Floating-Point)
% Simulates the weight-stationary systolic data flow:
%   Each PE accumulates dot-product over time steps.
%   Data skew is applied to simulate pipeline latency.
% ---------------------------------------------------------

function C = systolic_matmul_8_64__64_8(A, B, sigma2_over_P, T)
    [M, K]        = size(A);
    [~, N]        = size(B);
    C             = complex( zeros(M, N, 'like', T.Q8_) );
    sigma2_over_P = cast(sigma2_over_P , 'like', T.Q7_);
    A             = cast(A, 'like', T.H);
    B             = cast(B, 'like', T.H);

    % Weight-stationary: weights (A) stay in PEs
    % Inputs (B columns) stream through with skew
    for i = 1:M
        for j = 1:N
            acc_Q2_  = complex( zeros(1,1, 'like', T.Q2_) );
            acc_Q3_  = complex( zeros(1,1, 'like', T.Q3_)  );
            acc_Q4_  = complex( zeros(1,1, 'like', T.Q4_)  );
            acc_Q5_  = complex( zeros(1,1, 'like', T.Q5_)  );
            acc_Q6_  = complex( zeros(1,1, 'like', T.Q6_)  );
            acc_Q7_  = complex( zeros(1,1, 'like', T.Q7_)  );
            for k = 1:K
                mult = cast(A(i,k) * B(k,j), 'like', T.mult);
                % Each PE: multiply-accumulate
                if(k == 1)
                    mult_Q2_ = cast(mult    , 'like', T.Q2_);
                    acc_Q2_  = cast(mult_Q2_, 'like', T.Q2_);
                end

                if(k == 2)
                    mult_Q2_ = cast(mult              , 'like', T.Q2_);
                    acc_Q3_  = cast(acc_Q2_ + mult_Q2_, 'like', T.Q3_);
                end

                if((k >= 3) && (k <= 4))
                    if(k == 3)
                      mult_Q3_ = cast(mult              , 'like', T.Q3_);
                      acc_Q4_  = cast(acc_Q3_ + mult_Q3_, 'like', T.Q4_);
                    else
                      mult_Q4_ = cast(mult              , 'like', T.Q4_);
                      acc_Q4_  = cast(acc_Q4_ + mult_Q4_, 'like', T.Q4_);
                    end
                end

                if((k >= 5) && (k <= 12))
                    if(k == 5)
                      mult_Q4_ = cast(mult              , 'like', T.Q4_);
                      acc_Q5_  = cast(acc_Q4_ + mult_Q4_, 'like', T.Q5_);
                    else
                      mult_Q5_ = cast(mult              , 'like', T.Q5_);
                      acc_Q5_  = cast(acc_Q5_ + mult_Q5_, 'like', T.Q5_);
                    end
                end

                if((k >= 13) && (k <= 28))
                    if(k == 13)
                      mult_Q5_ = cast(mult              , 'like', T.Q5_);
                      acc_Q6_  = cast(acc_Q5_ + mult_Q5_, 'like', T.Q6_);
                    else
                      mult_Q6_ = cast(mult, 'like', T.Q6_);
                      acc_Q6_  = cast(acc_Q6_ + mult_Q6_, 'like', T.Q6_);
                    end
                end

                if((k >= 29) && (k <= 64))
                    if(k == 29)
                      mult_Q6_ = cast(mult              , 'like', T.Q6_);
                      acc_Q7_  = cast(acc_Q6_ + mult_Q6_, 'like', T.Q7_);
                    else
                      mult_Q7_ = cast(mult              , 'like', T.Q7_);
                      acc_Q7_  = cast(acc_Q7_ + mult_Q7_, 'like', T.Q7_);
                    end
                end
                
                %% useful for track fixed point
                switch k
                    case 1,  acc_array_1  = acc_Q2_;

                    case 2,  acc_array_2  = acc_Q3_;

                    case 3,  acc_array_3  = acc_Q4_;
                    case 4,  acc_array_4  = acc_Q4_;

                    case 5,  acc_array_5  = acc_Q5_;
                    case 6,  acc_array_6  = acc_Q5_;
                    case 7,  acc_array_7  = acc_Q5_;
                    case 8,  acc_array_8  = acc_Q5_;
                    case 9,  acc_array_9  = acc_Q5_;
                    case 10, acc_array_10 = acc_Q5_;
                    case 11, acc_array_11 = acc_Q5_;
                    case 12, acc_array_12 = acc_Q5_;

                    case 13, acc_array_13 = acc_Q6_;
                    case 14, acc_array_14 = acc_Q6_;
                    case 15, acc_array_15 = acc_Q6_;
                    case 16, acc_array_16 = acc_Q6_;
                    case 17, acc_array_17 = acc_Q6_;
                    case 18, acc_array_18 = acc_Q6_;
                    case 19, acc_array_19 = acc_Q6_;
                    case 20, acc_array_20 = acc_Q6_;
                    case 21, acc_array_21 = acc_Q6_;
                    case 22, acc_array_22 = acc_Q6_;
                    case 23, acc_array_23 = acc_Q6_;
                    case 24, acc_array_24 = acc_Q6_;
                    case 25, acc_array_25 = acc_Q6_;
                    case 26, acc_array_26 = acc_Q6_;
                    case 27, acc_array_27 = acc_Q6_;
                    case 28, acc_array_28 = acc_Q6_;

                    case 29, acc_array_29 = acc_Q7_;
                    case 30, acc_array_30 = acc_Q7_;
                    case 31, acc_array_31 = acc_Q7_;
                    case 32, acc_array_32 = acc_Q7_;
                    case 33, acc_array_33 = acc_Q7_;
                    case 34, acc_array_34 = acc_Q7_;
                    case 35, acc_array_35 = acc_Q7_;
                    case 36, acc_array_36 = acc_Q7_;
                    case 37, acc_array_37 = acc_Q7_;
                    case 38, acc_array_38 = acc_Q7_;
                    case 39, acc_array_39 = acc_Q7_;
                    case 40, acc_array_40 = acc_Q7_;
                    case 41, acc_array_41 = acc_Q7_;
                    case 42, acc_array_42 = acc_Q7_;
                    case 43, acc_array_43 = acc_Q7_;
                    case 44, acc_array_44 = acc_Q7_;
                    case 45, acc_array_45 = acc_Q7_;
                    case 46, acc_array_46 = acc_Q7_;
                    case 47, acc_array_47 = acc_Q7_;
                    case 48, acc_array_48 = acc_Q7_;
                    case 49, acc_array_49 = acc_Q7_;
                    case 50, acc_array_50 = acc_Q7_;
                    case 51, acc_array_51 = acc_Q7_;
                    case 52, acc_array_52 = acc_Q7_;
                    case 53, acc_array_53 = acc_Q7_;
                    case 54, acc_array_54 = acc_Q7_;
                    case 55, acc_array_55 = acc_Q7_;
                    case 56, acc_array_56 = acc_Q7_;
                    case 57, acc_array_57 = acc_Q7_;
                    case 58, acc_array_58 = acc_Q7_;
                    case 59, acc_array_59 = acc_Q7_;
                    case 60, acc_array_60 = acc_Q7_;
                    case 61, acc_array_61 = acc_Q7_;
                    case 62, acc_array_62 = acc_Q7_;
                    case 63, acc_array_63 = acc_Q7_;
                    case 64, acc_array_64 = acc_Q7_;
                end
            end
            if(i == j)
                C(i,j) = cast(acc_Q7_ + sigma2_over_P, 'like', T.Q8_);
            else
                C(i,j) = cast(acc_Q7_                , 'like', T.Q8_);
            end
        end
    end
end