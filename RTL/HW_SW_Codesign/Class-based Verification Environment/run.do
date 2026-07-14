transcript file simulation_transcript.txt
vlog -f files.txt
vsim -voptargs=+acc -sv_seed random work.tb_top
run -all