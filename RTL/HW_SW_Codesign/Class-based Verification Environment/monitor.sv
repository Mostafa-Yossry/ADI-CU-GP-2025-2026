/*
Monitor monitors the DUT signals,
send the DUT outputs to the scoreboard via mailbox to be checked against golden model,
needs virtual interface of modport MON to observe the signals,
sends the observed transaction to the scoreboard,
waits on the driver trigger to start observing the interface
*/
package monitor_pkg;
import generator_pkg::  *;
import transaction_pkg::  *;
import driver_pkg::  *;
  class monitor;
    transaction trans;
    virtual interf.MON mon_intf;
    mailbox #(transaction) mbx_mon2scoreboard;
    event monitor_trigger;

    function new(mailbox #(transaction) mbx_mon2scoreboard);
      this.mbx_mon2scoreboard = mbx_mon2scoreboard;
    endfunction //new()
    task run();
      forever
      begin
        @(monitor_trigger);
        trans = new();
        trans.data_in= mon_intf.data_in; // Assign transaction data from monitor interface
        trans.op_sel = mon_intf.op_sel;
        trans.data_out = mon_intf.data_out;
        $display("[MON] : DATA RECEIVED FROM DUT");
        $display("[MON] : Interface Trigger");
        trans.display();
        mbx_mon2scoreboard.put(trans); // Put transaction into mailbox to send to scoreboard
      end
    endtask
  endclass //className
endpackage