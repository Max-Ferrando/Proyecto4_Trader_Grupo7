"""codiseno.py - Tabla comparativa de las variantes de co-diseno y roofline.

Lee, para cada variante:
  docs/mediciones/<variante>_<serie>_perfil.csv     perfil por tick (make check)
  docs/mediciones/<variante>_<serie>_perfil_pc.csv  perfil por PC
  docs/mediciones/sintesis.csv                      LUT4, celdas, BRAM y Fmax
  sw/<programa>.hex                                 para clasificar instrucciones
y escribe docs/mediciones/codiseno.csv, docs/mediciones/roofline.csv y, si hay
matplotlib, docs/roofline.png y docs/amdahl.png.

Definiciones:
  operacion util (Ops/s de decision) = una decision por tick
        Ops/s = f_clk / ciclos por tick (tasa maxima sostenible de decisiones)
  roofline: W = instrucciones que no acceden a memoria (aritmetica, logica,
        comparaciones y saltos); Q = bytes movidos por lw/sw (4 por acceso)
        intensidad I = W / Q; rendimiento P = W / tiempo
        techo de computo  = f_clk / 2          (una instruccion ALU = 2 ciclos)
        techo de memoria  = (4 bytes * f_clk / 3) * I   (un lw = 3 ciclos)
"""
import csv
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
MED = os.path.join(ROOT, "docs", "mediciones")
F_CLK = 25e6
VARIANTS = [  # nombre, programa, descripcion
    ("base", "trade", "Solo software (core original)"),
    ("pc12", "trade", "PC de 12 bits"),
    ("mavg", "trade_mavg", "PC12 + sumas moviles en HW"),
    ("sig", "trade_sig", "PC12 + senales en HW"),
]
SERIES = ["practica", "practica_meta"]
# Estimacion previa (antes de medir) de la aceleracion local de cada seccion,
# en ciclos, con 2 ciclos por instruccion ALU/sw y 3 por lw o salto tomado.
#   update en software: ~22 instr. (4 lw, 2 sw)  ~ 50 ciclos
#   mavg: 1 sw + 3 lw = 11 ciclos                 -> s = 50/11
#   sig : ademas reemplaza las cadenas 60p y 6*s20 (13 instr. ~ 27 ciclos)
#         update+cadenas ~ 77 ciclos por 1 sw + 2 lw = 8 ciclos
PRED = {"mavg": (("ventanas",), 50 / 11.0), "sig": (("ventanas", "cadenas"), 77 / 8.0)}


def load_prog(prog):
    words = [int(x, 16) for x in open(os.path.join(ROOT, "sw", prog + ".hex")).read().split()]
    return words


def labels(prog):
    import re
    out = {}
    pend = []
    for line in open(os.path.join(ROOT, "sw", prog + ".lst")):
        m = re.match(r"\s+([A-Za-z_]\w*):", line)
        if m:
            pend.append(m.group(1))
        a = re.match(r"([0-9a-fA-F]{8})\s+[0-9a-fA-F]{8}", line)
        if a and pend:
            for p in pend:
                out[p] = int(a.group(1), 16)
            pend = []
    return out


