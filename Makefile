# Proyecto 4 - Pochoco Trader (Espino Core sobre la Go Board)
#
#   make algo        compara estrategias en series sinteticas (Python)
#   make ref         decisiones de la referencia Python para SERIE
#   make hex         sw/trade.s -> sw/trade.hex
#   make sim         testbench que emula a la maestra (TICK ciclos por tick)
#   make check       sim + compara cada decision con Python + perfil por tick
#   make profile     perfil por seccion de trade.s (despues de make sim)
#   make bin / prog  sintesis, place & route, bitstream y programar la placa
#   make demo        version DEMO (precios de una tabla interna) y programar la placa
#   make test        pruebas del assembler
#
# Variables: SERIE=data/serie.csv  N=ticks  TICK=2500 (ronda 3: 0,1 ms a 25 MHz)
# En Windows (Git Bash) usar PYTHON=python.

PYTHON ?= python3
ASM    := $(PYTHON) tools/rvasm.py
SERIE  ?= data/serie_sintetica.csv
N      ?= 1000
TICK   ?= 2500

TOP  := game_top
PCF  := goboard.pcf
FREQ := 25
SRC  := $(wildcard rtl/fpga/*.v rtl/common/*.v rtl/common/espino_core/*.v)
CELLS := $(shell yosys-config --datdir 2>/dev/null)/ice40/cells_sim.v

.PHONY: all algo ref hex sim check profile bin prog demo demo-bin test clean

all: bin

algo:
	cd algo && $(PYTHON) explore.py

ref:
	$(PYTHON) algo/trade_ref.py $(SERIE) -o sim/out/decisiones_ref.txt

hex: sw/trade.hex
sw/trade.hex: sw/trade.s tools/rvasm.py
	$(ASM) sw/trade.s -o sw/trade.hex -l sw/trade.lst --report

data/precios.hex: $(SERIE)
	$(PYTHON) -c "import sys; sys.path.insert(0,'algo'); import series; \
	p = series.load_csv('$(SERIE)'); open('$@','w').write(''.join(f'{x:02x}\n' for x in p))"

sim: sw/trade.hex data/precios.hex
	mkdir -p sim/out
	iverilog -g2012 -o sim/out/tb.vvp sim/tb_trader.v $(SRC) $(CELLS)
	vvp -n sim/out/tb.vvp +N=$(N) +TICK=$(TICK)

check: sim
	$(PYTHON) sim/compare.py $(SERIE) sim/out/decisiones_asm.txt sim/out/perfil.csv

profile:
	$(PYTHON) sim/sections.py sw/trade.lst sim/out/perfil_pc.csv

$(TOP).json: $(SRC) sw/trade.hex
	yosys -p "read_verilog -DPOCHOCO_MEMFILE=\"sw/trade.hex\" $(SRC); synth_ice40 -top $(TOP) -json $(TOP).json; stat"
$(TOP).asc: $(TOP).json $(PCF)
	nextpnr-ice40 --hx1k --package vq100 --freq $(FREQ) --json $(TOP).json --pcf $(PCF) --asc $(TOP).asc
$(TOP).bin: $(TOP).asc
	icepack $(TOP).asc $(TOP).bin
bin: $(TOP).bin
prog: $(TOP).bin
	iceprog $(TOP).bin

# Version DEMO: sin la maestra, lee precios de una tabla (solo para probar la placa)
sw/trade_demo.hex: sw/trade.s tools/make_demo.py
	$(PYTHON) tools/make_demo.py
	$(ASM) sw/trade_demo.s -o sw/trade_demo.hex
demo.json: $(SRC) sw/trade_demo.hex
	yosys -p "read_verilog -DPOCHOCO_MEMFILE=\"sw/trade_demo.hex\" $(SRC); synth_ice40 -top $(TOP) -json demo.json"
demo.asc: demo.json $(PCF)
	nextpnr-ice40 --hx1k --package vq100 --freq $(FREQ) --json demo.json --pcf $(PCF) --asc demo.asc
demo.bin: demo.asc
	icepack demo.asc demo.bin
demo-bin: demo.bin
demo: demo.bin
	iceprog demo.bin

test:
	$(PYTHON) tools/test_rvasm.py

clean:
	rm -rf sim/out build $(TOP).json $(TOP).asc $(TOP).bin demo.json demo.asc demo.bin
