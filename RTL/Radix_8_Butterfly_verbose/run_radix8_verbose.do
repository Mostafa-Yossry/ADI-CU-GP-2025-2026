vlib work

vlog \
  convround.sv \
  twiddle_rom_bank.sv \
  radix8_butterfly_verbose.sv \
  tb_verbose.sv

vsim -vopt -voptargs=+acc work.tb_radix8_butterfly_verbose
do wave_verbose.do
run -all
