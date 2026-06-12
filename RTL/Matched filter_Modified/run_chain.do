vlib work
vlog *.sv
vsim +define+SVA_ON -vopt -voptargs=+acc work.tb_herm_mf_chain
run -all
