"""tune_practica.py - Ajusta parametros con la serie de practica oficial.

Para no sobreajustar, la serie de 20.000 ticks se divide en 4 tramos de 5.000
(cada uno parte con $10.000 y 0 acciones, como una ronda nueva) y se exige
que la configuracion funcione bien en TODOS los tramos, no solo en la serie
completa. Ordena por el peor tramo y luego por el promedio.
"""
import itertools
import math
import sys
from statistics import mean

import market
import series
import strategies as st

prices = series.load_csv(sys.argv[1] if len(sys.argv) > 1 else "../tb/practica.csv")
SEG = 5000
segs = [prices[i:i + SEG] for i in range(0, len(prices), SEG)]

configs = []
for S, L in itertools.product([2, 3, 5, 8, 10, 15, 20, 30, 50], [10, 20, 30, 40, 60, 80, 100, 150, 200, 300]):
    if S < L:
        for m in (0, 1, 2, 3, 5, 8):
            configs.append((f"SMA S={S} L={L} M={m}", lambda S=S, L=L, m=m: st.SmaCross(S, L, m)))
for k in (5, 10, 20, 50, 100, 200):
    for th in (1, 2, 4, 8, 12):
        configs.append((f"MOM k={k} th={th}", lambda k=k, th=th: st.Momentum(k, th)))
for L in (10, 20, 50, 100, 200):
    for th in (1, 2, 4, 8):
        configs.append((f"MR L={L} th={th}", lambda L=L, th=th: st.MeanRevert(L, th)))
for L in (20, 50, 100, 200, 400):
    configs.append((f"BRK L={L}", lambda L=L: st.Breakout(L)))

def score(mk):
    full = market.run(prices, mk())
    seg = [market.run(s, mk())["final"] for s in segs]
    bh = [market.buy_and_hold_official(s) for s in segs]
    rel = [math.log(a / b) for a, b in zip(seg, bh)]
    return full, seg, bh, rel

rows = []
for name, mk in configs:
    full, seg, bh, rel = score(mk)
    rows.append((name, full["final"], full["orders"], full["fees"], full["max_drawdown"], seg, min(seg), mean(seg), rel))
rows.sort(key=lambda r: (-r[6], -r[7]))
print(f"B&H oficial serie completa: {market.buy_and_hold_official(prices)}   tramos B&H: {[market.buy_and_hold_official(s) for s in segs]}")
print(f"{'config':22s} {'final':>8s} {'ord':>5s} {'comis':>6s} {'MDD':>6s} | tramos (5000 ticks c/u)           | peor   media")
for r in rows[:30]:
    print(f"{r[0]:22s} {r[1]:8d} {r[2]:5d} {r[3]:6d} {r[4]:6d} | {' '.join(f'{x:7d}' for x in r[5])} | {r[6]:6d} {r[7]:7.0f}")
