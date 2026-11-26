# Proyecto 4 · Pochoco Trader · Grupo 7

Arquitectura de Computadores 2026-2 · Universidad de los Andes · Profesor Jorge Gómez Mir
Integrantes: Lucas Fernández · Maximiliano Ferrando · Renato Rivadeneira · Matías Ureta

Agente de inversión que corre en el Pochoco SoC (Espino Core, RV32E) sobre la Go Board. La FPGA maestra
envía por SPI un precio por tick; `sw/trade.s` responde en el registro DECISION si compra, vende o mantiene.
El informe está en `Informe_Proyecto_4_Grupo_7.pdf`.

**Algoritmo:** híbrido de tendencia y reversión a la media con control de riesgo.

* Tendencia: media de 20 precios contra media de 120 (entra con +4, sale con −2).
* Reversión: compra cuando el precio cae 4 bajo la media de 60 y sale al volver a ella, salvo bajada fuerte.
* Riesgo: stop de 8 unidades bajo el máximo desde la entrada, pausa de 64 ticks después de un stop y
  abstención de 64 ticks después de un salto de precio de 32 o más (cambio de día).
* Cantidad: siempre 63 en la dirección deseada (`0x7F` comprar, `0xBF` vender). La maestra recorta la orden
  a la caja o a las acciones disponibles y no cobra comisión por órdenes que quedan en cero.

## Estructura

| Carpeta | Contenido |
|---|---|
| `rtl/` | Pochoco SoC: `pochoco_soc.v` (top de la Go Board, parámetro `MemFile`), memoria, periféricos, esclavo SPI, contador de ciclos y **`pochoco_mavg.v`** (periférico de sumas móviles, co-diseño) |
| `rtl/espino_core/` | Espino Core (RV32E) con banco de registros en BRAM. Opciones de co-diseño por `define`: `ESPINO_PC_BITS`, `ESPINO_SHIFTER`, `ESPINO_MUL8` |
| `sw/trade.s` | El agente en assembly (versión de competencia, solo software) |
| `sw/trade_mavg.s`, `sw/trade_sig.s` | El mismo agente para las variantes con hardware |
| `sw/trade_hibrido.s`, `sw/trade_contab.s` | Versiones anteriores del algoritmo (historial) |
| `tb/` | Testbench **oficial** (`tb_proyecto_4.sv`), series de práctica y **`tb_mavg.v`** (testbench del hardware agregado) |
| `algo/` | Simulador del mercado (`market.py`, contabilidad idéntica al testbench oficial) y referencia exacta de `trade.s` (`trade_ref.py`) |
| `sim/` | Testbench propio: compara cada decisión con Python y mide IC, ciclos y CPI por tick y por sección |
| `tools/` | Assembler del grupo (`rvasm.py`; `pochoasm.py` es un alias), `sintesis.py`, `codiseno.py`, `figuras.py` |
| `docs/` | Figuras del informe y `docs/mediciones/` (perfiles por tick de 20.000 ticks por serie y variante, síntesis, tabla de co-diseño) |

## Comandos

En Windows (Git Bash) agregar `PYTHON=python` a los comandos `make`.

| Comando | Qué hace |
|---|---|
| `make hex` | Ensambla `sw/trade.s` → `sw/trade.hex` (equivale a `python3 tools/pochoasm.py sw/trade.s -o sw/trade.hex`) |
| `python3 algo/trade_ref.py tb/practica.csv` | Versión de referencia del algoritmo en Python |
| `make tb` | Testbench oficial del curso. Debe terminar con `Testbenchs aprobados: 4/4` |
| `make check N=20000 TICK=700` | Testbench propio: compara cada decisión con Python y mide IC, ciclos y CPI por tick |
| `make profile` | Ciclos por sección del programa (después de `make check`) |
| `make tb-mavg` | Testbench autoverificado del periférico `pochoco_mavg` en sus dos modos |
| `make prog` | Sintetiza, hace place & route y programa la Go Board (versión de competencia) |
| `make demo` | Versión de prueba sin la maestra: precios de una tabla interna (no usar en la competencia) |
| `make test` | Pruebas del assembler |

Otra serie: `make check SERIE=tb/practica_meta.csv N=20000 TICK=700`.

### Variantes de co-diseño

