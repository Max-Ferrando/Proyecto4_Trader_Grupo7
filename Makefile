# Proyecto 4 - Pochoco Trader (Espino Core sobre la Go Board)
#
#   make algo        compara estrategias en series sinteticas (Python)
#   make ref         decisiones de la referencia Python para SERIE
#   make hex         ensambla el programa de la variante
#   make sim         testbench que emula a la maestra (TICK ciclos por tick)
#   make check       sim + compara cada decision con Python + perfil por tick
#   make profile     perfil por seccion del programa (despues de make sim)
#   make bin / prog  sintesis, place & route, bitstream y programar la placa
#   make tb          testbench OFICIAL del curso (tb/tb_proyecto_4.sv)
#   make tb-mavg     testbench del periferico rtl/pochoco_mavg.v (dos modos)
#   make codiseno    tabla comparativa de variantes + roofline (docs/)
#   make demo        version DEMO (precios de una tabla interna) y programar la placa
#   make test        pruebas del assembler
#
# Variables: SERIE=tb/practica.csv  N=ticks  TICK=2500 (ronda 3: 0,1 ms a 25 MHz)
#            VARIANTE=base|pc12|mavg|sig   (co-diseno, ver README)
# En Windows (Git Bash) usar PYTHON=python.

PYTHON ?= python3
ASM    := $(PYTHON) tools/rvasm.py
SERIE  ?= tb/practica.csv
N      ?= 2000
TICK   ?= 2500

TOP  := pochoco_soc
PCF  := goboard.pcf
FREQ := 25
SRC  := $(wildcard rtl/*.v rtl/espino_core/*.v)
CELLS := $(shell yosys-config --datdir 2>/dev/null)/ice40/cells_sim.v

# ---------------- variantes de co-diseno ----------------
#   base  solo software: core original y sw/trade.s  (la que compite)
#   pc12  base + PC de 12 bits en el Espino (libera celdas, mismos ciclos)
#   mavg  pc12 + periferico de sumas moviles          (sw/trade_mavg.s)
#   sig   pc12 + periferico que entrega las senales   (sw/trade_sig.s)
# Evaluadas y descartadas (solo para reproducir su costo con "make bin"):
#   shifter  habilita SLL/SRL/SRA: no cabe en la HX1K
#   mul8     multiplicador de 8x8 en la ALU
#   pll      PLL a 37,5 MHz: el iCE40HX1K-VQ100 de la Go Board no tiene PLL
VARIANTE ?= base
PROG := trade
DEFS :=
ifeq ($(VARIANTE),pc12)
  DEFS := -DESPINO_PC_BITS=12
endif
ifeq ($(VARIANTE),mavg)
  DEFS := -DESPINO_PC_BITS=12 -DPOCHOCO_MAVG
  PROG := trade_mavg
endif
ifeq ($(VARIANTE),sig)
  DEFS := -DESPINO_PC_BITS=12 -DPOCHOCO_MAVG -DPOCHOCO_MAVG_SIG -DPOCHOCO_NO_CYCLE_CNT
  PROG := trade_sig
endif
ifeq ($(VARIANTE),shifter)
  DEFS := -DESPINO_SHIFTER
endif
ifeq ($(VARIANTE),mul8)
  DEFS := -DESPINO_MUL8
endif
ifeq ($(VARIANTE),pll)
  DEFS := -DPOCHOCO_PLL
  FREQ := 37.5
endif
HEX := sw/$(PROG).hex
B   := build/$(VARIANTE)
O   := sim/out/$(VARIANTE)

.PHONY: all algo ref hex sim check profile bin prog demo demo-bin test tb tb-mavg codiseno clean

all: bin

algo:
	cd algo && $(PYTHON) explore.py

ref:
	$(PYTHON) algo/trade_ref.py $(SERIE) -o sim/out/decisiones_ref.txt

hex: $(HEX)
sw/%.hex: sw/%.s tools/rvasm.py
	$(ASM) $< -o $@ -l sw/$*.lst --report

data/precios.hex: $(SERIE)
	$(PYTHON) -c "import sys; sys.path.insert(0,'algo'); import series; \
	p = series.load_csv('$(SERIE)'); open('$@','w').write(''.join(f'{x:02x}\n' for x in p))"

sim: $(HEX) data/precios.hex
	mkdir -p $(O)
	iverilog -g2012 $(DEFS) '-DPOCHOCO_MEMFILE="$(HEX)"' -o $(O)/tb.vvp sim/tb_trader.v $(SRC) $(CELLS)
	vvp -n $(O)/tb.vvp +N=$(N) +TICK=$(TICK) +OUT=$(O)/decisiones_asm.txt +PROF=$(O)/perfil.csv +PCPROF=$(O)/perfil_pc.csv

check: sim
	$(PYTHON) sim/compare.py $(SERIE) $(O)/decisiones_asm.txt $(O)/perfil.csv

profile:
	$(PYTHON) sim/sections.py sw/$(PROG).lst $(O)/perfil_pc.csv

$(B)/$(TOP).json: $(SRC) $(HEX)
	mkdir -p $(B)
	yosys -l $(B)/yosys.log -p "read_verilog $(DEFS) -DPOCHOCO_MEMFILE=\"$(HEX)\" $(SRC); synth_ice40 -top $(TOP) -json $(B)/$(TOP).json; tee -o $(B)/stat.txt stat"
$(B)/$(TOP).asc: $(B)/$(TOP).json $(PCF)
	nextpnr-ice40 --hx1k --package vq100 --freq $(FREQ) --json $(B)/$(TOP).json --pcf $(PCF) --asc $(B)/$(TOP).asc -l $(B)/nextpnr.log
$(B)/$(TOP).bin: $(B)/$(TOP).asc
	icepack $(B)/$(TOP).asc $(B)/$(TOP).bin
bin: $(B)/$(TOP).bin
prog: $(B)/$(TOP).bin
	iceprog $(B)/$(TOP).bin

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

# Testbench oficial del curso: misma serie, contabilidad oficial y 4 chequeos.
# El archivo oficial no se modifica: para las variantes solo se cambia, en una
# copia, el nombre del programa que carga.
tb: $(HEX)
	mkdir -p $(O)
	sed 's#sw/trade.hex#$(HEX)#' tb/tb_proyecto_4.sv > $(O)/tb_proyecto_4.sv
	iverilog -g2012 $(DEFS) -s tb_proyecto_4 -o $(O)/tb_p4 $(CELLS) $(SRC) $(O)/tb_proyecto_4.sv
	vvp -n $(O)/tb_p4

# Testbench del hardware agregado (periferico de sumas moviles), en sus dos modos
tb-mavg:
	mkdir -p sim/out
	iverilog -g2012 -o sim/out/tb_mavg.vvp tb/tb_mavg.v rtl/pochoco_mavg.v
	vvp -n sim/out/tb_mavg.vvp
	iverilog -g2012 -DPOCHOCO_MAVG_SIG -o sim/out/tb_mavg_sig.vvp tb/tb_mavg.v rtl/pochoco_mavg.v
	vvp -n sim/out/tb_mavg_sig.vvp

# Tabla comparativa de variantes (lee build/<variante>/ y sim/out/<variante>/)
codiseno:
	$(PYTHON) tools/codiseno.py

test:
	$(PYTHON) tools/test_rvasm.py

clean:
	rm -rf sim/out build decisiones.csv $(TOP).json $(TOP).asc $(TOP).bin demo.json demo.asc demo.bin