def measure(var, prog):
    words = load_prog(prog)
    lab = labels(prog)
    # El lazo de sondeo (wait .. lw PRICE) queda fuera del kernel. El perfil por
    # PC cuenta en "lw PRICE" los ciclos de las instrucciones descartadas tras
    # cada salto del sondeo, asi que esa instruccion se agrega aparte: se
    # ejecuta una vez por tick y tarda 3 ciclos.
    wait_lo, wait_hi = lab["wait"], lab["update"]
    names = [("update", "Ventanas móviles"), ("signal", "Señal de reversión"),
             ("mr_done", "Señal de tendencia"), ("risk", "Stop, cooldown y entrada"),
             ("decide", "Filtro de saltos y decisión"), ("out", "DECISION, display y LEDs")]
    starts = sorted((lab[k], n) for k, n in names)
    res = {"ticks": 0, "ic": 0, "cyc": 0, "worst": 0, "worst_ic": 0,
           "W": 0, "mem": 0, "kc": 0, "sec": {}, "named": {}}
    for s in SERIES:
        f = os.path.join(MED, f"{var}_{s}_perfil.csv")
        if not os.path.exists(f):
            continue
        rows = [r for r in csv.DictReader(open(f)) if int(r["tick"]) > 0]
        res["ticks"] += len(rows)
        res["ic"] += sum(int(r["ic_tick"]) for r in rows)
        res["cyc"] += sum(int(r["ciclos_tick"]) for r in rows)
        for r in rows:
            if int(r["ciclos_tick"]) > res["worst"]:
                res["worst"], res["worst_ic"] = int(r["ciclos_tick"]), int(r["ic_tick"])
        res["kc"] += 3 * len(rows)
        res["mem"] += len(rows)
        res["named"]["Leer PRICE"] = res["named"].get("Leer PRICE", 0) + 3 * len(rows)
        for r in csv.DictReader(open(os.path.join(MED, f"{var}_{s}_perfil_pc.csv"))):
            pc, c, i = int(r["pc"]), int(r["ciclos"]), int(r["instrucciones"])
            if pc < lab["wait"] or wait_lo <= pc < wait_hi:
                continue                                   # inicio y sondeo: fuera del kernel
            op = words[pc // 4] & 0x7F if pc // 4 < len(words) else 0
            res["kc"] += c
            if op in (0x03, 0x23):
                res["mem"] += i
            else:
                res["W"] += i
            nm = [n for a, n in starts if a <= pc][-1]
            res["named"][nm] = res["named"].get(nm, 0) + c
            # secciones para Amdahl (sobre el programa base)
            if prog == "trade":
                if lab["update"] <= pc < lab["idx_ok"]:
                    k = "ventanas"
                elif lab["signal"] <= pc < lab["signal"] + 9 * 4 or lab["mr_done"] <= pc < lab["mr_done"] + 4 * 4:
                    k = "cadenas"                          # 60p, lw SUMM, sub y 6*s20 - s120
                else:
                    k = "resto"
                res["sec"][k] = res["sec"].get(k, 0) + c
    return res


def main():
    syn = {r["variante"]: r for r in csv.DictReader(open(os.path.join(MED, "sintesis.csv")))}
    out, roof = [], []
    base = None
    for var, prog, desc in VARIANTS:
        m = measure(var, prog)
        if not m["ticks"]:
            continue
        cyc, ic = m["cyc"] / m["ticks"], m["ic"] / m["ticks"]
        row = {"variante": var, "descripcion": desc, "ticks": m["ticks"],
               "ic_prom": round(ic, 1), "ciclos_prom": round(cyc, 1), "cpi": round(cyc / ic, 3),
               "ciclos_peor": m["worst"], "t_prom_us": round(1e6 * cyc / F_CLK, 2),
               "t_peor_us": round(1e6 * m["worst"] / F_CLK, 2),
               "ops_s": round(F_CLK / cyc), "ops_s_peor": round(F_CLK / m["worst"])}
        row.update({k: syn[var][k] for k in ("lut4", "celdas", "bram", "fmax_mhz")} if var in syn else {})
        if var == "base":
            base = (cyc, m)
        row["speedup"] = round(base[0] / cyc, 3)
        if var in PRED:
            secs, s = PRED[var]
            tot = sum(base[1]["sec"].values())
            # fraccion sobre los ciclos del tick completo (incluye el sondeo final)
            f = sum(base[1]["sec"].get(k, 0) for k in secs) / base[1]["ticks"] / base[0]
            row["amdahl_f"] = round(f, 3)
            row["amdahl_pred"] = round(1 / ((1 - f) + f / s), 3)
            row["amdahl_max"] = round(1 / (1 - f), 3)
        out.append(row)
        W, Q, kc = m["W"] / m["ticks"], 4 * m["mem"] / m["ticks"], m["kc"] / m["ticks"]
        inten = W / Q
        perf = W / (kc / F_CLK)
        roof.append({"variante": var, "W_ops": round(W, 1), "Q_bytes": round(Q, 1),
                     "intensidad": round(inten, 3), "rendimiento_Mops_s": round(perf / 1e6, 2),
                     "techo_Mops_s": round(min(F_CLK / 2, 4 * F_CLK / 3 * inten) / 1e6, 2),
                     "ciclos_kernel": round(kc, 1)})
    keys = []
    for r in out:
        keys += [k for k in r if k not in keys]
    with open(os.path.join(MED, "codiseno.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=keys)
        w.writeheader()
        w.writerows(out)
    with open(os.path.join(MED, "roofline.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(roof[0]))
        w.writeheader()
        w.writerows(roof)
    for r in out:
        print(r)
    for r in roof:
        print(r)
    with open(os.path.join(MED, "secciones_base.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["seccion", "ciclos_por_tick"])
        for k, v in base[1]["named"].items():
            w.writerow([k, round(v / base[1]["ticks"], 2)])
    if base:
        tot = sum(base[1]["sec"].values())
        print("secciones base (ciclos por tick):",
              {k: round(v / base[1]["ticks"], 1) for k, v in base[1]["sec"].items()})
    try:
        plot(out, roof)
    except ImportError:
        print("(sin matplotlib: no se generan los graficos)")


def plot(out, roof):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    ink, muted, grid = "#191919", "#666666", "#e3e3e3"
    cols = {"base": "#257de0", "mavg": "#f47230", "sig": "#00b894"}
    names = {"base": "Solo software", "mavg": "Sumas en HW", "sig": "Señales en HW"}
    offs = {"base": (10, 12), "mavg": (10, -4), "sig": (-10, -16)}
    plt.rcParams.update({"font.size": 8.5, "font.family": "DejaVu Sans"})
    fig, ax = plt.subplots(figsize=(7.0, 3.9), dpi=170)
    xs = [10 ** (k / 60.0 - 1.4) for k in range(0, 171)]
    ax.plot(xs, [min(F_CLK / 2, 4 * F_CLK / 3 * x) / 1e6 for x in xs], color=ink, lw=2)
    knee = (F_CLK / 2) / (4 * F_CLK / 3)
    ax.axvline(knee, color=muted, lw=0.9, ls=(0, (4, 3)))
    ax.text(knee * 0.93, 0.62, "I = 0,375", rotation=90, fontsize=8, color=muted, ha="right", va="bottom")
    ax.text(0.046, 4.6, "techo de memoria:\n33,3 MB/s × I\n(un lw = 3 ciclos)", fontsize=8, color=ink, ha="left")
    ax.text(26, 14.2, "techo de cómputo: 12,5 Mops/s (una instrucción ALU = 2 ciclos)", fontsize=8, color=ink, ha="right")
    mk = {"base": ("o", 110), "mavg": ("s", 34), "sig": ("^", 60)}
    for r in roof:
        v = r["variante"]
        if v not in cols:
            continue
        ax.scatter([r["intensidad"]], [r["rendimiento_Mops_s"]], s=mk[v][1], marker=mk[v][0],
                   color=cols[v], zorder=3 + list(cols).index(v), edgecolor="white", linewidth=1.2,
                   label=f'{names[v]}: {r["rendimiento_Mops_s"]:.1f} Mops/s con I = {r["intensidad"]:.2f}'.replace(".", ","))
    ax.legend(frameon=False, fontsize=8.5, loc="lower right", title="Kernel de decisión (medido)",
              title_fontsize=8.5, alignment="left")
    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_xlim(0.04, 30); ax.set_ylim(0.5, 22)
    ax.set_xticks([0.1, 1, 10]); ax.set_xticklabels(["0,1", "1", "10"])
    ax.set_yticks([1, 2, 5, 10, 20]); ax.set_yticklabels(["1", "2", "5", "10", "20"])
    ax.minorticks_off()
    ax.set_xlabel("Intensidad operacional I (operaciones por byte de memoria)", color=ink)
    ax.set_ylabel("Rendimiento (Mops/s)", color=ink)
    ax.grid(True, which="major", color=grid, lw=0.6)
    ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    fig.tight_layout()
    fig.savefig(os.path.join(ROOT, "docs", "roofline.png"))


if __name__ == "__main__":
    main()
