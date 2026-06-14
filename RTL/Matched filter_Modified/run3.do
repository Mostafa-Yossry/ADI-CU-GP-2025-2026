vlib work
vlog *.sv
vsim +define+SVA_ON -vopt -voptargs=+acc work.tb_hermitian_mf_chain
run -all
