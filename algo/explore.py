"""explore.py - Compara estrategias y parametros sobre muchas series sinteticas.

Uso:  python3 algo/explore.py [semillas]

Para cada configuracion corre todas las familias x semillas y reporta:
  * exceso medio sobre "comprar y mantener" (en % del patrimonio inicial),
  * exceso medio sobre "no operar" (= ganancia neta, en %),
  * peor caso, ordenes y drawdown medio.
"""
import sys
from statistics import mean

import market
import series
import strategies as st

CONFIGS = []
for S, L in [(3, 10), (5, 20), (5, 30), (8, 32), (10, 40), (4, 16), (2, 8), (3, 15)]:
    for m in (0, 1, 2):
        CONFIGS.append((f"SMA S={S} L={L} m={m}", lambda S=S, L=L, m=m: st.SmaCross(S, L, m)))
for k in (5, 10, 20, 40):
    for th in (0, 2, 5, 10):
        CONFIGS.append((f"MOM k={k} th={th}", lambda k=k, th=th: st.Momentum(k, th)))
for L in (10, 20, 40):
    for th in (2, 5, 10):
        CONFIGS.append((f"MR L={L} th={th}", lambda L=L, th=th: st.MeanRevert(L, th)))
for L in (10, 20, 40, 80):
    CONFIGS.append((f"BRK L={L}", lambda L=L: st.Breakout(L)))
for ks, kl in [(2, 5), (3, 6), (2, 6), (1, 4), (3, 5)]:
    for m in (0, 1):
        CONFIGS.append((f"EMA ks={ks} kl={kl} m={m}", lambda ks=ks, kl=kl, m=m: st.EmaCross(ks, kl, m)))


def evaluate(make_bot, suite, refs):
    rows = []
    for key, prices in suite.items():
        r = market.run(prices, make_bot())
        bh = refs[key]
        rows.append((key[0], r["final"], bh, r["orders"], r["max_drawdown_pct"]))
    return rows


def summarize(rows):
    import math
    lg_bh = [math.log(max(f, 1) / max(bh, 1)) for _, f, bh, _, _ in rows]
    lg = [math.log(max(f, 1) / market.CASH0) for _, f, _, _, _ in rows]
    ex_bh = [100 * (f - bh) / market.CASH0 for _, f, bh, _, _ in rows]
    gain = [100 * (f - market.CASH0) / market.CASH0 for _, f, _, _, _ in rows]
    by_fam = {}
    for (fam, f, bh, _, _), e in zip(rows, ex_bh):
        by_fam.setdefault(fam, []).append(e)
    by_fam_lg = {}
    for (fam, *_), v in zip(rows, lg_bh):
        by_fam_lg.setdefault(fam, []).append(v)
    return {
        "geo_bh": 100 * (math.exp(mean(lg_bh)) - 1),
        "geo": 100 * (math.exp(mean(lg)) - 1),
        "fam_geo": {k: 100 * (math.exp(mean(v)) - 1) for k, v in by_fam_lg.items()},
        "ex_bh": mean(ex_bh),
        "gain": mean(gain),
        "worst_gain": min(gain),
        "beats_bh": sum(e > 0 for e in ex_bh) / len(ex_bh),
        "orders": mean(r[3] for r in rows),
        "mdd": mean(r[4] for r in rows),
        "fam": {k: mean(v) for k, v in by_fam.items()},
    }


def main():
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    suite = series.suite(seeds)
    refs = {k: market.run(p, market.BuyAndHold())["final"] for k, p in suite.items()}
    fams = list(series.FAMILIES)
    results = []
    for name, mk in CONFIGS:
        results.append((name, summarize(evaluate(mk, suite, refs))))
    results.sort(key=lambda x: -x[1]["geo_bh"])
    hdr = f"{'config':24s} {'geo%':>7s} {'geo/B&H%':>8s} {'peor%':>7s} {'gana B&H':>8s} {'ordenes':>7s} {'MDD%':>6s} | " + " ".join(f"{f[:8]:>8s}" for f in fams)
    print(hdr)
    for name, s in results[:20] + [r for r in results[20:] if r[0].startswith(('EMA','MR'))][:6]:
        print(f"{name:24s} {s['geo']:7.1f} {s['geo_bh']:8.1f} {s['worst_gain']:7.1f} {100*s['beats_bh']:7.0f}% {s['orders']:7.0f} {s['mdd']:6.1f} | "
              + " ".join(f"{s['fam_geo'][f]:8.1f}" for f in fams))
    bh_gain = mean(100 * (v - market.CASH0) / market.CASH0 for v in refs.values())
    print(f"\nComprar y mantener: ganancia media {bh_gain:.1f}%  |  No operar: 0%")
    fam_bh = {f: mean(100 * (refs[k] - market.CASH0) / market.CASH0 for k in refs if k[0] == f) for f in fams}
    print("B&H por familia (ganancia %): " + "  ".join(f"{f}={v:.1f}" for f, v in fam_bh.items()))


if __name__ == "__main__":
    main()
