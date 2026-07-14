/*
Scoreboard receives the observed transactions from the monitor.
It calculates the expected result using a golden model and stores it in an associative array.
It stores the actual DUT output in a queue.
Provides methods for the Environment to trigger batch validation and clear storage between phases.
*/
package scoreboard_pkg;
  import global_counters::*;
  import transaction_pkg::*;

  class scoreboard;
    mailbox #(transaction) mbx_mon2scoreboard;
    transaction trans;
    event scoreboard_done;

    // ======================================================
    // Data Structures from the procedural testbench
    // ======================================================
    // Associative array for golden model outputs (index is stimulus number)
    logic signed [OUT_WIDTH - 1:0] expected_results[int];
    // Queue for actual DUT outputs
    logic signed [OUT_WIDTH - 1:0] dut_results[$];

    // Internal counter to track the current stimulus index for the batch
    int trans_index;

    function new(mailbox #(transaction) mbx_mon2scoreboard);
      this.mbx_mon2scoreboard = mbx_mon2scoreboard;
      this.trans_index = 0;
    endfunction 

    // Main run task runs continuously to catch monitor data
    task run();
      forever begin
        mbx_mon2scoreboard.get(trans);
        $display("[SCOREBOARD] : DATA RECEIVED FROM MONITOR (Index: %0d)", trans_index);
        
        // 1. Calculate and store the expected result
        golden_model(trans);
        
        // 2. Store the actual result
        collect_output_data(trans.data_out);
        
        // Notify Generator to proceed
        ->scoreboard_done; 
        
        // Increment index for the next transaction in the batch
        trans_index++;
        $display("--------------------------------------------------------");
      end
    endtask

    // ==============================================================
    // Maps to: golden_model (Associative Array Storage)
    // ==============================================================
    function void golden_model(transaction trans);
      logic signed [7:0] golden_out;
      
      case (trans.op_sel)
        2'b00: golden_out = trans.data_in + $signed(8'd1); // Increment
        2'b01: golden_out = trans.data_in - $signed(8'd1); // Decrement
        2'b10: golden_out = ~trans.data_in;                // Bitwise NOT
        2'b11: golden_out = trans.data_in << 1;            // Left shift by 1
        default: golden_out = trans.data_in;
      endcase

      // Store in associative array
      expected_results[trans_index] = golden_out;
      $display("[SCOREBOARD] : Golden Expected = %0d stored at index %0d", golden_out, trans_index);
    endfunction

    // ==============================================================
    // Maps to: collect_output_data (Queue Storage)
    // ==============================================================
    function void collect_output_data(logic signed [7:0] dut_out);
      dut_results.push_back(dut_out);
      $display("[SCOREBOARD] : DUT Actual = %0d pushed to queue", dut_out);
    endfunction

    // ==============================================================
    // Maps to: check_results (Batch Validation)
    // ==============================================================
    function void check_batch_results();
      $display("\n[SCOREBOARD] : --- Checking Batch Results ---");
      
      if (expected_results.size() != dut_results.size()) begin
        $display("[SCOREBOARD] : ERROR - Array size mismatch. Expected: %0d, Actual: %0d", expected_results.size(), dut_results.size());
      end

      for (int i = 0; i < dut_results.size(); i++) begin
        if (expected_results[i] === dut_results[i]) begin
          $display("[SCOREBOARD] : Stimulus %0d - PASS: Expected = %0d, Actual = %0d", i, expected_results[i], dut_results[i]);
        end else begin
          error_count++; // Update global error counter
          $display("[SCOREBOARD] : Stimulus %0d - FAIL: Expected = %0d, Actual = %0d", i, expected_results[i], dut_results[i]);
        end
      end
      $display("[SCOREBOARD] : Batch check complete. Current Total Errors = %0d\n", error_count);
    endfunction

    // ==============================================================
    // Helper to clear storage between environment phases
    // ==============================================================
    function void clear_storage();
      expected_results.delete();
      dut_results.delete();
      trans_index = 0;
      $display("[SCOREBOARD] : Content of output queue and expected associative array cleared. Ready for next phase.\n");
    endfunction

  endclass
endpackage