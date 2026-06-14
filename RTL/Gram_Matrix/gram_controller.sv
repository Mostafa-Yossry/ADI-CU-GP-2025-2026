//==============================================================================
// gram_controller.sv   (PIPELINED parallel version)
//------------------------------------------------------------------------------
// Same job as before: schedule the 36 lower-triangle elements of
// G = H^H*H + sigma^2*I onto N_LANES MAC lanes and write the results.
//
// SPEED CHANGE vs the simple version:
//   * No mac_done handshake. The lanes have a FIXED latency (MAT_DIM accumulate
//     cycles + 1 finish cycle = 9). The controller runs a cycle counter `cyc`
//     in lockstep with the lanes, so it always knows where they are.
//   * mac_start is held so the lanes chain ROUND-TO-ROUND with no idle gap
//     (the mac FINISH state goes straight back to ACCUM). 5 rounds back to back
//     = 45 cycles of compute instead of ~55-60 with per-round handshaking.
//   * A round's results are written into memory DURING the next round's compute
//     (store pipelined one round behind issue). One DRAIN cycle stores the last.
//
// Round timing (cyc 0..MAT_DIM):
//      cyc 0..MAT_DIM-1 : lanes ACCUMULATE element k = cyc
//      cyc == MAT_DIM   : lanes FINISH (round + sigma); round advances
//
// Ports are identical to the simple version, so top/testbench are unchanged.
// (mac_done is left as a port but is no longer used for timing.)
//==============================================================================
module gram_controller #(
    parameter int N_LANES   = 8,
    parameter int MAT_DIM   = 8,
    parameter int IDX_W     = 3,
    parameter int NUM_ELEMS = MAT_DIM*(MAT_DIM+1)/2,   // = 36
    parameter int ADDR_W    = 6
)(
    input  logic              clk,
    input  logic              rst_n,

    input  logic              start,
    input  logic              hh_valid,
    input  logic              mac_done,    // unused: fixed-latency pipeline

    output logic [IDX_W-1:0]  row        [N_LANES],
    output logic [IDX_W-1:0]  col        [N_LANES],
    output logic              is_diag    [N_LANES],
    output logic              lane_valid [N_LANES],
    output logic              mac_start,

    output logic              wr_en      [N_LANES],
    output logic [ADDR_W-1:0] wr_addr    [N_LANES],

    output logic              done
);

    localparam int NUM_ROUNDS = (NUM_ELEMS + N_LANES - 1) / N_LANES;   // 5
    localparam int RND_W = (NUM_ROUNDS <= 1) ? 1 : $clog2(NUM_ROUNDS);
    localparam int CYC_W = $clog2(MAT_DIM + 1);                        // cyc 0..MAT_DIM

    //--------------------------------------------------------------------------
    // Triangle order as constant tables (no initial block)
    //--------------------------------------------------------------------------
    localparam logic [IDX_W-1:0] ROW_LUT [0:NUM_ELEMS-1] = '{
        0,
        1,1,
        2,2,2,
        3,3,3,3,
        4,4,4,4,4,
        5,5,5,5,5,5,
        6,6,6,6,6,6,6,
        7,7,7,7,7,7,7,7
    };
    localparam logic [IDX_W-1:0] COL_LUT [0:NUM_ELEMS-1] = '{
        0,
        0,1,
        0,1,2,
        0,1,2,3,
        0,1,2,3,4,
        0,1,2,3,4,5,
        0,1,2,3,4,5,6,
        0,1,2,3,4,5,6,7
    };

    //--------------------------------------------------------------------------
    // Pipeline state
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] { IDLE, LAUNCH, RUN, DRAIN } state_t;
    state_t           state;
    logic [CYC_W-1:0] cyc;            // cycle within the current round
    logic [RND_W-1:0] issue_round;    // round the lanes are computing now
    logic [RND_W-1:0] store_round;    // round whose results are being written
    logic             store_valid;    // a completed round is available to store

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            cyc         <= '0;
            issue_round <= '0;
            store_round <= '0;
            store_valid <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    cyc         <= '0;
                    issue_round <= '0;
                    store_round <= '0;
                    store_valid <= 1'b0;
                    if (start && hh_valid)
                        state <= LAUNCH;
                end

                // One cycle with mac_start high while the lanes are still IDLE,
                // so they begin ACCUM next cycle aligned to RUN cyc 0.
                LAUNCH: begin
                    cyc         <= '0;
                    issue_round <= '0;
                    state       <= RUN;
                end

                RUN: begin
                    if (cyc == MAT_DIM) begin            // lanes are in FINISH now
                        store_round <= issue_round;      // this round's result is ready next cyc
                        store_valid <= 1'b1;
                        cyc         <= '0;
                        if (issue_round == NUM_ROUNDS-1)
                            state <= DRAIN;              // last round computed
                        else
                            issue_round <= issue_round + 1'b1;   // chain to next round
                    end else begin
                        cyc <= cyc + 1'b1;
                    end
                end

                // Write the final round's results AND signal done in the same
                // cycle (the write commits on this edge; done pulses with it).
                DRAIN: begin
                    store_valid <= 1'b0;
                    state       <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // mac_start: high to launch round 0 and to chain every round except the
    // FINISH of the last round (where the lanes must stop).
    //--------------------------------------------------------------------------
    assign mac_start = (state == LAUNCH) ||
                       (state == RUN && !((issue_round == NUM_ROUNDS-1) && (cyc == MAT_DIM)));

    //--------------------------------------------------------------------------
    // Store strobe: write the just-finished round during the next round's
    // first cycle (store_valid), or during DRAIN for the last round.
    //--------------------------------------------------------------------------
    logic do_store;
    assign do_store = (state == RUN && cyc == '0 && store_valid) || (state == DRAIN);

    assign done = (state == DRAIN);

    //--------------------------------------------------------------------------
    // Per-lane indices for the round being COMPUTED (issue_round)
    //--------------------------------------------------------------------------
    int lin_i;
    always_comb begin
        for (int l = 0; l < N_LANES; l++) begin
            lin_i = issue_round*N_LANES + l;
            if (lin_i < NUM_ELEMS) begin
                row[l]        = ROW_LUT[lin_i];
                col[l]        = COL_LUT[lin_i];
                is_diag[l]    = (ROW_LUT[lin_i] == COL_LUT[lin_i]);
                lane_valid[l] = 1'b1;
            end else begin
                row[l]        = '0;
                col[l]        = '0;
                is_diag[l]    = 1'b0;
                lane_valid[l] = 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Per-lane write address/enable for the round being STORED (store_round)
    //--------------------------------------------------------------------------
    int lin_s;
    always_comb begin
        for (int l = 0; l < N_LANES; l++) begin
            lin_s      = store_round*N_LANES + l;
            wr_addr[l] = (lin_s < NUM_ELEMS) ? lin_s[ADDR_W-1:0] : '0;
            wr_en[l]   = do_store && (lin_s < NUM_ELEMS);
        end
    end

endmodule