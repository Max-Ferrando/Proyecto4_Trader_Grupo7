"""sections.py - Agrupa el perfil por PC (sim/out/perfil_pc.csv) en las
secciones de trade.s, usando las etiquetas del listado (sw/trade.lst).

Uso: python3 sim/sections.py sw/trade.lst sim/out/perfil_pc.csv
Cada instruccion pertenece a la ultima etiqueta "de seccion" anterior.
"""
import csv
import re
import sys

SECTIONS = {            # etiqueta que abre la seccion -> nombre
    "wait": "esperar precio (sondeo)",
    "apply": "aplicar orden pendiente",
    "update": "ventanas moviles",
    "signal": "senal (L*sc - S*sl)",
    "decide": "decidir cantidad",
    "out": "escribir DECISION + display",
    "afford": "afford (lazo de sumas)",
}


def label_addrs(lst):
    """Direccion de cada etiqueta = direccion de la primera instruccion que la sigue."""
    out, pending = [], []
    for line in open(lst):
        m = re.match(r"\s+([A-Za-z_]\w*):", line)
        if m and m.group(1) in SECTIONS:
            pending.append(m.group(1))
        a = re.match(r"([0-9a-fA-F]{8})\s+[0-9a-fA-F]{8}", line)
        if a and pending:
            out += [(int(a.group(1), 16), name) for name in pending]
            pending = []
    return sorted(out)


def main(lst, prof):
    labels = label_addrs(lst)
    tot_c, tot_i, agg = 0, 0, {}
    for r in csv.DictReader(open(prof)):
        pc, c, i = int(r["pc"]), int(r["ciclos"]), int(r["instrucciones"])
        sec = None
        for a, name in labels:
            if a <= pc:
                sec = name
        sec = SECTIONS.get(sec, "inicio")
        a = agg.setdefault(sec, [0, 0])
        a[0] += c
        a[1] += i
    work = {k: v for k, v in agg.items() if not k.startswith("esperar")}
    tc = sum(v[0] for v in work.values())
    ti = sum(v[1] for v in work.values())
    print(f"{'seccion':32s} {'ciclos':>10s} {'% ciclos':>8s} {'instr.':>9s} {'CPI':>6s}")
    for k, (c, i) in sorted(work.items(), key=lambda kv: -kv[1][0]):
        print(f"{k:32s} {c:10d} {100 * c / tc:7.1f}% {i:9d} {c / max(i, 1):6.2f}")
    print(f"{'TOTAL (sin sondeo)':32s} {tc:10d} {100:7.1f}% {ti:9d} {tc / ti:6.2f}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
