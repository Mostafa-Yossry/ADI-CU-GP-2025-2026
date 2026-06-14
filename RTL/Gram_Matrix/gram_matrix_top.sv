//==============================================================================
// gram_matrix_top.sv
//------------------------------------------------------------------------------
// Top level for G = H^H * H + sigma^2 * I, lower triangle only, 8 parallel
// MAC lanes (5 rounds x ~9 cycles ~= 45-cycle compute).
//
// Datapath:
//
//   H_in --[H buffer]--+--------------------------------> H matrix --+
//        (latch @start) |                                            |
//                       +--> hermitian_pipeW --> HH matrix ----------+
//                                                                    v
//   controller --(row/col/is_diag/valid, mac_start)--> mac_array --> gram_read_ports
//        ^   |                                              |  ^        (HH/H reads)
//        |   |                              (g_real/g_imag) |  +-- operands
//   mac_done |                                              v
//            +--(wr_en/wr_addr)--------------------> gram_mem (8 write ports)
//                                                          |
//                                                   rd_addr +--> rd_real/rd_imag
//
// Handshake:
//   * `start` latches H_in into the buffer and (one cycle later, when the
//     buffer is stable) pulses hermitian_pipeW.valid_in.
//   * hermitian_pipeW.valid_out -> latches hh_ready, telling the controller
//     HH has settled. Only then does the controller begin issuing rounds.
//   * Because HH is the registered image of the (held) buffered H, it stays
//     stable for the entire compute -- no need to re-pulse anything.
//==============================================================================
module gram_matrix_top #(
    parameter int MAT_DIM   = 8,
    parameter int N_LANES   = 8,                         // 8 -> 45-cycle compute
    parameter int DATA_W    = 12,                        // H / HH element width
    parameter int G_W       = 12,                        // stored G width
    parameter int IDX_W     = 3,
    parameter int NUM_ELEMS = MAT_DIM*(MAT_DIM+1)/2,     // 36
    parameter int ADDR_W    = 6,
    parameter int MEM_AW    = 2*IDX_W                    // 6
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ---- start a compute on a held, stable H_in ----
    input  logic                     start,
    input  logic signed [DATA_W-1:0] h_real_in [0:MAT_DIM-1][0:MAT_DIM-1],
    input  logic signed [DATA_W-1:0] h_imag_in [0:MAT_DIM-1][0:MAT_DIM-1],

    // ---- result available pulse + read-back port for Cholesky ----
    output logic                     done,
    input  logic [ADDR_W-1:0]        rd_addr,
    output logic signed [G_W-1:0]    rd_real,
    output logic signed [G_W-1:0]    rd_imag
);

    //--------------------------------------------------------------------------
    // 1) H buffer -- latch H_in at start, hold it stable through the compute.
    //    Both hermitian_pipeW and the read ports read from this same copy.
    //--------------------------------------------------------------------------
    logic signed [DATA_W-1:0] h_buf_real [0:MAT_DIM-1][0:MAT_DIM-1];
    logic signed [DATA_W-1:0] h_buf_imag [0:MAT_DIM-1][0:MAT_DIM-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MAT_DIM; i++)
                for (int j = 0; j < MAT_DIM; j++) begin
                    h_buf_real[i][j] <= '0;
                    h_buf_imag[i][j] <= '0;
                end
        end else if (start) begin
            h_buf_real <= h_real_in;
            h_buf_imag <= h_imag_in;
        end
    end

    //--------------------------------------------------------------------------
    // 2) Handshake registers
    //--------------------------------------------------------------------------
    logic start_d;        // start delayed 1 cycle -> H buffer is now stable
    logic run_req;        // held from start until done
    logic hh_ready;       // set when HH has settled, cleared at done
    logic herm_valid_out;
    logic mac_done;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_d  <= 1'b0;
            run_req  <= 1'b0;
            hh_ready <= 1'b0;
        end else begin
            start_d <= start;

            if (start)      run_req <= 1'b1;
            else if (done)  run_req <= 1'b0;

            if (done)               hh_ready <= 1'b0;
            else if (herm_valid_out) hh_ready <= 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // 3) Hermitian generator:  HH = H^H  (from the buffered H)
    //--------------------------------------------------------------------------
    logic signed [DATA_W-1:0] hh_mat_real [0:MAT_DIM-1][0:MAT_DIM-1];
    logic signed [DATA_W-1:0] hh_mat_imag [0:MAT_DIM-1][0:MAT_DIM-1];

    hermitian_pipeW #(
        .ROWS           (MAT_DIM),
        .COLS           (MAT_DIM),
        .WL             (DATA_W),
        .REGISTER_OUTPUT(1)
    ) u_herm (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid_in (start_d),               // pulse once H buffer is stable
        .h_real   (h_buf_real),
        .h_imag   (h_buf_imag),
        .valid_out(herm_valid_out),
        .hh_real  (hh_mat_real),
        .hh_imag  (hh_mat_imag)
    );

    //--------------------------------------------------------------------------
    // 4) Controller -- issues N_LANES elements per round
    //--------------------------------------------------------------------------
    logic [IDX_W-1:0]  c_row     [N_LANES];
    logic [IDX_W-1:0]  c_col     [N_LANES];
    logic              c_is_diag [N_LANES];
    logic              c_valid   [N_LANES];
    logic              c_mac_start;
    logic              c_wr_en   [N_LANES];
    logic [ADDR_W-1:0] c_wr_addr [N_LANES];

    gram_controller #(
        .N_LANES (N_LANES),
        .MAT_DIM (MAT_DIM),
        .IDX_W   (IDX_W),
        .ADDR_W  (ADDR_W)
    ) u_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (run_req),              // held go
        .hh_valid  (hh_ready),             // HH settled
        .mac_done  (mac_done),
        .row       (c_row),
        .col       (c_col),
        .is_diag   (c_is_diag),
        .lane_valid(c_valid),
        .mac_start (c_mac_start),
        .wr_en     (c_wr_en),
        .wr_addr   (c_wr_addr),
        .done      (done)
    );

    //--------------------------------------------------------------------------
    // 5) MAC array  <->  read ports
    //--------------------------------------------------------------------------
    logic [MEM_AW-1:0]        hh_addr [N_LANES];
    logic [MEM_AW-1:0]        h_addr  [N_LANES];
    logic signed [DATA_W-1:0] hh_real [N_LANES];
    logic signed [DATA_W-1:0] hh_imag [N_LANES];
    logic signed [DATA_W-1:0] h_real  [N_LANES];
    logic signed [DATA_W-1:0] h_imag  [N_LANES];
    logic signed [G_W-1:0]    g_real  [N_LANES];
    logic signed [G_W-1:0]    g_imag  [N_LANES];

    gram_read_ports #(
        .N_LANES (N_LANES),
        .MAT_DIM (MAT_DIM),
        .DATA_W  (DATA_W),
        .MEM_AW  (MEM_AW)
    ) u_rd (
        .hh_real_mat(hh_mat_real),
        .hh_imag_mat(hh_mat_imag),
        .h_real_mat (h_buf_real),
        .h_imag_mat (h_buf_imag),
        .hh_addr    (hh_addr),
        .h_addr     (h_addr),
        .hh_real    (hh_real),
        .hh_imag    (hh_imag),
        .h_real     (h_real),
        .h_imag     (h_imag)
    );

    mac_array #(
        .N_LANES (N_LANES),
        .DATA_W  (DATA_W),
        .MAT_DIM (MAT_DIM),
        .IDX_W   (IDX_W),
        .G_W     (G_W),
        .MEM_AW  (MEM_AW)
    ) u_array (
        .clk       (clk),
        .rst_n     (rst_n),
        .mac_start (c_mac_start),
        .row       (c_row),
        .col       (c_col),
        .is_diag   (c_is_diag),
        .lane_valid(c_valid),
        .hh_addr   (hh_addr),
        .h_addr    (h_addr),
        .hh_real   (hh_real),
        .hh_imag   (hh_imag),
        .h_real    (h_real),
        .h_imag    (h_imag),
        .g_real    (g_real),
        .g_imag    (g_imag),
        .mac_done  (mac_done)
    );

    //--------------------------------------------------------------------------
    // 6) Memory -- 8 write ports in, one read port out
    //--------------------------------------------------------------------------
    gram_mem #(
        .N_LANES  (N_LANES),
        .G_W      (G_W),
        .NUM_ELEMS(NUM_ELEMS),
        .ADDR_W   (ADDR_W)
    ) u_mem (
        .clk    (clk),
        .wr_en  (c_wr_en),
        .wr_addr(c_wr_addr),
        .g_real (g_real),
        .g_imag (g_imag),
        .rd_addr(rd_addr),
        .rd_real(rd_real),
        .rd_imag(rd_imag)
    );

endmodule