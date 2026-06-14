onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/ID
add wave -noupdate -group hwpe_top_wrap_i -radix decimal /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/BW
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/N_CORES
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/N_CONTEXT
add wave -noupdate -group hwpe_top_wrap_i -radix decimal /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/BW_ALIGNED
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/clk_i
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/rst_ni
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/test_mode_i
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/evt_o
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/clear
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/streamer_ctrl
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/streamer_flags
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/engine_ctrl
add wave -noupdate -group hwpe_top_wrap_i /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/engine_flags
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/DW}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/AW}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/BW}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/WW}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/OW}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/UW}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/clk}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/req}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/gnt}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/lrdy}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/add}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/wen}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/data}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/be}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/boffs}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/user}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/r_data}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/r_valid}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/r_opc}
add wave -noupdate -group tcdm {/tb_pulp/i_dut/cluster_domain_i/cluster_i/s_hci_hwpe[0]/r_user}
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/TCDM_FIFO_DEPTH
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/BW
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/BW_ALIGNED
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/clk_i
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/rst_ni
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/test_mode_i
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/enable_i
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/clear_i
add wave -noupdate -group i_streamer -expand -subitemconfig {/tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/ctrl_i.data_in_source_ctrl -expand /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/ctrl_i.data_out_sink_ctrl -expand} /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/ctrl_i
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/flags_o
add wave -noupdate -group i_streamer /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_streamer/tcdm_fifo_flags
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/BW_ALIGNED
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/DATA_WIDTH
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/clk_i
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/rst_ni
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/test_mode_i
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/ctrl_i
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/flags_o
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_data_i
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/sample_data_in
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_data_o
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/sample_data_out
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/in32
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/out32
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/empty_data_in
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/full_data_in
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/pop_data_in
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/empty_data_out
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/full_data_out
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/push_data_out
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/valid_in
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/valid_out
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/valid_in_start
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/valid_in_finish
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/count_to_pop_data_in
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/count_to_disable_valid
add wave -noupdate -expand -group i_engine /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/count_to_push_data_out
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/ID_WIDTH
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/clk
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/req
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/gnt
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/add
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/wen
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/be
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/data
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/id
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/r_data
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/r_valid
add wave -noupdate -group periph /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/periph/r_id
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/clk_i
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/rst_ni
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/flush_i
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/testmode_i
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/full_o
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/empty_o
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/usage_o
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/data_i
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/push_i
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/data_o
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/pop_i
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/gate_clock
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/read_pointer_n
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/read_pointer_q
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/write_pointer_n
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/write_pointer_q
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/status_cnt_n
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/status_cnt_q
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/mem_n
add wave -noupdate -group fifo_pre_data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_pre_data_in/mem_q
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/FALL_THROUGH
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/DATA_WIDTH
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/DEPTH
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/ADDR_DEPTH
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/FifoDepth
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/clk_i
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/rst_ni
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/flush_i
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/testmode_i
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/full_o
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/empty_o
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/usage_o
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/data_i
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/push_i
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/data_o
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/pop_i
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/gate_clock
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/read_pointer_n
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/read_pointer_q
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/write_pointer_n
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/write_pointer_q
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/status_cnt_n
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/status_cnt_q
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/mem_n
add wave -noupdate -expand -group fifo_post_data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/fifo_post_data_out/mem_q
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/DATA_WIDTH
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/STRB_WIDTH
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/BYPASS_VCR_ASSERT
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/BYPASS_VDR_ASSERT
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/clk
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/valid
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/ready
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/data
add wave -noupdate -group data_in /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_in/strb
add wave -noupdate -expand -group data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_out/clk
add wave -noupdate -expand -group data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_out/valid
add wave -noupdate -expand -group data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_out/ready
add wave -noupdate -expand -group data_out -radix hexadecimal /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_out/data
add wave -noupdate -expand -group data_out /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/data_out/strb
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/N_CORES
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/N_CONTEXT
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/N_IO_REGS
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/ID
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/clk_i
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/rst_ni
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/test_mode_i
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/clear_o
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/evt_o
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/ctrl_streamer_o
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/flags_streamer_i
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/ctrl_engine_o
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/flags_engine_i
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/slave_ctrl
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/slave_flags
add wave -noupdate -group i_ctrl /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/reg_file
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/clk_i
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/rst_ni
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/test_mode_i
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/clear_i
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/ctrl_streamer_o
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/flags_streamer_i
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/ctrl_engine_o
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/flags_engine_i
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/ctrl_slave_o
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/flags_slave_i
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/reg_file_i
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/cs
add wave -noupdate -group i_fsm /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_ctrl/i_fsm/ns
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/DATA_WIDTH
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/clk
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/rst_n
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/valid_in
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/in_r
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/in_i
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/out_r
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/out_i
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/valid_out
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/frame_done
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/out_index
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg1_r
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg1_i
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg2_r
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg2_i
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg3_r
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg3_i
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg1_fill_done
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg2_fill_done
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/stg3_fill_done
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/valid_out1
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/valid_out2
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/valid_out3
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/frame_done_dff
add wave -noupdate -group i_fft /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/FFT_gen/hwpe_top_wrap_i/i_engine/i_fft/raw_count
add wave -noupdate -group {bank[0]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[0]/i_bank/sram}
add wave -noupdate -group {bank[1]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[1]/i_bank/sram}
add wave -noupdate -group {bank[2]} -childformat {{{/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[2]/i_bank/sram[256]} -radix hexadecimal}} -expand -subitemconfig {{/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[2]/i_bank/sram[256]} {-height 15 -radix hexadecimal}} {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[2]/i_bank/sram}
add wave -noupdate -group {bank[3]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[3]/i_bank/sram}
add wave -noupdate -group {bank[4]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[4]/i_bank/sram}
add wave -noupdate -group {bank[5]} {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[5]/i_bank/sram}
add wave -noupdate -group {bank[6]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[6]/i_bank/sram}
add wave -noupdate -group {bank[7]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[7]/i_bank/sram}
add wave -noupdate -group {bank[8]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[8]/i_bank/sram}
add wave -noupdate -group {bank[9]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[9]/i_bank/sram}
add wave -noupdate -group {bank[10]} -expand {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[10]/i_bank/sram}
add wave -noupdate -group {bank[11]} {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[11]/i_bank/sram}
add wave -noupdate -group {bank[12]} {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[12]/i_bank/sram}
add wave -noupdate -group {bank[13]} {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[13]/i_bank/sram}
add wave -noupdate -group {bank[14]} {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[14]/i_bank/sram}
add wave -noupdate -group {bank[15]} {/tb_pulp/i_dut/cluster_domain_i/cluster_i/tcdm_banks_i/banks_gen[15]/i_bank/sram}
add wave -noupdate /tb_pulp/i_dut/cluster_domain_i/cluster_i/hwpe_gen/hwpe_subsystem_i/N_MASTER_PORT
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {11899668542 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 178
configure wave -valuecolwidth 227
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {11899495299 ps} {11899881561 ps}
