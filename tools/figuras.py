"""figuras.py - Genera las figuras del informe en docs/ (requiere matplotlib).

  python3 tools/figuras.py
Lee tb/practica.csv, tb/practica_meta.csv y docs/mediciones/*.csv.
"""
import csv
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "algo"))
import market      # noqa: E402
import series      # noqa: E402
from trade_ref import TradeRef   # noqa: E402

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt   # noqa: E402

INK, MUTED, GRID = "#191919", "#666666", "#e3e3e3"
BLUE, ORANGE, AQUA, GRAY = "#257de0", "#f47230", "#00b894", "#9a9a9a"
plt.rcParams.update({"font.size": 8.5, "axes.edgecolor": MUTED, "axes.labelcolor": INK,
                     "xtick.color": MUTED, "ytick.color": MUTED, "font.family": "DejaVu Sans"})


def clean(ax):
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.grid(True, axis="y", color=GRID, lw=0.6)
    ax.set_axisbelow(True)


def miles(x, _):
    return f"{x:,.0f}".replace(",", ".")


def fig_patrimonio():
    from matplotlib.ticker import FuncFormatter
    fig, axs = plt.subplots(2, 2, figsize=(7.4, 4.7), dpi=170, sharex="col",
                            gridspec_kw={"height_ratios": [1, 1.6]})
    handles = None
    for j, (name, title) in enumerate((("practica", "practica.csv"), ("practica_meta", "practica_meta.csv"))):
        p = series.load_csv(os.path.join(ROOT, "tb", name + ".csv"))
        w = market.run(p, TradeRef())["wealth"]
        # Comprar y mantener como en tb_proyecto_4.sv: una compra de todo lo que alcanza al tick 0
        q0 = (market.CASH0 - market.FEE) // p[0]
        bh = [market.CASH0 - market.FEE - q0 * p[0] + q0 * px for px in p]
        x = range(len(p))
        a, b = axs[0][j], axs[1][j]
        a.plot(x, p, color=MUTED, lw=0.6)
        a.set_title(title, loc="left", fontsize=9.5, color=INK)
        a.set_ylabel("Precio (1 a 255)")
        clean(a)
        b.plot(x, bh, color=ORANGE, lw=1.0, label="Comprar y mantener")
        b.plot(x, w, color=BLUE, lw=1.2, label="Nuestro algoritmo")
        b.axhline(10000, color=GRAY, lw=1.0, ls=(0, (4, 3)), label="No operar")
        b.set_ylabel("Patrimonio ($)")
        b.set_xlabel("Tick")
        b.yaxis.set_major_formatter(FuncFormatter(miles))
        clean(b)
        b.set_xlim(-600, len(p) * 1.19)
        b.annotate(f"$ {miles(w[-1], 0)}", (len(p) - 1, w[-1]), xytext=(5, 0), textcoords="offset points",
                   ha="left", va="center", color=INK, fontsize=8.5, fontweight="bold")
        b.annotate(f"$ {miles(bh[-1], 0)}", (len(p) - 1, bh[-1]), xytext=(5, 0), textcoords="offset points",
                   ha="left", va="center", color=INK, fontsize=8.5)
        b.set_xticks([0, 5000, 10000, 15000, 20000])
        b.set_xticklabels(["0", "5.000", "10.000", "15.000", "20.000"])
        handles = b.get_legend_handles_labels()
    fig.tight_layout(rect=(0, 0.06, 1, 1))
    fig.legend(*handles, frameon=False, loc="lower center", ncol=3, fontsize=8.5)
    fig.savefig(os.path.join(ROOT, "docs", "fig_patrimonio.png"))
    plt.close(fig)


def fig_secciones():
    f = os.path.join(ROOT, "docs", "mediciones", "secciones_base.csv")
    rows = list(csv.DictReader(open(f)))
    rows.sort(key=lambda r: float(r["ciclos_por_tick"]))
    fig, ax = plt.subplots(figsize=(7.0, 2.6), dpi=170)
    y = range(len(rows))
    v = [float(r["ciclos_por_tick"]) for r in rows]
    ax.barh(list(y), v, color=BLUE, height=0.62)
    ax.set_yticks(list(y))
    ax.set_yticklabels([r["seccion"] for r in rows], color=INK)
    tot = sum(v)
    for i, x in enumerate(v):
        ax.text(x + 0.8, i, f"{x:.1f} ciclos ({100 * x / tot:.0f} %)".replace(".", ","), va="center", color=INK, fontsize=8)
    ax.set_xlabel("Ciclos por tick (promedio, variante solo software)")
    ax.set_xlim(0, max(v) * 1.32)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.tick_params(axis="y", length=0)
    ax.grid(True, axis="x", color=GRID, lw=0.6)
    ax.set_axisbelow(True)
    fig.tight_layout()
    fig.savefig(os.path.join(ROOT, "docs", "fig_secciones.png"))
    plt.close(fig)


def fig_variantes():
    rows = list(csv.DictReader(open(os.path.join(ROOT, "docs", "mediciones", "codiseno.csv"))))
    names = {"base": "Solo\nsoftware", "pc12": "PC de\n12 bits", "mavg": "Sumas\nen HW", "sig": "Señales\nen HW"}
    fig, axs = plt.subplots(1, 2, figsize=(7.2, 2.7), dpi=170)
    lab = [names[r["variante"]] for r in rows]
    for ax, key, title, fmt, lim in (
            (axs[0], "ciclos_prom", "Ciclos por tick (promedio)", "{:.0f}", None),
            (axs[1], "celdas", "Celdas lógicas usadas (de 1.280)", "{:.0f}", 1280)):
        v = [float(r[key]) for r in rows]
        ax.bar(range(len(v)), v, color=BLUE, width=0.58)
        for i, x in enumerate(v):
            ax.text(i, x * 0.5, miles(x, 0), ha="center", va="center", color="white", fontsize=9, fontweight="bold")
        ax.set_xticks(range(len(v)))
        ax.set_xticklabels(lab, color=INK, fontsize=8)
        ax.set_title(title, loc="left", fontsize=9.5, color=INK)
        ax.set_ylim(0, (lim * 1.22) if lim else max(v) * 1.14)
        if lim:
            ax.axhline(lim, color=MUTED, lw=1.0, ls=(0, (4, 3)))
            ax.text(len(v) - 0.5, lim * 1.09, "capacidad de la HX1K: 1.280", ha="right", color=MUTED, fontsize=8)
        clean(ax)
        ax.tick_params(axis="x", length=0)
    fig.tight_layout()
    fig.savefig(os.path.join(ROOT, "docs", "fig_variantes.png"))
    plt.close(fig)


if __name__ == "__main__":
    fig_patrimonio()
    for f in (fig_secciones, fig_variantes):
        try:
            f()
        except FileNotFoundError as e:
            print("falta", e.filename)
