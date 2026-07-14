`timescale 1ns/1ps
module multi_op_processor_tb ();
  // ======================================================
  // Signals Declaration
  // ======================================================
  parameter IN_WIDTH    = 8;
  parameter OUT_WIDTH   = 8;
  parameter OPERAND_SEL = 2;

  typedef struct {
            logic signed  [IN_WIDTH    - 1:0]  data_in;
            logic         [OPERAND_SEL - 1:0]   op_sel;
          } stimulus_packet;

  // DUT Signals (Logic as it is the default data type)
  logic signed  [IN_WIDTH    - 1:0]  data_in;
  logic         [OPERAND_SEL - 1:0]   op_sel;
  logic signed  [OUT_WIDTH   - 1:0] data_out;

  // stimulus --> Signed/Unsigned, We won't be driving by x or z --> 2-state is enough
  // 8-bit input. Therefore, we use byte --> byte stimulus_d[];
  // I chose to use a struct to hold the stimulus data, which includes both data_in and op_sel
  stimulus_packet stimulus_d[];

  // Output is 8 bits , Can be signed or unsigned , we are testing the dut which
  // can produce x or z if it is multi-driven or undriven respectively --> need 4-state data type
  // Therefore, we use signed Logic
  logic signed [OUT_WIDTH - 1:0] dut_results[$];

  // Golden model results are of the same type as the output, the index type is int
  // the index represents the stimulus number
  logic signed [OUT_WIDTH - 1:0] expected_results[int];

  // --------- Counters ---------//
  // Error counter
  int error_count;
  // Stimulus number counter
  int stim_num;

  // ======================================================
  // DUT Instantiation
  // ======================================================
  multi_op_processor dut (
                       .data_in(data_in),
                       .op_sel(op_sel),
                       .data_out(data_out)
                     );

  // ======================================================
  // Drive Stimulus
  // ======================================================
  initial
  begin
    configure_stim_storage(100);   // Configure the stimulus storage to hold 100 stimuli
    generate_stimulus(stimulus_d); // Generate the stimulus
    drive_stim();                  // Drive the stimulus to the DUT
    // Check the results
    check_results(expected_results, dut_results);

    configure_stim_storage(200);   // Configure the stimulus storage to hold 200 stimuli
    generate_stimulus(stimulus_d); 
    drive_stim(); 
    // Check the results
    check_results(expected_results, dut_results);

    reconfigure_stim(stimulus_d); // Reconfigure the stimulus order
    drive_stim(); 
    check_results(expected_results, dut_results);

    $display("\n");
    $display("[TB]: ================= Tests Completed ================= ");
    $display("[TB]: All Stimuli Processed. Total number of errors = %0d", error_count);
    $display("\n");
    #10ns;
    $finish;
  end
  // ======================================================
  // Tasks and Functions
  // ======================================================
  function void configure_stim_storage (int size); // initialization
    // Re-configure dynamic array size
    stimulus_d = new[size];
    // Clear Contet of data queue and expected data associative array
    dut_results.delete();
    expected_results.delete();
    $display("[configure_stim_storage]: Contenet of output queue and golden model Associative array are cleared. Ready for new stimulus");
    stim_num = 0;
    $display("[configure_stim_storage]: Stimulus number counter is reset to 0\n");
  endfunction

  function automatic void generate_stimulus (ref stimulus_packet stimulus_d[]);
    for (int i = 0; i < $size(stimulus_d) ; i++ )
    begin
      // Store randomized stimulus in the dynamic array
      stimulus_d[i].data_in = $random();
      stimulus_d[i].op_sel = $urandom();
    end
    $display("[generate_stimulus]: Stimulus Generated \n");
  endfunction

  task drive_stim();
    begin
      foreach (stimulus_d[i])
      begin
        op_sel  = stimulus_d[i].op_sel;
        data_in = stimulus_d[i].data_in;

        $display("[drive_stim]: DUT is derived with %0d and op_sel = %0d",
                 data_in, op_sel);

        #1ns; // dummy wait time for DUT to produce output

        golden_model(expected_results);
        collect_output_data(data_out);

        stim_num++;
      end

      $display("\n");
    end
  endtask

  function automatic void golden_model(ref logic signed [OUT_WIDTH - 1:0] expected_results[int]);
    logic signed [OUT_WIDTH - 1:0] golden_out;
    // Golden model
    case (op_sel)
      2'b00:
        golden_out = data_in + $signed(8'd1);       // Increment
      2'b01:
        golden_out = data_in - $signed(8'd1);       // Decrement
      2'b10:
        golden_out = ~data_in;          // Bitwise NOT
      2'b11:
        golden_out = data_in << 1;      // Left shift by 1
      default:
        golden_out = data_in;
    endcase
    // Store Golden Result in the Associative array
    expected_results[stim_num] = golden_out;

    $display("[golden_model]: data_in = %0d, the expected result = %0d is stored in the associative array at Index (Stimulus number) = %0d",
             data_in, golden_out, stim_num);

    $display("[golden_model]: expected_results[%0d] = %0d",
             stim_num, expected_results[stim_num]);

  endfunction

  function void collect_output_data(logic signed [OUT_WIDTH - 1:0] dut_out);
    // Store the dut output inside the dut results queue
    dut_results.push_back(dut_out);
    $display("[collect_output_data]: DUT result: %0d is stored inside the dut results queue.",
             dut_results[$]);
    $display("\n");
  endfunction


  function automatic void check_results(
      const ref  logic signed [OUT_WIDTH - 1:0] expected_results[int],
      const ref  logic signed [OUT_WIDTH - 1:0] dut_results[$]
    );
    $display("[check_results]: Checking the results of the DUT against the expected results from the golden model");
    $display("[check_results]: Total number of Stimuli = %0d", $size(dut_results));
    $display("dut_results = %p", dut_results);
    $display("expected_results = %p", expected_results);
    $display("\n");
    for (int i = 0; i < $size(dut_results); i++)
    begin
      if (expected_results[i] == dut_results[i])
      begin
        $display("[check_results]: Stimulus %0d - PASS: Expected = %0d, Actual = %0d", i, expected_results[i], dut_results[i]);
      end
      else
      begin
        error_count++;
        $display("[check_results]: Stimulus %0d - FAIL: Expected = %0d, Actual = %0d", i, expected_results[i], dut_results[i]);
      end
    end
    $display("\n");
    $display("[check_results]: All Stimuli Processed. Total number of errors = %0d", error_count);
  endfunction

  function automatic void reconfigure_stim(ref stimulus_packet stimulus_d[]);
    // Shuufle the stimulus dynamic array to reconfigure the order of the stimulus
    stimulus_d.shuffle();
    $display("[reconfigure_stim]: Stimulus reconfigured in random order\n");
    dut_results.delete();
    expected_results.delete();
    $display("[reconfigure_stim]: Contenet of output queue and golden model Associative array are cleared to store the new results of the reconfigured stimulus\n");
    // Reset stimulus number counter
    stim_num = 0;
  endfunction

endmodule
