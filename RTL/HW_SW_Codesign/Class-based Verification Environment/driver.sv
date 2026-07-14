/*
Driver drives the dut with the generated stimulus,
needs virtual interface with modport TB to wiggle the DUT pins,
needs mailbox to receive the transaction from the generator,
an event to trigger the monitor in order to start reading the DUT outputs
*/
package driver_pkg;
import generator_pkg::  *;
import transaction_pkg::  *;
  class driver;
    virtual interf.TB drv_intf;
    mailbox #(transaction) mbx_from_gen;
    transaction trans;
    event monitor_trigger;

    function new(mailbox #(transaction) mbx_from_gen);
      this.mbx_from_gen = mbx_from_gen;
    endfunction //new()

    task run();
      forever //
      begin
        mbx_from_gen.get(trans);// Get transaction from mailbox
        $display("[DRV] : DATA RECEIVED FROM GENERATOR");
        drv_intf.data_in = trans.data_in;// Assign transaction data to driver interface
        drv_intf.op_sel = trans.op_sel;
        $display("[DRV] : DATA ASSIGNED TO DRIVER INTERFACE data_in: %0d, op_sel: %0d",
                 drv_intf.data_in, drv_intf.op_sel);
        $display("[DRV] : DATA SENT TO DUT");
        //$stop;
        trans.display();
        #1ns; // dut produce output
        ->monitor_trigger;
      end
    endtask
  endclass
endpackage