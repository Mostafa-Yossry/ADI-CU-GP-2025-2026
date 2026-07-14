interface interf;
  logic [7:0] data_in;
  logic [1:0] op_sel;
  logic  [7:0] data_out;

  modport DUT (
  input data_in,
  input op_sel,
  output data_out
  );

  modport TB (
  input data_out,
  output data_in,
  output op_sel
  );

  modport MON (
  input data_in,
  input op_sel,
  input data_out
  );

endinterface //interfacename
