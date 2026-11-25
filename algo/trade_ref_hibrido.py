"""trade_ref.py - Modelo de referencia EXACTO de sw/trade.s.

Algoritmo HIBRIDO (tendencia + reversion a la media), escrito como lo
ejecuta el Espino:
  * tendencia: cruce de medias S/L con margen M  -> estado "trend"
  * reversion: precio TIN bajo la media de LM precios -> estado "mr" (se apaga
    cuando el precio supera la media + TOUT)
  * quiero estar comprado si trend, o si mr y NO hay bajada fuerte
    (media corta mas de M2 bajo la larga).
Estructura: buffer circular de L precios, dos sumas moviles que se
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
LM = 60        # ventana de la reversion a la media (LM <= L)
TIN = 4        # entra si el precio esta TIN bajo la media LM
TOUT = 0       # sale si el precio esta TOUT sobre la media LM
M2 = 4         # bajada fuerte: media corta mas de M2 bajo la larga
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
        self.sum_m = 0                          # RAM (SUMM)
        self.trend = self.mr = 0                # RAM (STATE bit0, bit1)
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
        self.sum_m += p - self.buf[(self.idx + self.L - LM) % self.L]
        self.buf[self.idx] = p
        self.idx = (self.idx + 1) % self.L
        if self.count < self.L:
            self.count += 1
        # 3) senal
        if self.count == self.L:
            d = self.mul_const(p, LM) - self.sum_m
            if d < -TIN * LM:
                self.mr = 1
            elif d > TOUT * LM:
                self.mr = 0
            diff = self.mul_const(self.sum_s, self.L) - self.mul_const(self.sum_l, self.S)
            thr = self.M * self.S * self.L
            if diff > thr:
                self.trend = 1
            elif diff < -thr:
                self.trend = 0
            down = diff < -M2 * self.S * self.L
            self.want = 1 if (self.trend or (self.mr and not down)) else 0
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
    """Compara con una implementacion independiente (sumas directas sobre la historia)."""
    def simple(prices):
        out, hist, cash, sh, pend, trend, mr = [], [], CASH0, 0, 0, 0, 0
        for x in prices:
            cash, sh, _ = market.execute(pend, x, cash, sh, FEE)
            hist.append(x)
            want = 0
            if len(hist) >= L:
                diff = L * sum(hist[-S:]) - S * sum(hist[-L:])
                if diff > M * S * L: trend = 1
                elif diff < -M * S * L: trend = 0
                d = LM * x - sum(hist[-LM:])
                if d < -TIN * LM: mr = 1
                elif d > TOUT * LM: mr = 0
                want = trend or (mr and not diff < -M2 * S * L)
            if want:
                k = min(63, (cash - FEE) // x) if cash > FEE else 0
                pend = 0x40 | k if k > 0 else 0
            else:
                k = min(63, sh); pend = 0x80 | k if k > 0 else 0
            out.append(pend)
        return out
    suite = dict(series.suite(seeds))
    for name in ("practica.csv", "practica_meta.csv"):
        path = os.path.join(ROOT, "tb", name)
        if os.path.exists(path):
            suite[(name, 0)] = series.load_csv(path)
    bad = 0
    for key, prices in suite.items():
        if market.run(prices, TradeRef())["decisions"] != simple(prices):
            bad += 1
            print("DIFERENTE:", key)
    print(f"trade_ref == implementacion directa en {len(suite) - bad} de {len(suite)} series")
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
