/*
Generator generates the stimulus.
It now utilizes a dynamic array to store batches of transactions,
allowing for pre-generation, dynamic sizing, and shuffling before driving.
It waits on the scoreboard event before sending the next transaction in the array.
*/
package generator_pkg;
  import global_counters::*;
  import transaction_pkg::*;

  class generator;
    mailbox #(transaction) mbx_gen2drv;
    event scoreboard_done;
    event stimulus_done;

    // Dynamic array to hold our generated stimulus batch
    transaction trans_array[];

    function new(mailbox #(transaction) mbx_gen2drv);
      this.mbx_gen2drv = mbx_gen2drv;
    endfunction

    // ==============================================================
    // Maps to: configure_stim_storage & generate_stimulus
    // ==============================================================
    function void configure_and_generate(int size);
      $display("[GEN] : Configuring stimulus storage for %0d transactions", size);
      trans_array = new[size]; // Re-configure dynamic array size
      
      foreach(trans_array[i]) begin
        trans_array[i] = new();
        // Randomize the inputs (data_in, op_sel) based on constraints in transaction_pkg
        if(!trans_array[i].randomize()) begin
          $display("[GEN] : Randomization failed at index %0d", i);
        end
      end
      $display("[GEN] : Stimulus batch generated successfully.");
    endfunction

    // ==============================================================
    // Maps to: reconfigure_stim
    // ==============================================================
    function void shuffle_stimulus();
      trans_array.shuffle(); // Shuffle the existing transactions
      $display("[GEN] : Stimulus array shuffled into a random order.");
    endfunction

    // ==============================================================
    // Main run task: drives the currently configured dynamic array
    // ==============================================================
    task run();
      $display("[GEN] : Starting to drive stimulus batch of size %0d", trans_array.size());
      #1ns; // brief wait for other threads to initialize
      
      foreach(trans_array[i]) begin
        // Put a deep copy of the transaction into the mailbox
        mbx_gen2drv.put(trans_array[i].copy());
        
        $display("-------------------------------------------------");
        $display("[GEN] : DATA SENT TO DRIVER (Stimulus Index: %0d)", i);
        trans_array[i].display();
        
        // Wait for the scoreboard to finish evaluating the current transaction
        @(scoreboard_done); 
        
        total_stimuli++; // Update global stimuli counter
      end
      
      $display("[GEN] : All transactions in current batch sent.");
      ->stimulus_done; // Trigger environment that the batch is complete
    endtask
    
  endclass
endpackage