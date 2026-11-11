import itertools, math, sys
from statistics import mean, median
import market, series, strategies as st

class MR2(st.Base):
    """Reversion a la media con umbral de entrada y de salida separados."""
    def __init__(self, L=20, th_in=8, th_out=8, **kw):
        super().__init__(**kw); self.L, self.ti, self.to = L, th_in, th_out
    def signal(self):
        h = self.hist
        if len(h) < self.L: return 0
        d = self.L * h[-1] - sum(h[-self.L:])          # L*(p - media)
        if d < -self.ti * self.L: return 1
        if d > self.to * self.L: return -1
        return 0

prices = series.load_csv("../tb/practica.csv")
def segs(n): return [prices[i:i+n] for i in range(0, len(prices), n)]
S2, S5 = segs(2000), segs(5000)
rows = []
for L, ti, to in itertools.product([5, 8, 10, 15, 20, 30, 40, 60, 100], [3, 4, 5, 6, 8, 10, 12, 16], [-4, -2, 0, 2, 4, 6, 8, 12]):
    mk = lambda: MR2(L, ti, to)
    f = market.run(prices, mk())
    r2 = [market.run(s, mk())["final"] for s in S2]
    r5 = [market.run(s, mk())["final"] for s in S5]
    rows.append((f"MR L={L} in={ti} out={to}", f["final"], f["orders"], f["max_drawdown"], min(r2), mean(r2), sum(x > 10000 for x in r2), min(r5), mean(r5)))
rows.sort(key=lambda r: -(r[5] + r[8]) / 2)
print(f"{'config':24s} {'final':>7s} {'ord':>4s} {'MDD':>6s} | 2000: peor  media gana>10k | 5000: peor  media")
for r in rows[:25]:
    print(f"{r[0]:24s} {r[1]:7d} {r[2]:4d} {r[3]:6d} | {r[4]:6d} {r[5]:7.0f} {r[6]:3d}/10 | {r[7]:6d} {r[8]:7.0f}")
