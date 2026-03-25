`timescale 1ns / 1ps

module tb_fft4096;

    // --------------------------------------------------------
    // 1. Simulation Parameters
    // --------------------------------------------------------
    parameter DATA_WIDTH    = 12;
    parameter N             = 4096;
    parameter NUM_FRAMES    = 100;          // MUST MATCH nSeeds in gen_testdata_4096.m
    localparam TOTAL_SAMPLES = N * NUM_FRAMES;
    localparam CLK_PERIOD   = 10;

    // --------------------------------------------------------
    // 2. Signals
    // --------------------------------------------------------
    reg clk, rst_n, valid_in;
    reg signed [DATA_WIDTH-1:0] in_r, in_i;

    wire signed [DATA_WIDTH-1:0] out_r, out_i;
    wire valid_out, frame_done;
    wire [11:0] out_index;

    // --------------------------------------------------------
    // 3. Memory Arrays
    //    Each complex sample = 2 words (real, imag), interleaved
    // --------------------------------------------------------
    reg [DATA_WIDTH-1:0] input_mem  [0:(TOTAL_SAMPLES*2)-1];
    reg [DATA_WIDTH-1:0] golden_mem [0:(TOTAL_SAMPLES*2)-1];

    initial begin
        $readmemb("input_data_ordered.txt",  input_mem);
        $readmemb("output_data_ordered.txt", golden_mem);

        $display("------------------------------------------------");
        $display("DATA LOAD CHECK (4096-pt FFT):");
        $display("Input[0]  (Real): %b", input_mem[0]);
        $display("Input[1]  (Imag): %b", input_mem[1]);
        $display("Golden[0] (Real): %b", golden_mem[0]);
        $display("Golden[1] (Imag): %b", golden_mem[1]);
        $display("------------------------------------------------");
    end

    // --------------------------------------------------------
    // 4. DUT
    // --------------------------------------------------------
    fft4096_dif #(
        .DATA_WIDTH(DATA_WIDTH),
        .ORDERED_OUTPUT(1)         // <-- FIX 1: Forces the ordered RAM wrapper to be generated
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .in_r(in_r),
        .in_i(in_i),
        .out_r(out_r),
        .out_i(out_i),
        .valid_out(valid_out),
        .frame_done(frame_done),
        .out_index(out_index)
    );

    // --------------------------------------------------------
    // 5. Clock
    // --------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --------------------------------------------------------
    // 6. Driver
    // --------------------------------------------------------
    integer f, k, in_ptr;

    initial begin
        rst_n    = 0;
        valid_in = 0;
        in_r     = 0;
        in_i     = 0;
        in_ptr   = 0;

        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        $display("Starting Simulation: %0d Frames of 4096-point FFT...", NUM_FRAMES);

        // --- Feed the Valid Data ---
        for (f = 0; f < NUM_FRAMES; f = f + 1) begin
            for (k = 0; k < N; k = k + 1) begin
                @(negedge clk);
                valid_in = 1;
                in_r = input_mem[in_ptr];
                in_i = input_mem[in_ptr + 1];
                in_ptr = in_ptr + 2;
            end
        end

        // --- FIX 2: THE FLUSH ---
        $display("Main data driven. Flushing the pipeline to push out trapped data...");
        
        // Feed dummy zeros for 2*N cycles to clear the SDF stages AND the RAM buffer
        for (k = 0; k < (2 * N); k = k + 1) begin
            @(negedge clk);
            valid_in = 1;  // Must stay high!
            in_r = 0;      // Dummy data
            in_i = 0;      // Dummy data
        end

        // --- Shut down the driver ---
        @(negedge clk);
        valid_in = 0;

        $display("Driver Finished. Waiting for pipeline to drain completely...");
    end

    // --------------------------------------------------------
    // 7. Checker
    // --------------------------------------------------------
    integer out_cnt = 0;
    integer err_cnt = 0;
    integer gold_ptr = 0;

    reg signed [DATA_WIDTH-1:0] exp_r, exp_i;

    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            exp_r = golden_mem[gold_ptr];
            exp_i = golden_mem[gold_ptr + 1];

            if ((out_r !== exp_r) || (out_i !== exp_i)) begin
                err_cnt = err_cnt + 1;
                if (err_cnt <= 20) begin
                    $display("[FAIL] Time: %t | Frame: %0d | Sample: %0d",
                             $time, (out_cnt / N), (out_cnt % N));
                    $display("    Expected: %h + j%h", exp_r, exp_i);
                    $display("    Received: %h + j%h", out_r, out_i);
                end
            end

            gold_ptr = gold_ptr + 2;
            out_cnt  = out_cnt  + 1;

            if (out_cnt == TOTAL_SAMPLES) begin
                $display("\n============================================");
                $display("             SIMULATION RESULTS             ");
                $display("============================================");
                $display(" Total Frames Checked : %0d", NUM_FRAMES);
                $display(" Total Samples        : %0d", TOTAL_SAMPLES);
                $display(" Total Errors         : %0d", err_cnt);
                $display("--------------------------------------------");
                if (err_cnt == 0)
                    $display(" STATUS: [PASS] Perfect Match with MATLAB.");
                else
                    $display(" STATUS: [FAIL] Mismatches detected.");
                $display("============================================\n");
                $finish;
            end
        end
    end

    // --------------------------------------------------------
    // 8. Watchdog 
    // --------------------------------------------------------
    initial begin
        #(CLK_PERIOD * N * (NUM_FRAMES + 4) * 4);
        $display("[FATAL] Watchdog expired! %0d/%0d samples processed.", out_cnt, TOTAL_SAMPLES);
        $finish;
    end

endmodule