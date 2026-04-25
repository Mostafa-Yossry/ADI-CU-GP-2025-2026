onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_radix8_butterfly_verbose/IWIDTH
add wave -noupdate /tb_radix8_butterfly_verbose/CWIDTH
add wave -noupdate /tb_radix8_butterfly_verbose/OWIDTH
add wave -noupdate /tb_radix8_butterfly_verbose/SHIFT
add wave -noupdate /tb_radix8_butterfly_verbose/clk
add wave -noupdate /tb_radix8_butterfly_verbose/rst
add wave -noupdate /tb_radix8_butterfly_verbose/ce
add wave -noupdate /tb_radix8_butterfly_verbose/twiddle_idx
add wave -noupdate /tb_radix8_butterfly_verbose/i_data0
add wave -noupdate /tb_radix8_butterfly_verbose/i_data1
add wave -noupdate /tb_radix8_butterfly_verbose/i_data2
add wave -noupdate /tb_radix8_butterfly_verbose/i_data3
add wave -noupdate /tb_radix8_butterfly_verbose/i_data4
add wave -noupdate /tb_radix8_butterfly_verbose/i_data5
add wave -noupdate /tb_radix8_butterfly_verbose/i_data6
add wave -noupdate /tb_radix8_butterfly_verbose/i_data7
add wave -noupdate /tb_radix8_butterfly_verbose/aux_in
add wave -noupdate /tb_radix8_butterfly_verbose/o_data0
add wave -noupdate /tb_radix8_butterfly_verbose/o_data1
add wave -noupdate /tb_radix8_butterfly_verbose/o_data2
add wave -noupdate /tb_radix8_butterfly_verbose/o_data3
add wave -noupdate /tb_radix8_butterfly_verbose/o_data4
add wave -noupdate /tb_radix8_butterfly_verbose/o_data5
add wave -noupdate /tb_radix8_butterfly_verbose/o_data6
add wave -noupdate /tb_radix8_butterfly_verbose/o_data7
add wave -noupdate /tb_radix8_butterfly_verbose/aux_out
add wave -noupdate /tb_radix8_butterfly_verbose/result_count
add wave -noupdate /tb_radix8_butterfly_verbose/test_id
add wave -noupdate /tb_radix8_butterfly_verbose/cycle_count
add wave -noupdate /tb_radix8_butterfly_verbose/aux_in_q
add wave -noupdate /tb_radix8_butterfly_verbose/aux_out_q
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
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
configure wave -timelineunits ps
update
WaveRestoreZoom {594050 ps} {595050 ps}
