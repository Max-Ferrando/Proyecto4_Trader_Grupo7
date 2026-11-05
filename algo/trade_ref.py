"""trade_ref.py - Modelo de referencia EXACTO de sw/trade.s.

Es el mismo algoritmo que strategies.SmaCross, pero escrito como lo ejecuta el
Espino: buffer circular de L precios, sumas moviles que se actualizan con una
suma y una resta, multiplicacion por constante con sumas repetidas y la
cantidad a comprar con un lazo de sumas (sin MUL, DIV ni shifts).

Uso:
  python3 algo/trade_ref.py serie.csv [-o decisiones.txt]
    -> escribe un byte de decision (hex) por tick y las metricas de la 3.1.
  python3 algo/trade_ref.py --check
    -> comprueba que coincide con strategies.SmaCross en todas las series.

Los parametros S, L, M deben ser los mismos .equ de sw/trade.s.
"""
import argparse
import sys

import market
import series
import strategies

S = 3          # ventana corta (ticks)
L = 10         # ventana larga (ticks), maximo 64
M = 1          # histeresis: margen en unidades de precio
FEE = market.FEE
CASH0 = market.CASH0


class TradeRef:
    def __init__(self, S=S, L=L, M=M, cash0=CASH0, fee=FEE):
        self.S, self.L, self.M, self.fee = S, L, M, fee
        self.cash, self.shares = cash0, 0       # s1, tp
        self.pending = 0                        # gp: ultimo byte escrito en DECISION
        self.buf = [0] * L                      # buffer circular en RAM
        self.idx = 0                            # a4 (en palabras aqui; en bytes en asm)
        self.count = 0                          # a5: precios recibidos, satura en L
        self.sum_s = self.sum_l = 0             # a2, a3
        self.want = 0                           # sp: 1 = quiero estar comprado

    def afford(self, p, qmax):
        """Mayor n <= qmax con fee + n*p <= caja. Devuelve (n, costo = fee + n*p)."""
        n, cost = 0, self.fee
        while n < qmax and cost + p <= self.cash:
            cost += p
            n += 1
        return n, cost

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
                self.cash += acc - self.fee
                self.shares -= n
        # 2) Ventanas moviles
        old_l = self.buf[self.idx]
        old_s = self.buf[(self.idx + self.L - self.S) % self.L]
        self.sum_l += p - old_l
        self.sum_s += p - old_s
        self.buf[self.idx] = p
        self.idx = (self.idx + 1) % self.L
        if self.count < self.L:
            self.count += 1
        # 3) Senal: L*sum_s - S*sum_l comparado con M*S*L
        if self.count == self.L:
            a = 0
            for _ in range(self.L):
                a += self.sum_s
            b = 0
            for _ in range(self.S):
                b += self.sum_l
            diff, thr = a - b, self.M * self.S * self.L
            if diff > thr:
                self.want = 1
            elif diff < -thr:
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
    bad = 0
    for key, prices in series.suite(seeds).items():
        a = market.run(prices, TradeRef())["decisions"]
        b = market.run(prices, strategies.SmaCross(S, L, M))["decisions"]
        if a != b:
            bad += 1
            print("DIFERENTE:", key)
    print(f"trade_ref == SmaCross en {len(series.suite(seeds)) - bad} de {len(series.suite(seeds))} series")
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
    bh = market.run(prices, market.BuyAndHold())
    hold = market.run(prices, market.Hold())
    if a.out:
        with open(a.out, "w") as fh:
            for b in res["decisions"]:
                fh.write(f"{b:02x}\n")
    for name, r in (("trade (SMA)", res), ("comprar y mantener", bh), ("no operar", hold)):
        print(f"{name:20s} final=${r['final']:>9,}  ordenes={r['orders']:4d}  comisiones=${r['fees']:>6,}  "
              f"MDD=${r['max_drawdown']:>7,} ({r['max_drawdown_pct']:.1f}%)")


if __name__ == "__main__":
    main()
