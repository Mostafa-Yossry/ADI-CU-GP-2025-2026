vlib work
vlog *.sv
vsim +define+SVA_ON -vopt -voptargs=+acc work.tb_matched_filter_pipe_wrap
run -all
