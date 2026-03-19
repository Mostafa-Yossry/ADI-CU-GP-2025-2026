vlib work

vlog \
  convround.sv \
  twiddle_rom_bank.sv \
  simple_butterfly.sv \
  tb.sv

vsim -vopt -voptargs=+acc work.tb_butterfly
do wave.do
run -all
