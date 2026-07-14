/*
Environment builds and connects the verification environment components.
It orchestrates the simulation phases:
  - Starts the Driver, Monitor, and Scoreboard background processes.
  - Commands the Generator to create a batch (e.g., 100 transactions) and drive it.
  - Triggers the Scoreboard to check the batch results.
  - Clears storage and moves to the next phase (e.g., 200 transactions, then shuffled).
*/
package enviroment_pkg;
  import generator_pkg::*;
  import transaction_pkg::*;
  import driver_pkg::*;
  import monitor_pkg::*;
  import scoreboard_pkg::*;
  import global_counters::*;

  class enviroment;
    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard sb;
    
    mailbox #(transaction) mbx_gentodrv;
    mailbox #(transaction) mbx_montosb;
    
    virtual interf env_intf; 
    
    event next_stimulus;
    event monitor_trigger;

    function new(virtual interf.TB tb_intf, virtual interf.MON mon_intf);
      // 1. Initialize interfaces and mailboxes
      env_intf = tb_intf;
      mbx_gentodrv = new();
      mbx_montosb  = new();
      
      // 2. Instantiate components
      gen = new(mbx_gentodrv);
      drv = new(mbx_gentodrv);
      mon = new(mbx_montosb);
      sb  = new(mbx_montosb);
      
      // 3. Connect virtual interfaces
      drv.drv_intf = tb_intf;
      mon.mon_intf = mon_intf;
      
      // 4. Connect handshaking events
      gen.scoreboard_done = next_stimulus;
      sb.scoreboard_done  = next_stimulus;
      
      drv.monitor_trigger = monitor_trigger;
      mon.monitor_trigger = monitor_trigger;
    endfunction

    task pre_test();
      $display("[ENV] : Pre-test setup");
      // Add reset logic here if your DUT eventually requires one
      $display("[ENV] : DUT reset completed");
    endtask

task test();
      $display("[ENV] : Starting test phases");
      
      // Start the reactive components in the background
      fork
        drv.run();
        mon.run();
        sb.run();
      join_none
      
      // ==========================================
      // PHASE 1: Drive 100 Transactions
      // ==========================================
      $display("\n==========================================");
      $display("[ENV] : PHASE 1 - 100 Transactions");
      $display("==========================================");
      gen.configure_and_generate(100);
      
      gen.run(); // This blocks the thread until all 100 are sent
      
      // @(gen.stimulus_done); <-- REMOVE THIS LINE
      
      sb.check_batch_results(); // This will now run immediately after gen.run() finishes

      // ==========================================
      // PHASE 2: Drive 200 Transactions
      // ==========================================
      $display("\n==========================================");
      $display("[ENV] : PHASE 2 - 200 Transactions");
      $display("==========================================");
      sb.clear_storage(); 
      gen.configure_and_generate(200);
      
      gen.run();
      
      // @(gen.stimulus_done); <-- REMOVE THIS LINE
      
      sb.check_batch_results();

      // ==========================================
      // PHASE 3: Shuffle and Drive the 200 again
      // ==========================================
      $display("\n==========================================");
      $display("[ENV] : PHASE 3 - Shuffled Transactions");
      $display("==========================================");
      sb.clear_storage();
      gen.shuffle_stimulus();
      
      gen.run();
      
      // @(gen.stimulus_done); <-- REMOVE THIS LINE
      
      sb.check_batch_results();
      
    endtask

    task post_test();
      $display("\n[ENV] : Post-test cleanup");
      $display("[ENV] : All phases complete. Total Stimuli = %0d, Total Errors = %0d", total_stimuli, error_count);
      $finish; // End the simulation
    endtask
    
    // Main run task
    task run();
      pre_test();
      test();
      post_test();
    endtask

  endclass
endpackage