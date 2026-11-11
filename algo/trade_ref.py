"""trade_ref.py - Modelo de referencia EXACTO de sw/trade.s.

Algoritmo: reversion a la media (strategies.MeanRevert2) escrito como lo
ejecuta el Espino: buffer circular de L precios, suma movil actualizada con una
suma y una resta, L*p con duplicaciones (sin MUL ni shifts) y la cantidad a
comprar con un lazo de sumas.

Uso:
  python3 algo/trade_ref.py tb/practica.csv [-o decisiones.txt]
  python3 algo/trade_ref.py --check     (coincide con strategies.MeanRevert2)

Los parametros L, TIN, TOUT deben ser los mismos .equ de sw/trade.s.
"""
import argparse
import sys

import market
import series
import strategies

L = 60         # ventana de la media (ticks), maximo 64
TIN = 4        # comprar si el precio esta TIN unidades bajo la media
TOUT = 0       # vender si el precio esta TOUT unidades sobre la media
FEE = market.FEE
CASH0 = market.CASH0


class TradeRef:
    def __init__(self, L=L, tin=TIN, tout=TOUT, cash0=CASH0, fee=FEE):
        self.L, self.tin, self.tout, self.fee = L, tin, tout, fee
        self.cash, self.shares = cash0, 0       # s1, tp
        self.pending = 0                        # gp: ultimo byte escrito en DECISION
        self.buf = [0] * L                      # buffer circular en RAM
        self.idx = 0                            # a4
        self.count = 0                          # a5
        self.sum_l = 0                          # a3
        self.want = 0                           # sp

    def afford(self, p, qmax):
        """Mayor n <= qmax con fee + n*p <= caja. Devuelve (n, costo)."""
        n, cost = 0, self.fee
        while n < qmax and cost + p <= self.cash:
            cost += p
            n += 1
        return n, cost

    @staticmethod
    def mul_const(x, k):
        """x*k con duplicaciones: recorre los bits de k (8 bits) con una mascara."""
        acc, pw, mask = 0, x, 1
        while mask < 256:
            if k & mask:
                acc += pw
            pw += pw
            mask += mask
        return acc

    def step(self, p):
        # 1) La maestra ejecuto el byte anterior al precio p: copia propia
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
                for _ in range(n):           # n*p con sumas
                    acc += p
                if self.cash + acc >= self.fee:
                    self.cash += acc - self.fee
                    self.shares -= n
        # 2) Ventana movil
        self.sum_l += p - self.buf[self.idx]
        self.buf[self.idx] = p
        self.idx = (self.idx + 1) % self.L
        if self.count < self.L:
            self.count += 1
        # 3) Senal: d = L*p - suma
        if self.count == self.L:
            d = self.mul_const(p, self.L) - self.sum_l
            if d < -self.tin * self.L:
                self.want = 1
            elif d > self.tout * self.L:
                self.want = 0
        # 4) Cantidad
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
    suite[("practica", 0)] = series.load_csv("../tb/practica.csv") if __import__("os").path.exists("../tb/practica.csv") else series.load_csv("tb/practica.csv")
    bad = 0
    for key, prices in suite.items():
        a = market.run(prices, TradeRef())["decisions"]
        b = market.run(prices, strategies.MeanRevert2(L, TIN, TOUT))["decisions"]
        if a != b:
            bad += 1
            print("DIFERENTE:", key)
    print(f"trade_ref == MeanRevert2 en {len(suite) - bad} de {len(suite)} series")
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
