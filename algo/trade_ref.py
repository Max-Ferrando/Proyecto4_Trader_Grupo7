"""Referencia causal del nuevo sw/trade.s (sin contabilidad duplicada)."""
import argparse
import os
import sys
import market
import series

S, L, LM = 20, 120, 60
ENTRY, EXIT, M2, TIN, STOP, COOL, SHOCK = 4, 2, 4, 4, 8, 64, 32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

class TradeRef:
    def __init__(self, entry=ENTRY, exit=EXIT, stop=STOP, cool=COOL, shock=SHOCK):
        self.entry, self.exit, self.stop, self.cool, self.shock = entry, exit, stop, cool, shock
        self.prev = None
        self.buf = [0]*L
        self.idx = self.count = self.ss = self.sl = self.sm = 0
        self.tr = self.mr = self.want = self.peak = self.lock = 0

    def step(self, p):
        shock = self.shock and self.prev is not None and abs(p-self.prev)>=self.shock
        self.prev = p
        i, b = self.idx, self.buf
        self.ss += p - b[(i+L-S)%L]
        self.sl += p - b[i]
        self.sm += p - b[(i+L-LM)%L]
        b[i] = p
        self.idx = (i+1)%L
        self.count = min(L, self.count+1)
        if self.count < L:
            return 0
        d = 6*self.ss - self.sl
        dm = LM*p - self.sm
        if d > self.entry*L: self.tr = 1
        elif d < -self.exit*L: self.tr = 0
        if dm < -TIN*LM: self.mr = 1
        elif dm > 0: self.mr = 0
        want = bool(self.tr or (self.mr and d >= -M2*L))
        if self.stop:
            self.lock = max(0, self.lock-1)
            if self.want:
                self.peak = max(self.peak, p)
                if self.peak-p >= self.stop:
                    self.lock = self.cool
                    self.tr = self.mr = 0
                    want = False
            if self.lock: want = False
            if want and not self.want: self.peak = p
        if shock:
            self.lock = self.cool
            self.tr = self.mr = 0
            want = False
        self.want = want
        return 0x7f if want else 0xbf

def check():
    # Referencia independiente sobre ventanas directas.
    def direct(prices):
        tr=mr=want=peak=lock=0
        out=[]
        for i,p in enumerate(prices):
            if i+1<L:
                out.append(0); continue
            d=120*sum(prices[i-S+1:i+1])-20*sum(prices[i-L+1:i+1])
            dm=LM*p-sum(prices[i-LM+1:i+1])
            if d>ENTRY*S*L: tr=1
            elif d<-EXIT*S*L: tr=0
            if dm<-TIN*LM: mr=1
            elif dm>0: mr=0
            target=bool(tr or (mr and d>=-M2*S*L))
            lock=max(0,lock-1)
            if want:
                peak=max(peak,p)
                if peak-p>=STOP: lock=COOL; tr=mr=0; target=False
            if lock: target=False
            if target and not want: peak=p
            if i and abs(p-prices[i-1])>=SHOCK: lock=COOL; tr=mr=0; target=False
            want=target
            out.append(127 if want else 191)
        return out
    cases=dict(series.suite(10))
    for f in ('practica.csv','practica_meta.csv','peor_caso.csv'):
        cases[(f,0)] = series.load_csv(os.path.join(ROOT,'tb',f))
    for k,p in cases.items():
        bot=TradeRef()
        assert [bot.step(x) for x in p]==direct(p),k
    print(f'Referencia incremental == ventanas directas: {len(cases)}/{len(cases)}')
    return True

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('csv',nargs='?'); ap.add_argument('-o','--out'); ap.add_argument('--check',action='store_true'); a=ap.parse_args()
    if a.check: sys.exit(0 if check() else 1)
    p=series.load_csv(a.csv); r=market.run(p,TradeRef())
    if a.out:
        with open(a.out,'w') as f: f.writelines(f'{x:02x}\n' for x in r['decisions'])
    print(f"trade.s final=${r['final']:,} ordenes={r['orders']} comisiones=${r['fees']:,} perdida maxima=${r['max_drawdown']:,} ({r['max_drawdown_pct']:.2f}%)")
    print(f"Comprar y mantener=${market.buy_and_hold_official(p):,}; no operar=${market.CASH0:,}")
if __name__=='__main__': main()
