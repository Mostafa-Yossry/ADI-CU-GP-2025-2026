/*
 * Copyright (C) 2020 ETH Zurich and University of Bologna
 *
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

import hwpe_ctrl_package::*;
import hci_package::*;
import FFT_package::*;

module FFT_top #(
  parameter int unsigned ID        = 10,
  parameter int unsigned BW        = 64,
  parameter int unsigned N_CORES   = 8,
  parameter int unsigned N_CONTEXT = 2
) (
  // global signals
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    test_mode_i,
  // events
  output logic [N_CORES-1:0][1:0] evt_o,
  // tcdm master ports
  hci_core_intf.master            tcdm,
  // periph slave port
  hwpe_ctrl_intf_periph.slave     periph
);

  // We "sacrifice" 1 word of memory interface bandwidth in order to support
  // realignment at a byte boundary.
  localparam BW_ALIGNED = BW-32;

  logic            clear;
  ctrl_streamer_t  streamer_ctrl;
  flags_streamer_t streamer_flags;
  ctrl_engine_t    engine_ctrl;
  flags_engine_t   engine_flags;


  // Data in and data out internal HWPE-Streams. Notice that the data width
  // is set to 256 bits by default, 32 bits less than the default external
  // bandwidth. The additional 32 bits of memory bandwidth are used to 
  // support access to non-word-aligned data packets.
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(BW_ALIGNED)
  ) data_in  (
    .clk(clk_i)
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH(BW_ALIGNED)
  ) data_out (
    .clk(clk_i)
  );


  FFT_ctrl #(
    .N_CORES  ( N_CORES   ),
    .N_CONTEXT( N_CONTEXT ),
    .ID       ( ID        )
  ) i_ctrl (
    .clk_i            ( clk_i          ),
    .rst_ni           ( rst_ni         ),
    .test_mode_i      ( test_mode_i    ),
    .evt_o            ( evt_o          ),
    .ctrl_streamer_o  ( streamer_ctrl  ),
    .flags_streamer_i ( streamer_flags ),
    .ctrl_engine_o    ( engine_ctrl    ),
    .flags_engine_i   ( engine_flags   ),
    .periph           ( periph         )
  );


  FFT_streamer #(
    .BW              ( BW ),
    .TCDM_FIFO_DEPTH ( 0  )
  ) i_streamer (
    .clk_i      ( clk_i          ),
    .rst_ni     ( rst_ni         ),
    .test_mode_i( test_mode_i    ),
    .enable_i   ( 1'b1           ),
    .clear_i    ( clear          ),
    .data_in    ( data_in        ),
    .data_out   ( data_out       ),
    .tcdm       ( tcdm           ),
    .ctrl_i     ( streamer_ctrl  ),
    .flags_o    ( streamer_flags )
  );


  FFT_engine #(
    .BW_ALIGNED ( BW_ALIGNED ),
    .DATA_WIDTH ( 12         )
  ) i_engine (
    .clk_i      ( clk_i          ),
    .rst_ni     ( rst_ni         ),
    .test_mode_i( test_mode_i    ),
    .data_in    ( data_in        ),
    .data_out   ( data_out       ),
    .ctrl_i     ( engine_ctrl    ),
    .flags_o    ( engine_flags   )
  );

endmodule
