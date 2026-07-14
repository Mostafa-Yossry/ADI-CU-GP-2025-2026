/*
baseline for transactions,
all inputs and outputs are declared here and inputs are randomized,
constraints are written here,
Deep copy method in order to send copies of a single object (shared object history can use randc)
*/
package transaction_pkg;
  class transaction;
    rand logic [7:0] data_in;
    rand logic [1:0] op_sel;
    logic [7:0] data_out;


    function void display();
      $display("data_in: %0d, op_sel: %0b, data_out: %0d", data_in, op_sel, data_out);
    endfunction

    function transaction copy();
    copy = new();
      copy.data_in = this.data_in;
      copy.op_sel = this.op_sel;
      copy.data_out = this.data_out;
    endfunction

    function new();

    endfunction
  endclass
endpackage