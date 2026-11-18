import market, series, strategies as st, statistics, math

class Meta(st.Base):
    """Sigue a la estrategia (MR o SMA) con mejor puntaje virtual.
    Puntaje de cada una: suma de (p[n]-p[n-1]) mientras esa estrategia 'quiere estar comprada',
    menos una penalizacion PEN por cada cambio de opinion (aproxima la comision)."""
    def __init__(self, mr=(60,4,0), sma=(20,120,8), pen=1, decay=None, **kw):
        super().__init__(**kw)
        self.a = st.MeanRevert2(*mr); self.b = st.SmaCross(*sma)
        self.wa = self.wb = -1; self.sa = self.sb = 0; self.pen = pen; self.prev = None; self.decay = decay
    def signal(self):
        p = self.hist[-1]
        if self.prev is not None:
            if self.wa > 0: self.sa += p - self.prev
            if self.wb > 0: self.sb += p - self.prev
        self.prev = p
        for strat, attr in ((self.a, "wa"), (self.b, "wb")):
            strat.hist = self.hist
            s = strat.signal()
            if s and s != getattr(self, attr):
                setattr(self, attr, s)
                if attr == "wa": self.sa -= self.pen
                else: self.sb -= self.pen
        w = self.wa if self.sa >= self.sb else self.wb
        return w

A = series.load_csv("../tb/practica.csv"); B = series.load_csv("../tb/practica_meta.csv")
for pen in (0, 1, 2, 4):
    out=[]
    for s in (A,B):
        r=market.run(s,Meta(pen=pen)); seg=[market.run(s[i:i+2000],Meta(pen=pen))["final"] for i in range(0,20000,2000)]
        out.append(f"final {r['final']:6d} ord {r['orders']:3d} MDD {r['max_drawdown']:5d} tramos>=10k {sum(x>=10000 for x in seg)}/10 peor {min(seg)}")
    print("pen",pen,"| A:",out[0],"| B:",out[1])
suite=series.suite(10)
fs=[market.run(p,Meta(pen=1))["final"] for p in suite.values()]; bh=[market.buy_and_hold_official(p) for p in suite.values()]
print("sinteticas meta: mediana",statistics.median(fs),"gana B&H",sum(a>b for a,b in zip(fs,bh)),"/70 gana 10k",sum(a>10000 for a in fs),"/70")
