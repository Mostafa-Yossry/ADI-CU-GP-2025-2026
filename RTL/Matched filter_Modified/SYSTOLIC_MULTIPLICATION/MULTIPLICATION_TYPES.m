function T = MULTIPLICATION_TYPES(type, length)
%% =========================================================
%  MULTIPLICATION_TYPES  -  Fixed-Point Type Definitions
%  for systolic_matmul_8_8__8_8  and  systolic_matmul_8_8__8_1
%
%  2's complement format: WL = IntBits + FL
%  IntBits INCLUDES the sign bit (MSB).
%  fi([], 1, WL, FL)
%    MaxPos = (2^(WL-1) - 1) * 2^(-FL)
%    MinNeg = -2^(WL-1)      * 2^(-FL)
%
%% =========================================================

  F = fimath('RoundingMethod','Convergent');

  switch type

    % ------------------------------------------------------------------
    %  DOUBLE  (float pass-through for reference)
    % ------------------------------------------------------------------
    case 'double'
        T.P      = double([]);
        T.Sigma2 = double([]);
        T.mult   = double([]);
        T.H      = double([]);
        T.Y      = double([]);
        T.Q1_    = double([]);
        T.Q2_    = double([]);
        T.Q3_    = double([]);
        T.Q4_    = double([]);
        T.Q5_    = double([]);
        T.Q6_    = double([]);
        T.Q7_    = double([]);
        T.Q6_6   = double([]);
        T.Q7_5   = double([]);
        T.Q1_11  = double([]);

    % ------------------------------------------------------------------
    %  SINGLE  (float pass-through for reference)
    % ------------------------------------------------------------------
    case 'single'
        T.P      = single([]);
        T.Sigma2 = single([]);
        T.mult   = single([]);
        T.H      = single([]);
        T.Y      = single([]);
        T.Q1_    = single([]);
        T.Q2_    = single([]);
        T.Q3_    = single([]);
        T.Q4_    = single([]);
        T.Q5_    = single([]);
        T.Q6_    = single([]);
        T.Q7_    = single([]);
        T.Q8_    = single([]);
        T.Q1_11  = single([]);
        T.Q6_6   = single([]);
        T.Q7_5   = single([]);
        T.Q8_4   = single([]);

    % ------------------------------------------------------------------
    %  ORIGINAL 64x8 configuration  (keep untouched)
    % ------------------------------------------------------------------
    case 'fixed_point_G'
        T.P      = fi([], 1,    5 + 7,         7     , 'fimath', F);
        T.Sigma2 = fi([], 1,    6 + 6,         6     , 'fimath', F);
        T.mult   = fi([], 1, 2*length, 2*(length - 1), 'fimath', F);
        T.H      = fi([], 1,   length,    length - 1 , 'fimath', F);
        T.Q2_    = fi([], 1,   length,    length - 8 , 'fimath', F);
        T.Q3_    = fi([], 1,   length,    length - 8 , 'fimath', F);
        T.Q4_    = fi([], 1,   length,    length - 8 , 'fimath', F);
        T.Q5_    = fi([], 1,   length,    length - 8 , 'fimath', F);
        T.Q6_    = fi([], 1,   length,    length - 8 , 'fimath', F);
        T.Q7_    = fi([], 1,   length,    length - 8 , 'fimath', F);
        T.Q8_    = fi([], 1,   length,    length - 8 , 'fimath', F);
        T.Q7_5   = fi([], 1,    7 + 5,        5      , 'fimath', F);
        T.Q8_4   = fi([], 1,    8 + 4,        4      , 'fimath', F);

    case 'fixed_point_Z'
        T.mult   = fi([], 1, 2*length, 2*(length - 1), 'fimath', F);
        T.H      = fi([], 1,   length,    length - 1 , 'fimath', F);
        T.Y      = fi([], 1,   length,    length - 1 , 'fimath', F);
        T.Q2_    = fi([], 1,   length,    length - 6 , 'fimath', F);
        T.Q3_    = fi([], 1,   length,    length - 6 , 'fimath', F);
        T.Q4_    = fi([], 1,   length,    length - 6 , 'fimath', F);
        T.Q5_    = fi([], 1,   length,    length - 6 , 'fimath', F);
        T.Q6_    = fi([], 1,   length,    length - 6 , 'fimath', F);
        T.Q6_6   = fi([], 1,    6 + 6,        6      , 'fimath', F);

    case 'fixed_point_GZ'
        T.mult   = fi([], 1, 2*length, 2*(length - 1), 'fimath', F);
        T.Q1_    = fi([], 1,   length,    length - 1 , 'fimath', F);
        T.Q6_    = fi([], 1,   length,    length - 6 , 'fimath', F);
        T.Q1_11  = fi([], 1,    1 + 11,       11     , 'fimath', F);

    % ------------------------------------------------------------------
    %  8x8 MMSE: G = H^H*H + sigma2*I
    %
    %  Input:  H in Q1.(WL-1)  --> 12-bit: Q1.11, MaxPos=0.9995
    %  mult:   full-precision product, 2*WL bits
    %
    %  Bit-growth budget (K=8 complex accumulations):
    %    Complex product (a+jb)(c+jd): real part = ac-bd
    %    Each input bounded by 1 --> |ac|<=1, |bd|<=1 --> |ac-bd|<=2
    %    So each product real/imag part is bounded by 2, not 1.
    %
    %    After k accumulations the max value is k*2:
    %      k=1  -> max=2   -> IntBits=2  -> Q2_
    %      k=2  -> max=4   -> IntBits=3  -> Q3_
    %      k=4  -> max=8   -> IntBits=4  -> Q4_
    %      k=8  -> max=16  -> IntBits=5  -> Q5_
    %    (IntBits includes sign bit, so IntBits=5 -> MaxPos=15.999 at 12-bit FL=7)
    %
    %    Diagonal: add sigma2~63 at SNR=-18dB -> needs IntBits=8
    %    -> Q6_ uses WL-8 fractional bits for MMSE
    %
    %  Signal      WL  FL      IntBits  MaxPos    Notes
    %  H           12  11          2    0.9995    Q1.11 input
    %  mult        24  22          2    ~4.0      full product
    %  Q2_         12  10          2    1.9995    after k=1  (max=2)
    %  Q3_         12   9          3    3.999     after k=2  (max=4)
    %  Q4_         12   8          4    7.999     after k=3..4 (max=8)
    %  Q5_         12   7          5   15.999     after k=5..8 (max=16)
    %  Sigma2      12   4          8  127.940     sigma2/P~63 at SNR=-18dB
    %  Q6_         12   4          8  127.940     diagonal max=8+63=71
    % ------------------------------------------------------------------
    case 'fixed_point_G_8x8_MMSE'
        T.mult   = fi([], 1, 2*length, 2*(length - 1), 'fimath', F);  % FL=22  IntBits=2
        T.H      = fi([], 1,   length,    length - 1 , 'fimath', F);  % FL=11  IntBits=1  Q1.11
        T.Q2_    = fi([], 1,   length,    length - 2 , 'fimath', F);  % FL=10  IntBits=2  MaxPos=1.9995
        T.Q3_    = fi([], 1,   length,    length - 3 , 'fimath', F);  % FL=9   IntBits=3  MaxPos=3.999
        T.Q4_    = fi([], 1,   length,    length - 4 , 'fimath', F);  % FL=8   IntBits=4  MaxPos=7.999
        T.Q5_    = fi([], 1,   length,    length - 5 , 'fimath', F);  % FL=7   IntBits=5  MaxPos=15.999
        T.Sigma2 = fi([], 1,   length,    length - 8 , 'fimath', F);  % FL=4   IntBits=8  MaxPos=127.94
        T.Q6_    = fi([], 1,   length,    length - 8 , 'fimath', F);  % FL=4   IntBits=8  MaxPos=127.94

    % ------------------------------------------------------------------
    %  8x8 ZF: G = H^H*H  (sigma2=0, no regularization)
    %
    %  With no sigma2 term, diagonal max ~ 8 (K=8 terms, |H|<=1).
    %  IntBits needs only 4 (not 8) on diagonal -> 3 extra FL bits
    %  vs MMSE -> approximately +18 dB SQNR improvement.
    %
    %  Signal      WL  FL      IntBits  MaxPos    Notes
    %  H           12  11          2    0.9995    Q1.11 input
    %  mult        24  22          2    ~4.0      full product
    %  Q2_         12  10          2    1.9995    after k=1
    %  Q3_         12   9          3    3.999     after k=2
    %  Q4_         12   8          4    7.999     after k=3..4
    %  Q5_         12   7          5   15.999     after k=5..8 (max=16)
    %  Sigma2      12   7          5   15.999     ZF: sigma2=0, same as Q5_
    %  Q6_         12   7          5   15.999     ZF output: no regularization
    % ------------------------------------------------------------------
    case 'fixed_point_G_8x8_ZF'
        T.mult   = fi([], 1, 2*length, 2*(length - 1), 'fimath', F);  % FL=22  IntBits=2
        T.H      = fi([], 1,   length,    length - 1 , 'fimath', F);  % FL=11  IntBits=2  Q1.11
        T.Q2_    = fi([], 1,   length,    length - 2 , 'fimath', F);  % FL=10  IntBits=2  MaxPos=1.9995
        T.Q3_    = fi([], 1,   length,    length - 3 , 'fimath', F);  % FL=9   IntBits=3  MaxPos=3.999
        T.Q4_    = fi([], 1,   length,    length - 4 , 'fimath', F);  % FL=8   IntBits=4  MaxPos=7.999
        T.Q5_    = fi([], 1,   length,    length - 5 , 'fimath', F);  % FL=7   IntBits=5  MaxPos=15.999
        T.Sigma2 = fi([], 1,   length,    length - 5 , 'fimath', F);  % FL=7   ZF: sigma2=0 (harmless)
        T.Q6_    = fi([], 1,   length,    length - 5 , 'fimath', F);  % FL=7   IntBits=5  MaxPos=15.999

    % ------------------------------------------------------------------
    %  8x8 Z = H^H * Y  (uses systolic_matmul_8_8__8_1)
    %
    %  FIELD MAPPING in systolic_matmul_8_8__8_1:
    %    T.H     --> A input  (H^H rows)    : Q1.(WL-1)   MUST be T.H not T.Q1_
    %    T.Q6_   --> B input  (Y column)    : Q1.(WL-1)
    %    T.mult  --> full product           : Q2.(2*WL-2)
    %    T.Q2_   --> accumulator after k=1  : IntBits=2
    %    T.Q3_   --> accumulator after k=2  : IntBits=3
    %    T.Q4_   --> accumulator after k=3..4 : IntBits=4
    %    T.Q5_   --> accumulator after k=5..8 : IntBits=5
    %    T.Q1_11 --> output                 : same format as Q5_
    %
    %  Bit-growth identical to G_8x8 (same K=8, same input bounds):
    %    Complex product real part: ac-bd, max = 1*1 + 1*1 = 2
    %    k=1: max=2, k=2: max=4, k=4: max=8, k=8: max=16
    %
    %  Signal      WL  FL      IntBits  MaxPos    Notes
    %  H           12  11          2    0.9995    Q1.11 H^H input
    %  Q6_         12  11          2    0.9995    Q1.11 Y input (reuse field name)
    %  mult        24  22          2    ~4.0      full product
    %  Q2_         12  10          2    1.9995    after k=1  (max=2)
    %  Q3_         12   9          3    3.999     after k=2  (max=4)
    %  Q4_         12   8          4    7.999     after k=3..4 (max=8)
    %  Q5_         12   7          5   15.999     after k=5..8 (max=16)
    %  Q1_11       12   7          5   15.999     output Z = H^H*Y
    %
    %  KEY FIX (v2 -> v3):
    %  Previous version had:
    %    T.Q6_ = fi([], 1, WL, WL-1) -> correct for Y input
    %    T.Q1_ = fi([], 1, WL, WL-6) -> WRONG: was used to cast A (H^H)
    %  systolic_matmul_8_8__8_1 v1 cast A to T.Q1_ -> truncated H^H to FL=6
    %  before multiplication -> lost 5 fractional bits -> SQNR ~33-38 dB
    %  Fix: systolic_matmul_8_8__8_1 now casts A to T.H (FL=11) correctly.
    %  T.Q1_ field kept for backward compatibility but no longer used by
    %  the main compute path.
    % ------------------------------------------------------------------
    case 'fixed_point_Z_8x8'
        T.mult   = fi([], 1, 2*length, 2*(length - 1), 'fimath', F);  % FL=22  IntBits=2  full product
        T.H      = fi([], 1,   length,    length - 1 , 'fimath', F);  % FL=11  IntBits=2  Q1.11 H^H input
        T.Q6_    = fi([], 1,   length,    length - 1 , 'fimath', F);  % FL=11  IntBits=2  Q1.11 Y input
        T.Q2_    = fi([], 1,   length,    length - 2 , 'fimath', F);  % FL=10  IntBits=2  MaxPos=1.9995
        T.Q3_    = fi([], 1,   length,    length - 3 , 'fimath', F);  % FL=9   IntBits=3  MaxPos=3.999
        T.Q4_    = fi([], 1,   length,    length - 4 , 'fimath', F);  % FL=8   IntBits=4  MaxPos=7.999
        T.Q5_    = fi([], 1,   length,    length - 5 , 'fimath', F);  % FL=7   IntBits=5  MaxPos=15.999
        T.Q1_11  = fi([], 1,   length,    length - 5 , 'fimath', F);  % FL=7   IntBits=5  output Z
        T.Q1_    = fi([], 1,   length,    length - 5 , 'fimath', F);  % FL=7   (kept for compat, not used)

  end
end