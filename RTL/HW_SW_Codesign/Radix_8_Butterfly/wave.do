onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_radix8_butterfly/clk
add wave -noupdate /tb_radix8_butterfly/rst
add wave -noupdate /tb_radix8_butterfly/ce
add wave -noupdate /tb_radix8_butterfly/twiddle_idx
add wave -noupdate /tb_radix8_butterfly/data_in
add wave -noupdate /tb_radix8_butterfly/aux_in
add wave -noupdate /tb_radix8_butterfly/data_out
add wave -noupdate /tb_radix8_butterfly/aux_out
add wave -noupdate /tb_radix8_butterfly/result_count
add wave -noupdate /tb_radix8_butterfly/test_id
add wave -noupdate /tb_radix8_butterfly/cycle_count
add wave -noupdate /tb_radix8_butterfly/aux_in_q
add wave -noupdate /tb_radix8_butterfly/aux_out_q
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
WaveRestoreZoom {0 ps} {1 ns}
