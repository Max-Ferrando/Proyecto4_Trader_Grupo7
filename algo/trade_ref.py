"""trade_ref.py - Modelo de referencia EXACTO de sw/trade.s.

Algoritmo: cruce de medias moviles (strategies.SmaCross) escrito como lo
ejecuta el Espino: buffer circular de L precios, dos sumas moviles que se
actualizan con una suma y una resta, multiplicacion por constante con
duplicaciones (sin MUL ni shifts) y la cantidad con un lazo de sumas.

Parametros elegidos con las DOS series de practica oficiales
(tb/practica.csv y tb/practica_meta.csv; ver algo/tune_all2.py).

Uso:
  python3 algo/trade_ref.py tb/practica.csv [-o decisiones.txt]
  python3 algo/trade_ref.py --check     (coincide con strategies.SmaCross)
"""
import argparse
import os
import sys

import market
import series
import strategies

S = 20         # ventana corta (ticks)
L = 120        # ventana larga (ticks), maximo 120 (buffer de 0x600 a 0x7DF)
M = 8          # histeresis: margen en unidades de precio
FEE = market.FEE
CASH0 = market.CASH0
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


class TradeRef:
    def __init__(self, S=S, L=L, M=M, cash0=CASH0, fee=FEE):
        self.S, self.L, self.M, self.fee = S, L, M, fee
        self.cash, self.shares = cash0, 0       # s1, tp
        self.pending = 0                        # gp
        self.buf = [0] * L                      # buffer circular en RAM
        self.idx = 0                            # a4
        self.count = 0                          # a5
        self.sum_s = self.sum_l = 0             # a2, a3
        self.want = 0                           # sp

    def afford(self, p, qmax):
        n, cost = 0, self.fee
        while n < qmax and cost + p <= self.cash:
            cost += p
            n += 1
        return n, cost

    @staticmethod
    def mul_const(x, k):
        """x*k con duplicaciones: recorre los 8 bits de k con una mascara."""
        acc, pw, mask = 0, x, 1
        while mask < 256:
            if k & mask:
                acc += pw
            pw += pw
            mask += mask
        return acc

    def step(self, p):
        # 1) orden pendiente ejecutada por la maestra al precio p
        action, q = self.pending >> 6, self.pending & 63
        if action == 1 and q:
            n, cost = self.afford(p, q)
            if n:
                self.cash -= cost
                self.shares += n
        elif action == 2 and q:
            n = min(q, self.shares)
            if n:
                acc = 0
                for _ in range(n):
                    acc += p
                if self.cash + acc >= self.fee:
                    self.cash += acc - self.fee
                    self.shares -= n
        # 2) ventanas moviles
        old_l = self.buf[self.idx]
        old_s = self.buf[(self.idx + self.L - self.S) % self.L]
        self.sum_l += p - old_l
        self.sum_s += p - old_s
        self.buf[self.idx] = p
        self.idx = (self.idx + 1) % self.L
        if self.count < self.L:
            self.count += 1
        # 3) senal: L*suma_corta - S*suma_larga contra M*S*L
        if self.count == self.L:
            diff = self.mul_const(self.sum_s, self.L) - self.mul_const(self.sum_l, self.S)
            thr = self.M * self.S * self.L
            if diff > thr:
                self.want = 1
            elif diff < -thr:
                self.want = 0
        # 4) cantidad
        if self.want:
            n, _ = self.afford(p, 63)
            byte = 0x40 | n if n else 0
        else:
            n = min(63, self.shares)
            byte = 0x80 | n if n else 0
        self.pending = byte
        return byte


def check(seeds=10):
    suite = dict(series.suite(seeds))
    for name in ("practica.csv", "practica_meta.csv"):
        path = os.path.join(ROOT, "tb", name)
        if os.path.exists(path):
            suite[(name, 0)] = series.load_csv(path)
    bad = 0
    for key, prices in suite.items():
        a = market.run(prices, TradeRef())["decisions"]
        b = market.run(prices, strategies.SmaCross(S, L, M))["decisions"]
        if a != b:
            bad += 1
            print("DIFERENTE:", key)
    print(f"trade_ref == SmaCross({S},{L},{M}) en {len(suite) - bad} de {len(suite)} series")
    return bad == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", nargs="?")
    ap.add_argument("-o", "--out")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.check:
        sys.exit(0 if check() else 1)
    prices = series.load_csv(a.csv)
    res = market.run(prices, TradeRef())
    hold = market.run(prices, market.Hold())
    if a.out:
        with open(a.out, "w") as fh:
            for b in res["decisions"]:
                fh.write(f"{b:02x}\n")
    print(f"{'trade.s':22s} final=${res['final']:>9,}  ordenes={res['orders']:4d}  comisiones=${res['fees']:>6,}  "
          f"perdida max=${res['max_drawdown']:>7,} ({res['max_drawdown_pct']:.1f}%)")
    print(f"{'comprar y mantener':22s} final=${market.buy_and_hold_official(prices):>9,}  (definicion del testbench oficial)")
    print(f"{'no operar':22s} final=${hold['final']:>9,}")


if __name__ == "__main__":
    main()
