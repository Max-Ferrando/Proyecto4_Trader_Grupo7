import itertools, math
from statistics import mean
import market, series, strategies as st
A = series.load_csv("../tb/practica.csv"); B = series.load_csv("../tb/practica_meta.csv")
segs = [s[i:i+2000] for s in (A, B) for i in range(0, 20000, 2000)]
cfg = []
for S, L in itertools.product([2,3,5,8,10,15,20,30,50], [10,20,30,40,60,80,100,150,200,300]):
    if S < L:
        for m in (0,1,2,3,5,8):
            cfg.append((f"SMA {S}/{L} M={m}", lambda S=S,L=L,m=m: st.SmaCross(S,L,m)))
for k, th in itertools.product((5,10,20,50,100,200),(1,2,4,8,12)):
    cfg.append((f"MOM k={k} th={th}", lambda k=k,th=th: st.Momentum(k,th)))
for L, ti, to in itertools.product((10,20,40,60,100,150),(2,3,4,5,6,8,10),(-2,0,2,4)):
    cfg.append((f"MR L={L} in={ti} out={to}", lambda L=L,ti=ti,to=to: st.MeanRevert2(L,ti,to)))
for L in (20,50,100,200,400):
    cfg.append((f"BRK L={L}", lambda L=L: st.Breakout(L)))
rows=[]
for name, mk in cfg:
    fa, fb = market.run(A, mk())["final"], market.run(B, mk())["final"]
    sg = [market.run(s, mk())["final"] for s in segs]
    geo = math.exp(mean([math.log(max(x,1)/10000) for x in [fa, fb] + sg]))
    rows.append((name, fa, fb, min(sg), sum(x>=10000 for x in sg), geo, min(fa, fb)))
print("Ordenado por media geometrica (2 series + 20 tramos):")
for r in sorted(rows, key=lambda r: -r[5])[:15]:
    print(f"{r[0]:26s} A={r[1]:7d} B={r[2]:7d} peor tramo={r[3]:6d} tramos>=10k={r[4]:2d}/20 geo={r[5]:.3f}")
print("\nOrdenado por la PEOR de las dos series completas:")
for r in sorted(rows, key=lambda r: -r[6])[:15]:
    print(f"{r[0]:26s} A={r[1]:7d} B={r[2]:7d} peor tramo={r[3]:6d} tramos>=10k={r[4]:2d}/20 geo={r[5]:.3f}")
