# Proyecto 4 · Pochoco Trader · Grupo 7

Arquitectura de Computadores 2026-2 · Universidad de los Andes · Profesor Jorge Gómez Mir
Integrantes: Lucas Fernández · Maximiliano Ferrando · Renato Rivadeneira · Matías Ureta

Agente de inversión que corre en el Pochoco SoC (Espino Core, RV32E) sobre la Go Board. La FPGA maestra
envía por SPI un precio por tick; `sw/trade.s` responde en el registro DECISION si compra, vende o mantiene.

**Algoritmo:** reversión a la media. Con la media de los últimos 60 precios, compra cuando el precio cae
4 unidades bajo la media y vende cuando vuelve a la media. Parámetros elegidos con la serie de práctica
(`algo/tune_practica.py`, `algo/tune_mr.py`), validados en 10 tramos de 2.000 ticks.

## Estructura

| Carpeta | Contenido |
|---|---|
| `rtl/` | Pochoco SoC: `pochoco_soc.v` (top de la Go Board, parámetro `MemFile`), memoria, periféricos, esclavo SPI, contador de ciclos |
| `rtl/espino_core/` | Espino Core (RV32E) y el banco de registros con BRAM del iCE40 |
| `sw/trade.s` | El agente en assembly |
| `tb/` | Testbench **oficial** del curso (`tb_proyecto_4.sv`) y la serie de práctica (`practica.csv`) |
| `algo/` | Simulador del mercado (`market.py`, misma contabilidad que el testbench oficial), estrategias, ajuste de parámetros y la referencia exacta de `trade.s` (`trade_ref.py`) |
| `sim/` | Testbench propio: compara cada decisión con Python y mide IC, ciclos y CPI por tick y por sección |
| `tools/` | Assembler del grupo (`rvasm.py`; `pochoasm.py` es un alias para el comando del testbench oficial) y generador de la demo |

## Comandos

Testbench oficial (desde la raíz, como indica `tb/tb_proyecto_4.sv`):
```bash
python3 tools/pochoasm.py sw/trade.s -o sw/trade.hex
iverilog -g2012 -s tb_proyecto_4 -o /tmp/tb_p4 $(yosys-config --datdir)/ice40/cells_sim.v rtl/*.v rtl/espino_core/*.v tb/tb_proyecto_4.sv
vvp -n /tmp/tb_p4
```
o simplemente `make tb`. Debe terminar con `Testbenchs aprobados: 4/4`.

| Comando | Qué hace |
|---|---|
| `python3 algo/trade_ref.py tb/practica.csv` | Referencia en Python: patrimonio, órdenes, comisiones y pérdida máxima frente a las referencias |
| `make check N=5000` | Testbench propio: mismas decisiones que Python + IC, ciclos y CPI por tick (ronda 3) |
| `make profile` | Ciclos por sección de `trade.s` (después de `make check`) |
| `make prog` | Sintetiza, place & route y programa la Go Board (versión de competencia) |
| `make demo` | Versión de prueba sin la maestra: precios de una tabla interna, uno cada ~0,5 s |
| `make test` | Pruebas del assembler |

En Windows (Git Bash) agregar `PYTHON=python`.

## Resultados con la serie de práctica

| | Patrimonio final | Órdenes | Pérdida máx. |
|---|---|---|---|
| **trade.s, 20.000 ticks** | **$31.558** | 533 | $4.476 |
| Comprar y mantener (definición del testbench) | $6.497 | 1 | — |
| No operar | $10.000 | 0 | — |
| **trade.s, testbench oficial (20.000 ticks)** | **$31.558** | 533 | $4.476 |
| trade.s, testbench oficial (2.000 ticks, configuración por defecto) | $11.167 | 63 | $1.919 |

* Testbench oficial con los 20.000 ticks y el período de la ronda 3: **4/4 aprobados**; peor caso 1.628 ciclos
  de 2.262 disponibles. El patrimonio, las órdenes y la pérdida máxima coinciden exactamente con `algo/trade_ref.py`.
* Testbench propio (5.000 ticks): las 5.000 decisiones son idénticas a Python; peor caso 1.627 ciclos
  hasta escribir DECISION (65 µs), CPI ≈ 2,2.
* Diseño en el iCE40 HX1K: 1.163 / 1.280 celdas lógicas (91 %), 12 / 16 BRAM, Fmax ≈ 44,7 MHz.

## Versiones

Mediciones hechas con Python 3.13, Icarus Verilog 12.0, Yosys 0.70 y nextpnr-ice40 0.11.1. La placa se
programa con OSS CAD Suite (Windows, 2026-08-26).

> Nota: Icarus Verilog 12 no acepta `string` en `$fgets` (línea 44 del testbench oficial); con una versión
> más nueva (la de OSS CAD Suite) corre sin cambios.
