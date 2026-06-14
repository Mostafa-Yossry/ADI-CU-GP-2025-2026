vlib work
vlog *.sv
vsim +define+SVA_ON -vopt -voptargs=+acc work.tb_matlab_debug
run -all
