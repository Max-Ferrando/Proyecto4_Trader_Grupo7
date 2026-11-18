# Proyecto 4 · Pochoco Trader · Grupo 7

Arquitectura de Computadores 2026-2 · Universidad de los Andes · Profesor Jorge Gómez Mir
Integrantes: Lucas Fernández · Maximiliano Ferrando · Renato Rivadeneira · Matías Ureta

Agente de inversión que corre en el Pochoco SoC (Espino Core, RV32E) sobre la Go Board. La FPGA maestra
envía por SPI un precio por tick; `sw/trade.s` responde en el registro DECISION si compra, vende o mantiene.

**Algoritmo:** cruce de medias móviles. Si la media de los últimos 20 precios supera a la de los últimos 120
por más de 8 unidades, el precio viene subiendo y el agente compra; si queda por debajo por más de 8, vende.
Parámetros elegidos con las **dos** series de práctica oficiales (`tb/practica.csv` y `tb/practica_meta.csv`,
ver `algo/tune_all2.py`): es la configuración que gana a *comprar y mantener* y a *no operar* en ambas, dentro
de una zona estable de parámetros.

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
| `practica.csv` | **$11.413** | 23 | $4.743 | $6.497 | $10.000 |
| `practica_meta.csv` | **$13.851** | 11 | $2.960 | $9.695 | $10.000 |

* Testbench oficial: **4/4 aprobados**. Con su configuración por defecto (2.000 ticks de `practica.csv`):
  patrimonio $8.688 contra $6.695 de comprar y mantener; peor caso 1.048 ciclos de 2.262.
* El patrimonio de cada tick del testbench oficial coincide exactamente con `algo/trade_ref.py`.
* Diseño en el iCE40 HX1K: 1.163 / 1.280 celdas lógicas (91 %), 12 / 16 BRAM, Fmax ≈ 44,7 MHz.
* Historia: la reversión a la media (ventana 60) ganaba $31.558 en `practica.csv` pero perdía en
  `practica_meta.csv` ($7.513); por eso se cambió a una estrategia que gana en las dos.

## Versiones

Mediciones hechas con Python 3.13, Icarus Verilog 12.0, Yosys 0.70 y nextpnr-ice40 0.11.1. La placa se
programa con OSS CAD Suite (Windows, 2026-08-26).

> Nota: Icarus Verilog 12 no acepta `string` en `$fgets` (línea 44 del testbench oficial); con una versión
> más nueva (la de OSS CAD Suite) corre sin cambios.
