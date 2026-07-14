/*
Top level wrapper.
- Creates an instance of the physical interface.
- Instantiates the DUT and correctly maps the interface using the DUT modport.
- Creates the environment and passes the correct TB and MON modports.
- Triggers waveform dumping.
*/
module tb_top ();
  // Import all necessary packages
  import transaction_pkg::*;
  import generator_pkg::*;
  import driver_pkg::*;
  import monitor_pkg::*;
  import scoreboard_pkg::*;
  import enviroment_pkg::*;
  import global_counters::*;

  // 1. Instantiate the physical interface
  interf tb_intf();

  // 2. Instantiate the DUT
  // CRITICAL FIX: Using named port connection to map the interface bundle 
  // directly to the DUT, resolving the compilation error.
  multi_op_processor dut (
    .intf(tb_intf.DUT) 
  );

  // 3. Declare the environment handle
  enviroment env;

  initial begin
    // 4. Initialize global tracking variables
    error_count = 0;
    total_stimuli = 0;

    // 5. Construct the environment, passing in the restrictive virtual interfaces
    env = new(tb_intf.TB, tb_intf.MON);
    
    // 6. Start the environment phase orchestration
    env.run(); 
  end

  // 7. Waveform dumping block
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end

endmodule