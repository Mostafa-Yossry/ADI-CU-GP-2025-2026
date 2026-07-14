module multi_op_processor (interf.DUT intf);
  always @(*)
  begin
    case (intf.op_sel)
      2'b00:
        intf.data_out = intf.data_in + 1;       // Increment
      2'b01:
        intf.data_out = intf.data_in - 1;       // Decrement
      2'b10:
        intf.data_out = ~intf.data_in;          // Bitwise NOT
      2'b11:
        intf.data_out = intf.data_in << 1;      // Left shift by 1
      default:
        intf.data_out = intf.data_in;
    endcase
  end

endmodule