Todos los comandos aceptan `VARIANTE=`. Cada variante se construye en `build/<variante>/`.

| Variante | Hardware | Programa |
|---|---|---|
| `base` (por defecto) | Core original, solo software | `sw/trade.s` |
| `pc12` | PC del Espino de 12 bits | `sw/trade.s` |
| `mavg` | `pc12` + periférico de sumas móviles | `sw/trade_mavg.s` |
| `sig` | `pc12` + periférico que entrega las señales ya combinadas | `sw/trade_sig.s` |
| `mul8`, `shifter`, `pll` | Evaluadas y descartadas: solo para reproducir su costo con `make bin` | `sw/trade.s` |

```bash
make check VARIANTE=sig N=20000 TICK=520     # mismas decisiones que la referencia + mediciones
make tb    VARIANTE=sig                      # testbench oficial con la variante
make prog  VARIANTE=sig                      # sintetiza y programa la variante
for v in base pc12 mavg sig mul8 shifter pll; do make bin VARIANTE=$v; done   # shifter y pll terminan en error: no caben
python3 tools/sintesis.py                    # LUT4, celdas, BRAM y Fmax -> docs/mediciones/sintesis.csv
python3 tools/codiseno.py                    # tabla comparativa, Amdahl y roofline
python3 tools/figuras.py                     # figuras del informe (requiere matplotlib)
```

## Resultados con las series de práctica (20.000 ticks)

| Serie | trade.s | Órdenes | Comisiones | Pérdida máx. | Comprar y mantener | No operar |
|---|---|---|---|---|---|---|
| `practica.csv` | **$17.394** | 517 | $2.585 | $4.518 | $6.497 | $10.000 |
| `practica_meta.csv` | **$24.317** | 416 | $2.080 | $5.778 | $9.695 | $10.000 |

* `trade.s` toma las mismas 20.000 decisiones que `algo/trade_ref.py` en cada una de las dos series
  (simulación RTL del SoC completo). Lo mismo se verificó para las variantes `pc12`, `mavg` y `sig`.
* Testbench oficial: 4/4 aprobados.
* Por tick: 82 instrucciones y 188 ciclos en promedio (7,5 µs), 209 ciclos en el peor caso; CPI 2,29.
  En la ronda 3 (2.256 ciclos disponibles) el peor caso usa el 9,3 %.

| Variante | LUT4 | Celdas (de 1.280) | BRAM | Fmax | Ciclos/tick | Speedup | Amdahl |
|---|---|---|---|---|---|---|---|
| `base` | 1.015 | 1.194 | 12 | 44,5 MHz | 188,3 | 1,00 | |
| `pc12` | 912 | 1.071 | 12 | 45,8 MHz | 188,3 | 1,00 | |
| `mavg` | 1.024 | 1.196 | 13 | 42,7 MHz | 149,9 | 1,26 | 1,24 |
| `sig` | 1.028 | 1.202 | 13 | 42,8 MHz | 123,1 | 1,53 | 1,54 |

Descartadas: `shifter` (1.581 celdas, no cabe), `mul8` (1.265 celdas para ahorrar menos del 6 % de los
ciclos) y `pll` (el iCE40HX1K-VQ100 de la Go Board no tiene PLL: nextpnr no encuentra dónde ubicarlo).

**Variante que compite: `base`.** Cumple el plazo de la ronda más rápida con un margen de 10 veces, toma
exactamente las mismas decisiones que las variantes con hardware y su hardware es el único validado en la
placa con la FPGA maestra.

Nota sobre el reset: en la placa el reset de encendido dura 2^20 ciclos (~42 ms). Con el reset corto del
repositorio base el core podía partir antes de que las BRAM estuvieran listas y no leía el SPI.

## Versiones de las herramientas

* Placa y síntesis del grupo: OSS CAD Suite 2026-08-26 para Windows (Yosys, nextpnr-ice40, IceStorm,
  Icarus Verilog), Git Bash y Python 3.
* Mediciones del informe: Python 3.13, Icarus Verilog 12.0, Yosys 0.71, nextpnr-ice40 0.11.1.
  El número de celdas y la Fmax pueden variar levemente entre versiones.

> Icarus Verilog 12 no acepta la variable `string` de la línea 44 del testbench oficial; con la versión de
> OSS CAD Suite corre sin cambios.
