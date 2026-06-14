//==============================================================================
// tb_gram_matrix_top.sv
//------------------------------------------------------------------------------
// Testbench for gram_matrix_top.
//
//   * Loads H from H_binary.txt
//   * Runs one full compute, measures start->done cycles
//   * Reads back the 36 lower-triangle G elements and compares to G_binary.txt
//
// FILE FORMAT (as specified):
//   one binary value per line, interleaved real then imag, row-major:
//      line 1 : H_00_real      line 2 : H_00_imag
//      line 3 : H_01_real      line 4 : H_01_imag
//      ...                     (H_00, H_01, ... H_07, H_10, ...)
//   H values are DATA_W (12) bits, G values are G_W (16) bits, two's complement.
//
// ASSUMPTION for G_binary.txt: full 8x8 matrix in the SAME row-major
// interleaved order as H (G_00, G_01, ... G_77). We only check the lower
// triangle (the part the DUT computes). If your G file is lower-triangle-only
// or a different order, adjust load_g()'s loop -- the per-element dump below
// makes any mismatch easy to spot.
//==============================================================================
`timescale 1ns/1ps
module tb_gram_matrix_top;

    //--------------------------------------------------------------------------
    localparam int MAT_DIM   = 8;
    localparam int DATA_W    = 12;
    localparam int G_W       = 12;
    localparam int IDX_W     = 3;
    localparam int ADDR_W    = 6;
    localparam int NUM_ELEMS = MAT_DIM*(MAT_DIM+1)/2;     // 36
    localparam int CLK_NS    = 10;

    localparam string H_FILE = "H_binary.txt";
    localparam string G_FILE = "G_binary.txt";

    //--------------------------------------------------------------------------
    // DUT I/O
    //--------------------------------------------------------------------------
    logic                     clk, rst_n, start, done;
    logic signed [DATA_W-1:0] h_real_in [0:MAT_DIM-1][0:MAT_DIM-1];
    logic signed [DATA_W-1:0] h_imag_in [0:MAT_DIM-1][0:MAT_DIM-1];
    logic [ADDR_W-1:0]        rd_addr;
    logic signed [G_W-1:0]    rd_real, rd_imag;

    gram_matrix_top #(
        .MAT_DIM(MAT_DIM), .N_LANES(8), .DATA_W(DATA_W), .G_W(G_W),
        .IDX_W(IDX_W), .NUM_ELEMS(NUM_ELEMS), .ADDR_W(ADDR_W), .MEM_AW(2*IDX_W)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .h_real_in(h_real_in), .h_imag_in(h_imag_in),
        .done(done), .rd_addr(rd_addr), .rd_real(rd_real), .rd_imag(rd_imag)
    );

    //--------------------------------------------------------------------------
    // Clock + free-running cycle counter (for the start->done measurement)
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_NS/2) clk = ~clk;

    // Free-running cycle counter. Plain `always` (not always_ff) so the TB's
    // initial-block setup is not flagged as a second driver. Self-resets via
    // rst_n, so nothing else needs to drive it.
    int unsigned cyc_count;
    always @(posedge clk)
        if (!rst_n) cyc_count <= 0;
        else        cyc_count <= cyc_count + 1;

    //--------------------------------------------------------------------------
    // Golden G (full 8x8) read from file
    //--------------------------------------------------------------------------
    logic signed [G_W-1:0] g_gold_real [0:MAT_DIM-1][0:MAT_DIM-1];
    logic signed [G_W-1:0] g_gold_imag [0:MAT_DIM-1][0:MAT_DIM-1];

    //--------------------------------------------------------------------------
    // File loaders
    //--------------------------------------------------------------------------
    task automatic load_h(input string fname);
        int fd, code, i, j;
        fd = $fopen(fname, "r");
        if (fd == 0) $fatal(1, "TB: cannot open %s", fname);
        for (i = 0; i < MAT_DIM; i++)
            for (j = 0; j < MAT_DIM; j++) begin
                code = $fscanf(fd, "%b", h_real_in[i][j]);
                code = $fscanf(fd, "%b", h_imag_in[i][j]);
                if (code != 1) $fatal(1, "TB: %s ran out of data at H[%0d][%0d]", fname, i, j);
            end
        $fclose(fd);
        $display("TB: loaded H from %s", fname);
    endtask

    task automatic load_g(input string fname);
        int fd, code, i, j;
        fd = $fopen(fname, "r");
        if (fd == 0) $fatal(1, "TB: cannot open %s", fname);
        for (i = 0; i < MAT_DIM; i++)
            for (j = 0; j < MAT_DIM; j++) begin
                code = $fscanf(fd, "%b", g_gold_real[i][j]);
                code = $fscanf(fd, "%b", g_gold_imag[i][j]);
                if (code != 1) $fatal(1, "TB: %s ran out of data at G[%0d][%0d]", fname, i, j);
            end
        $fclose(fd);
        $display("TB: loaded golden G from %s", fname);
    endtask

    //--------------------------------------------------------------------------
    // Main stimulus
    //--------------------------------------------------------------------------
    int unsigned t_start, t_done;
    int errors, addr, i, j;

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        rd_addr = '0;

        load_h(H_FILE);
        load_g(G_FILE);

        // reset
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // kick off (H is already driven and stable)
        @(negedge clk);
        start   = 1'b1;
        t_start = cyc_count;
        @(negedge clk);
        start   = 1'b0;

        // wait for completion, measure cycles
        wait (done == 1'b1);
        t_done = cyc_count;
        $display("======================================================");
        $display("TB: start -> done = %0d cycles", t_done - t_start);
        $display("======================================================");

        // read back the lower triangle (addr 0..35 in triangular order)
        @(posedge clk);
        errors = 0;
        addr   = 0;
        for (i = 0; i < MAT_DIM; i++)
            for (j = 0; j <= i; j++) begin
                rd_addr = addr[ADDR_W-1:0];
                #1;                                   // settle combinational read
                if ((rd_real !== g_gold_real[i][j]) ||
                    (rd_imag !== g_gold_imag[i][j])) begin
                    errors++;
                    $display("MISMATCH G[%0d][%0d] addr=%0d :",  i, j, addr);
                    $display("    dut  re=%0d (%b)  im=%0d (%b)",
                             rd_real, rd_real, rd_imag, rd_imag);
                    $display("    gold re=%0d (%b)  im=%0d (%b)",
                             g_gold_real[i][j], g_gold_real[i][j],
                             g_gold_imag[i][j], g_gold_imag[i][j]);
                end else begin
                    $display("ok  G[%0d][%0d] a=%0d : re=%0d (%b)  im=%0d (%b)",
                             i, j, addr, rd_real, rd_real, rd_imag, rd_imag);
                end
                addr++;
            end

        $display("======================================================");
        if (errors == 0)
            $display("TB: PASS -- all %0d lower-triangle elements match", NUM_ELEMS);
        else
            $display("TB: FAIL -- %0d mismatch(es)", errors);
        $display("======================================================");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Watchdog
    //--------------------------------------------------------------------------
    initial begin
        #100000;
        $display("TB: TIMEOUT -- done never asserted");
        $finish;
    end

endmodule