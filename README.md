# Proyecto 4 · Pochoco Trader · Grupo 7

Arquitectura de Computadores 2026-2 · Universidad de los Andes · Profesor Jorge Gómez Mir
Integrantes: Lucas Fernández · Maximiliano Ferrando · Renato Rivadeneira · Matías Ureta

Agente de inversión que corre en el Pochoco SoC (Espino Core, RV32E) sobre la Go Board. La FPGA maestra
envía por SPI un precio por tick; `sw/trade.s` responde en el registro DECISION si compra, vende o mantiene.

> **Estado:** versión de trabajo. El algoritmo está ajustado con series **sintéticas**; se reajusta
> cuando se publique la serie de práctica oficial (`make algo`).

## Estructura

| Carpeta | Contenido |
|---|---|
| `algo/` | Simulador del mercado (`market.py`), series sintéticas, estrategias, exploración de parámetros y la referencia exacta de `trade.s` (`trade_ref.py`) |
| `sw/trade.s` | El agente en assembly para Espino |
| `sim/` | Testbench que emula a la maestra (`tb_trader.v`), comparación con Python y perfiles |
| `rtl/` | Pochoco SoC (`common/`) y top de la Go Board (`fpga/`) |
| `tools/rvasm.py` | Assembler del grupo (Proyectos 2 y 3) |
| `data/` | Series de precios (CSV) |

## Comandos

```bash
make algo                 # compara estrategias y parámetros (Python)
make hex                  # ensambla sw/trade.s
make check                # simula con la maestra emulada, compara cada decisión con Python y mide IC/ciclos/CPI
make check TICK=250000    # lo mismo con el período de la ronda 1 (10 ms)
make profile              # ciclos por sección de trade.s
make prog                 # sintetiza, hace place & route y programa la Go Board
```

Para otra serie: `make check SERIE=data/practica.csv N=<ticks>`.

## Resultados actuales (serie sintética, 1000 ticks)

* `trade.s` toma **las mismas 1000 decisiones** que la referencia en Python.
* Peor caso por tick: 738 instrucciones, 1.627 ciclos (65 µs a 25 MHz), CPI ≈ 2,2 → cabe en la ronda 3 (2.500 ciclos).
* Diseño base en el iCE40 HX1K: 1.169 / 1.280 LUTs (91 %), 12 / 16 BRAM, Fmax ≈ 44 MHz.

## Versiones

Python 3, Icarus Verilog, Yosys, nextpnr-ice40, icestorm (se completan con las versiones exactas de la corrida final).
