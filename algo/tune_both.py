"""tune_both.py - Ajuste con las DOS series de practica oficiales.

Variantes de reversion a la media (todas enteras):
  base : compra si p < media_L - TIN, vende si p > media_L + TOUT
  trend: ademas solo compra si la media larga (L2) no viene bajando:
         media_L >= media_L2 - TT   (comparando sumas escaladas)
  stop : si p < precio_de_entrada - SL, vende y no vuelve a comprar hasta
         que el precio cruce sobre la media.
Puntaje: media geometrica del patrimonio final en las 2 series completas y en
sus 20 tramos de 2.000 ticks (cada tramo parte con $10.000).
"""
import itertools, math, sys
from statistics import mean
import market, series, strategies as st

class MRX(st.Base):
    def __init__(self, L=60, tin=4, tout=0, L2=0, tt=0, sl=0, **kw):
        super().__init__(**kw)
        self.L, self.ti, self.to, self.L2, self.tt, self.sl = L, tin, tout, L2, tt, sl
        self.entry = None; self.blocked = False
    def signal(self):
        h = self.hist; L = self.L
        need = max(L, self.L2)
        if len(h) < need: return 0
        p = h[-1]
        sL = sum(h[-L:])
        d = L * p - sL
        if self.sl and self.want > 0 and self.entry is not None and p < self.entry - self.sl:
            self.blocked = True; self.entry = None
            return -1
        if self.blocked:
            if d > 0: self.blocked = False
            return -1 if self.want > 0 else 0
        if d < -self.ti * L:
            if self.L2:
                sL2 = sum(h[-self.L2:])
                # media_L >= media_L2 - tt  <=>  L2*sL >= L*sL2 - tt*L*L2
                if self.L2 * sL < L * sL2 - self.tt * L * self.L2:
                    return 0
            if self.want <= 0: self.entry = p
            return 1
        if d > self.to * L:
            self.entry = None
            return -1
        return 0

A = series.load_csv("../tb/practica.csv"); B = series.load_csv("../tb/practica_meta.csv")
segs = [s[i:i+2000] for s in (A, B) for i in range(0, 20000, 2000)]
def evaluate(mk):
    fa, fb = market.run(A, mk())["final"], market.run(B, mk())["final"]
    sg = [market.run(s, mk())["final"] for s in segs]
    geo = math.exp(mean([math.log(x/10000) for x in [fa, fb] + sg]))
    return fa, fb, min(sg), sum(x >= 10000 for x in sg), geo

configs = [("base L=60 in=4", dict(L=60, tin=4))]
for L, ti in [(60,4),(60,5),(40,4),(100,4),(60,6)]:
    for L2, tt in itertools.product([120, 200, 250], [0, 2, 5]):
        configs.append((f"trend L={L} in={ti} L2={L2} tt={tt}", dict(L=L, tin=ti, L2=L2, tt=tt)))
    for sl in (5, 8, 12, 20):
        configs.append((f"stop L={L} in={ti} SL={sl}", dict(L=L, tin=ti, sl=sl)))
rows = []
for name, kw in configs:
    rows.append((name,) + evaluate(lambda kw=kw: MRX(**kw)))
rows.sort(key=lambda r: -r[5])
print(f"{'config':34s} {'serie A':>8s} {'serie B':>8s} {'peor tramo':>10s} {'tramos>=10k':>11s} {'geo':>6s}")
for r in rows[:20]:
    print(f"{r[0]:34s} {r[1]:8d} {r[2]:8d} {r[3]:10d} {r[4]:8d}/20 {r[5]:6.3f}")
base = [r for r in rows if r[0].startswith("base")][0]
print("BASE:", base)
