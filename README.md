# Proyecto 4 · Pochoco Trader · Grupo 7

Arquitectura de Computadores 2026-2 · Universidad de los Andes · Profesor Jorge Gómez Mir
Integrantes: Lucas Fernández · Maximiliano Ferrando · Renato Rivadeneira · Matías Ureta

Agente de inversión que corre en el Pochoco SoC (Espino Core, RV32E) sobre la Go Board. La FPGA maestra
envía por SPI un precio por tick; `sw/trade.s` responde en el registro DECISION si compra, vende o mantiene.

**Algoritmo:** híbrido de tendencia y reversión a la media. Tendencia: media de 20 precios contra media de 120
(margen 8). Reversión: compra cuando el precio cae 4 bajo la media de 60 precios y sale al volver a ella, salvo
que haya una bajada fuerte (media corta más de 4 bajo la larga). Parámetros elegidos con las **dos** series de
práctica oficiales (`tb/practica.csv` y `tb/practica_meta.csv`).

## Estructura

| Carpeta | Contenido |
|---|---|
| `rtl/` | Pochoco SoC: `pochoco_soc.v` (top de la Go Board, parámetro `MemFile`), memoria, periféricos, esclavo SPI, contador de ciclos |
| `rtl/espino_core/` | Espino Core (RV32E) y el banco de registros con BRAM del iCE40 |
| `sw/trade.s` | El agente en assembly |
| `tb/` | Testbench **oficial** del curso (`tb_proyecto_4.sv`) y las dos series de práctica (`practica.csv`, `practica_meta.csv`) |
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

## Resultados con las series de práctica (20.000 ticks)

| Serie | trade.s | Órdenes | Pérdida máx. | Comprar y mantener | No operar |
|---|---|---|---|---|---|
| `practica.csv` | **$16.372** | 373 | $4.956 | $6.497 | $10.000 |
| `practica_meta.csv` | **$14.960** | 216 | $4.554 | $9.695 | $10.000 |

* Testbench oficial: **4/4 aprobados**; el patrimonio de cada tick coincide con `algo/trade_ref.py`.
* Peor caso forzado (`tb/peor_caso.csv`): 1.907 ciclos de 2.262 disponibles en la ronda 3.
* Diseño en el iCE40 HX1K: ~1.190 / 1.280 celdas lógicas, 12 / 16 BRAM, Fmax ≈ 43 MHz.
* El reset de encendido dura 2^20 ciclos (~42 ms) en la placa: con el reset corto del repo base el core podía
  partir antes de que las BRAM estuvieran listas y no leía el SPI.
* Historia: reversión pura ($31.558 / $7.513) y cruce de medias puro ($11.413 / $13.851) fueron descartados
  por el híbrido, que rinde mejor en la peor de las dos series.

## Versiones

Mediciones hechas con Python 3.13, Icarus Verilog 12.0, Yosys 0.70 y nextpnr-ice40 0.11.1. La placa se
programa con OSS CAD Suite (Windows, 2026-08-26).

> Nota: Icarus Verilog 12 no acepta `string` en `$fgets` (línea 44 del testbench oficial); con una versión
> más nueva (la de OSS CAD Suite) corre sin cambios.
