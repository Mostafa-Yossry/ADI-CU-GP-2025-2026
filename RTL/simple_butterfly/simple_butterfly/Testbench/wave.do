onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_butterfly/dut/IWIDTH
add wave -noupdate /tb_butterfly/dut/CWIDTH
add wave -noupdate /tb_butterfly/dut/OWIDTH
add wave -noupdate /tb_butterfly/dut/SHIFT
add wave -noupdate /tb_butterfly/dut/MPY_DELAY
add wave -noupdate /tb_butterfly/dut/BFLYLATENCY
add wave -noupdate /tb_butterfly/dut/i_clk
add wave -noupdate /tb_butterfly/dut/i_reset
add wave -noupdate /tb_butterfly/dut/i_clk_enable
add wave -noupdate /tb_butterfly/dut/i_twiddle_idx
add wave -noupdate /tb_butterfly/dut/i_left
add wave -noupdate /tb_butterfly/dut/i_right
add wave -noupdate /tb_butterfly/dut/i_aux
add wave -noupdate /tb_butterfly/dut/o_left
add wave -noupdate /tb_butterfly/dut/o_right
add wave -noupdate /tb_butterfly/dut/o_aux
add wave -noupdate /tb_butterfly/dut/r_left
add wave -noupdate /tb_butterfly/dut/r_right
add wave -noupdate /tb_butterfly/dut/w_coef
add wave -noupdate /tb_butterfly/dut/r_coef
add wave -noupdate /tb_butterfly/dut/l_r
add wave -noupdate /tb_butterfly/dut/l_i
add wave -noupdate /tb_butterfly/dut/r_r
add wave -noupdate /tb_butterfly/dut/r_i
add wave -noupdate /tb_butterfly/dut/w_r
add wave -noupdate /tb_butterfly/dut/w_i
add wave -noupdate /tb_butterfly/dut/sum_r
add wave -noupdate /tb_butterfly/dut/sum_i
add wave -noupdate /tb_butterfly/dut/dif_r
add wave -noupdate /tb_butterfly/dut/dif_i
add wave -noupdate /tb_butterfly/dut/p1
add wave -noupdate /tb_butterfly/dut/p2
add wave -noupdate /tb_butterfly/dut/p3
add wave -noupdate /tb_butterfly/dut/mpy_r
add wave -noupdate /tb_butterfly/dut/mpy_i
add wave -noupdate /tb_butterfly/dut/sum_r_d
add wave -noupdate /tb_butterfly/dut/sum_i_d
add wave -noupdate /tb_butterfly/dut/i
add wave -noupdate /tb_butterfly/dut/left_sr
add wave -noupdate /tb_butterfly/dut/left_si
add wave -noupdate /tb_butterfly/dut/right_sr
add wave -noupdate /tb_butterfly/dut/right_si
add wave -noupdate /tb_butterfly/dut/left_r
add wave -noupdate /tb_butterfly/dut/left_i
add wave -noupdate /tb_butterfly/dut/right_r
add wave -noupdate /tb_butterfly/dut/right_i
add wave -noupdate /tb_butterfly/dut/aux_pipe
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
