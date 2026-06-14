/*
 * FFT_engine.sv
 *
 * Copyright (C) 2020 ETH Zurich and University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

/*
 * Authors:  Mohamed Abdelhay <abdelhaymohamed21@gmail.com>
 */

import FFT_package::*;
import hwpe_stream_package::*;
import hci_package::*;

module FFT_engine #(
  parameter int unsigned BW_ALIGNED = 256,
  parameter int unsigned DATA_WIDTH = 12
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // input data stream + handshake
  hwpe_stream_intf_stream.sink   data_in,
  // output data stream + handshake
  hwpe_stream_intf_stream.source data_out,
  // control channel
  input  ctrl_engine_t           ctrl_i,
  output flags_engine_t          flags_o
);

  logic  [BW_ALIGNED-1:0]            fifo_data_i, sample_data_in;
  logic  [BW_ALIGNED-1:0]            fifo_data_o, sample_data_out;
  logic  [31:0]                      in32;
  logic  [31:0]                      out32;  
  logic                              empty_data_in,  full_data_in,  pop_data_in;
  logic                              empty_data_out, full_data_out, push_data_out;
  logic                              valid_in;
  logic                              valid_out;
  logic                              valid_in_start, valid_in_finish;
  logic  [$clog2(BW_ALIGNED/32)-1:0] count_to_pop_data_in, count_to_disable_valid;
  logic  [$clog2(BW_ALIGNED/32)-1:0] count_to_push_data_out;



  fft8_dif #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) i_fft (
    .clk         ( clk_i && !full_data_out     ),
    .rst_n       ( rst_ni | !ctrl_i.clear      ),
    .valid_in    ( valid_in & ctrl_i.enable    ),
    .in_r        ( in32[DATA_WIDTH -1:0]       ),
    .in_i        ( in32[DATA_WIDTH+16 -1:16]   ),
    .out_r       ( out32[DATA_WIDTH-1:0]       ),
    .out_i       ( out32[DATA_WIDTH+16 -1:16]  ),
    .valid_out   ( valid_out                   ),
    .frame_done  ( flags_o.frame_done          )
  );


  // fifo data_in
  fifo_v3 #(
    .DATA_WIDTH (BW_ALIGNED),
    .DEPTH      (    8     )
  ) fifo_pre_data_in (
    .clk_i      ( clk_i                            ),
    .rst_ni     ( rst_ni                           ),
    .flush_i    ( !ctrl_i.enable                   ),
    .testmode_i ( test_mode_i                      ),
    .full_o     ( full_data_in                     ),
    .empty_o    ( empty_data_in                    ),
    .usage_o    (                                  ),
    .data_i     ( data_in.data                     ),
    .push_i     ( data_in.ready && data_in.valid   ),
    .data_o     ( fifo_data_o                      ),
    .pop_i      ( pop_data_in                      )
  );
  
  // fifo data_out
  fifo_v3 #(
    .DATA_WIDTH (BW_ALIGNED),
    .DEPTH      (    8     )
  ) fifo_post_data_out (
    .clk_i      ( clk_i                            ),
    .rst_ni     ( rst_ni                           ),
    .flush_i    ( !ctrl_i.enable                   ),
    .testmode_i ( test_mode_i                      ),
    .full_o     ( full_data_out                    ),
    .empty_o    ( empty_data_out                   ),
    .usage_o    (                                  ),
    .data_i     ( sample_data_out                  ),
    .push_i     ( push_data_out                    ),
    .data_o     ( data_out.data                    ),
    .pop_i      ( data_out.ready && data_out.valid )
  );



  // counter of count_to_pop_data_in
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (!rst_ni) begin
      count_to_pop_data_in <= 0;
    end
    else if (!empty_data_in)
    begin
      count_to_pop_data_in <= count_to_pop_data_in+1;
    end
  end

  // counter of count_to_push_data_out
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (!rst_ni) begin
      count_to_push_data_out <= 0;
    end
    else if (valid_out)
    begin
      count_to_push_data_out <= count_to_push_data_out+1;
    end
  end




  // loop to take in32 from fifo
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (!rst_ni) begin
      pop_data_in    <= 0;
      sample_data_in <= 0;
      in32           <= 0;
    end
    else begin
      if(count_to_pop_data_in == BW_ALIGNED/32 - 1) 
        pop_data_in <= 1;
      else
        pop_data_in <= 0;

      if(count_to_pop_data_in==0)
      begin
        sample_data_in <= fifo_data_o;
        in32           <= fifo_data_o;
      end
      else
        sample_data_in <= sample_data_in;

      if( (count_to_pop_data_in!=0) && (valid_in == 1) )
      begin
        in32           <= (sample_data_in >> 32);
        sample_data_in <= (sample_data_in >> 32);
      end
    end
  end


  // loop to put out32 in fifo
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (!rst_ni) begin
      fifo_data_i     <= 0;
      push_data_out   <= 0;
      sample_data_out <= 0;
      out32           <= 0;
    end
    else if(valid_out == 1)
    begin
      sample_data_out <= (sample_data_out >> 32) | (out32 << (BW_ALIGNED-32));
      
      if(count_to_push_data_out == BW_ALIGNED/32 - 1) begin
        push_data_out  <= 1;
        fifo_data_i    <= sample_data_out;
      end
      else begin
        push_data_out <= 0;
        fifo_data_i   <= fifo_data_i;
      end
    end
    else begin
      push_data_out <= 0;
      fifo_data_i   <= fifo_data_i;
    end
  end




  // condition to valid_in <= 1;
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (!rst_ni) begin
      valid_in_start <= 0;
      valid_in       <= 0;
    end

    else if((pop_data_in == 1 || valid_in_start == 1) && !valid_in_finish)
    begin
      valid_in_start <= 1;
      valid_in       <= 1;
    end
  end

  // condition to valid_in <= 0;
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (!rst_ni) begin
      count_to_disable_valid <= 0;
      valid_in_finish        <= 0;
    end
    else if (empty_data_in && valid_in)
    begin
      count_to_disable_valid <= count_to_disable_valid+1;
      if(count_to_disable_valid == BW_ALIGNED/32 - 1) 
      begin
       valid_in               <= 0;
       count_to_disable_valid <= 0;
       valid_in_finish        <= 1;
      end
    end
  end

  // reset all components when enable is not active
  always_ff @(posedge clk_i)
  begin
    if (!ctrl_i.enable)
    begin
      count_to_pop_data_in   <= 0;
      count_to_disable_valid <= 0;
      count_to_push_data_out <= 0;
      sample_data_out        <= 0;
      sample_data_in         <= 0;
      fifo_data_i            <= 0;
      fifo_data_o            <= 0;
      valid_in_start         <= 0;
      valid_in_finish        <= 0;
    end
  end



  assign data_out.valid    = !empty_data_out;
  assign flags_o.valid_out = data_out.valid;
  assign data_in.ready     = full_data_in ? 1'b0 : 1'b1;
  assign data_out.strb     = '1;
endmodule

