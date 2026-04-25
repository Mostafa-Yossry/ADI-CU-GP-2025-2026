vlib work

vlog \
  convround.sv \
  twiddle_rom_bank.sv \
  radix8_butterfly.sv \
  tb.sv

vsim -vopt -voptargs=+acc work.tb_radix8_butterfly
do wave.do
run -all
