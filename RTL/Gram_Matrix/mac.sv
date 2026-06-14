//==============================================================================
// mac.sv
//------------------------------------------------------------------------------
// Computes ONE element of the Hermitian Gram matrix G = H^H * H + sigma^2 * I:
//
//        G[row][col] = sum over k=0..MAT_DIM-1 of  HH[row][k] * H[k][col]
//                      ( + sigma^2  if row == col )
//
// HH and H are complex. Each step is a COMPLEX multiply:
//
//        (a + jb)(c + jd) = (ac - bd) + j(ad + bc)
//
// accumulated into a real accumulator and an imag accumulator.
//
// Fixed-point widths (inputs are 12-bit signed):
//        input element        : DATA_W = 12
//        one real multiply    : 24 bits   (12 x 12)
//        complex combine      : 25 bits   (ac - bd)
//        accumulate 8 terms   : 28 bits   (+log2(8) = +3)   -> ACC_W
//        round to even        : ACC_W -> G_W
//
// Assumptions:
//   * HH and H memories give combinational reads (registers / distributed RAM),
//     so the element addressed this cycle is available this cycle.
//   * The controller holds row/col/is_diag steady from mac_start until mac_done.
//
// Flow:  IDLE -> ACCUM (8 cycles) -> FINISH (sigma + round, pulse mac_done)
//==============================================================================
module mac #(
    parameter int DATA_W  = 12,                                   // input element width (signed)
    parameter int MAT_DIM = 8,                                    // matrix dimension
    parameter int IDX_W   = 3,                                    // bits for row/col/k (0..7)
    parameter int G_W     = 12,                                   // stored G width (Q7.4, 12-bit)
    // accumulator width: 2*DATA_W (product) + 1 (complex combine) + log2(MAT_DIM) (sum)
    parameter int ACC_W   = 2*DATA_W + 1 + $clog2(MAT_DIM),       // = 28
    parameter int MEM_AW  = 2*IDX_W                               // address into an 8x8 memory (=6)
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ---- control from the scheduler ----
    input  logic                     mac_start,   // pulse: compute this element
    input  logic [IDX_W-1:0]         row,         // element row  i
    input  logic [IDX_W-1:0]         col,         // element col  j
    input  logic                     is_diag,     // 1 -> add sigma^2

    // ---- read interface to the HH and H memories ----
    output logic [MEM_AW-1:0]        hh_addr,     // address of HH[row][k]
    output logic [MEM_AW-1:0]        h_addr,      // address of H[k][col]
    input  logic signed [DATA_W-1:0] hh_real,     // HH[row][k]
    input  logic signed [DATA_W-1:0] hh_imag,
    input  logic signed [DATA_W-1:0] h_real,      // H[k][col]
    input  logic signed [DATA_W-1:0] h_imag,

    // ---- result ----
    output logic signed [G_W-1:0]    g_real,
    output logic signed [G_W-1:0]    g_imag,
    output logic                     mac_done     // pulse: g_real/g_imag valid
);

    // sigma^2 constant at the OUTPUT (12-bit G) scale -- added AFTER rounding,
    // only on the diagonal. 1010 = 0b0011_1111_0010.
    localparam logic signed [G_W-1:0] SIGMA2 = 1010;

    // Convergent rounding drops the low ROUND_BITS of the accumulator.
    // The accumulator carries 22 fractional bits (Q*.22 from Q0.11 x Q0.11);
    // G keeps 4 fractional bits (Q7.4), so we drop 22 - 4 = 18.
    localparam int ROUND_BITS = 18;

    //--------------------------------------------------------------------------
    // FSM
    //--------------------------------------------------------------------------
    typedef enum logic [1:0] { IDLE, ACCUM, FINISH } state_t;
    state_t state;

    logic [IDX_W-1:0]        k;            // which term of the dot product (0..7)
    logic signed [ACC_W-1:0] acc_real;
    logic signed [ACC_W-1:0] acc_imag;

    // Address the k-th pair this cycle. HH walks along row `row`; H walks down
    // column `col`. (row*MAT_DIM + k) and (k*MAT_DIM + col) are linear addresses.
    assign hh_addr = row*MAT_DIM + k;
    assign h_addr  = k  *MAT_DIM + col;

    //--------------------------------------------------------------------------
    // Complex multiply of the current pair (pure combinational).
    //   hh = a + jb   ,   h = c + jd
    //   pr = ac - bd  ,   pi = ad + bc
    //--------------------------------------------------------------------------
    logic signed [2*DATA_W-1:0] ac, bd, ad, bc;
    logic signed [2*DATA_W:0]   pr, pi;     // 25-bit (one extra bit for the +/-)

    assign ac = hh_real * h_real;
    assign bd = hh_imag * h_imag;
    assign ad = hh_real * h_imag;
    assign bc = hh_imag * h_real;
    assign pr = ac - bd;
    assign pi = ad + bc;

    //--------------------------------------------------------------------------
    // Round-half-to-even (convergent rounding): ACC_W -> G_W
    //--------------------------------------------------------------------------
    function automatic logic signed [G_W-1:0] round_even (input logic signed [ACC_W-1:0] x);
        logic signed [G_W-1:0]      trunc;
        logic [ROUND_BITS-1:0]      frac;
        logic                       round_up;
        begin
            trunc = x >>> ROUND_BITS;                 // truncate toward -inf (arithmetic)
            frac  = x[ROUND_BITS-1:0];                // bits being discarded
            if (frac[ROUND_BITS-1] == 1'b0)
                round_up = 1'b0;                      // remainder < 0.5  -> down
            else if (|frac[ROUND_BITS-2:0])
                round_up = 1'b1;                      // remainder > 0.5  -> up
            else
                round_up = trunc[0];                  // remainder == 0.5 -> to even
            round_even = trunc + round_up;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Sequential control + datapath
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            k        <= '0;
            acc_real <= '0;
            acc_imag <= '0;
            g_real   <= '0;
            g_imag   <= '0;
            mac_done <= 1'b0;
        end else begin
            mac_done <= 1'b0;                          // default: pulse stays low

            case (state)

                // Wait for the go pulse, clear the accumulators, start at k=0.
                IDLE: begin
                    k        <= '0;
                    acc_real <= '0;
                    acc_imag <= '0;
                    if (mac_start)
                        state <= ACCUM;
                end

                // One complex multiply-accumulate per cycle, k = 0 .. MAT_DIM-1.
                ACCUM: begin
                    acc_real <= acc_real + pr;        // pr/pi sign-extend into ACC_W
                    acc_imag <= acc_imag + pi;
                    if (k == MAT_DIM-1)
                        state <= FINISH;              // last term done after this cycle
                    else
                        k <= k + 1'b1;
                end

                // Round to 12-bit (convergent), THEN add sigma^2 on the
                // diagonal at the output scale. Diagonal imag is exactly 0.
                // If mac_start is still asserted, chain straight into the next
                // round's accumulation -- no idle cycle between rounds.
                FINISH: begin
                    g_real   <= round_even(acc_real) + (is_diag ? SIGMA2 : '0);
                    g_imag   <= is_diag ? '0 : round_even(acc_imag);
                    mac_done <= 1'b1;
                    if (mac_start) begin
                        k        <= '0;
                        acc_real <= '0;
                        acc_imag <= '0;
                        state    <= ACCUM;
                    end else
                        state    <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule