"""make_demo.py - Genera sw/trade_demo.s: trade.s sin la FPGA maestra.

Reemplaza la espera del precio por SPI por la lectura de una tabla de precios
guardada en el programa, con una pausa entre ticks para poder ver en la placa
lo que hace el agente:
  * display: precio actual en hexadecimal
  * LED 1: quiero estar comprado   LED 2: orden de compra   LED 3: orden de venta
El resto del programa (contabilidad, medias, decision y escritura de DECISION)
es exactamente el de trade.s.

SOLO PARA PROBAR LA PLACA: la version de la competencia es sw/trade.s (las
reglas no permiten guardar series de precios en el diseno).

Uso: python3 tools/make_demo.py [serie.csv] [-n 96]
"""
import argparse
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "algo"))
import series  # noqa: E402

OLD_WAIT = """wait:                               # 1) esperar precio
    lw   t0, 0(s0)                  # STATUS
    andi t0, t0, 1
    beqz t0, wait
    lw   a0, 4(s0)                  # PRICE (leerlo baja el bit de precio nuevo)
"""

NEW_WAIT = """wait:                               # DEMO: precio desde la tabla
    li   t0, DELAY                  # pausa entre ticks
demo_dly:
    addi t0, t0, -1
    bnez t0, demo_dly
    lw   t1, DEMO_IDX(zero)         # indice actual (bytes)
    lw   a0, demo_tab(t1)
    addi t1, t1, 4
    li   t2, 4 * DEMO_N
    bne  t1, t2, demo_ok
    li   t1, 0                      # al terminar la tabla vuelve a empezar
demo_ok:
    sw   t1, DEMO_IDX(zero)
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", nargs="?")
    ap.add_argument("-n", type=int, default=96)
    a = ap.parse_args()
    prices = series.load_csv(a.csv) if a.csv else series.make("tendencias", 0)
    prices = prices[:a.n]
    src = open(os.path.join(ROOT, "sw", "trade.s")).read()
    assert OLD_WAIT in src, "no encontre el bloque de espera en trade.s"
    src = src.replace(OLD_WAIT, NEW_WAIT)
    src = src.replace("    sw   zero, 8(s0)                # DECISION = mantener\n",
                      "    sw   zero, 8(s0)                # DECISION = mantener\n"
                      "    sw   zero, DEMO_IDX(zero)       # DEMO: empieza en el primer precio\n")
    head = ("# GENERADO por tools/make_demo.py a partir de sw/trade.s. NO EDITAR.\n"
            "# Version DEMO: lee precios de una tabla (solo para probar la placa).\n"
            ".equ DELAY,    1600000             # ~0,3 s por tick a 25 MHz\n"
            f".equ DEMO_N,   {len(prices)}\n"
            ".equ DEMO_IDX, 0x6FC               # indice de la tabla, justo antes del buffer\n")
    tab = "\n# ----------------------------- Tabla DEMO ------------------------------------\ndemo_tab:\n"
    for i in range(0, len(prices), 8):
        tab += "    .word " + ", ".join(str(p) for p in prices[i:i + 8]) + "\n"
    out = os.path.join(ROOT, "sw", "trade_demo.s")
    open(out, "w").write(head + src + tab)
    print(f"{out}: {len(prices)} precios")


if __name__ == "__main__":
    main()
