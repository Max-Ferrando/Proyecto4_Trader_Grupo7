"""strategies.py - Estrategias candidatas, solo con aritmetica entera.

Todas comparten la misma estructura, que es la que tendra trade.s:

  1. Aplicar a la copia propia de la contabilidad la orden enviada en el tick
     anterior, al precio que acaba de llegar (asi se ejecuta en la maestra).
  2. Actualizar el estado (historia de precios, sumas moviles...).
  3. Calcular una SENAL: +1 quiero estar comprado, -1 quiero estar fuera,
     0 no cambio de opinion.
  4. Decidir la cantidad: con +1 compra todo lo que alcance (maximo 63 por
     orden); con -1 vende todo lo que tiene (maximo 63 por orden). Asi el
     algoritmo va "entrando" o "saliendo" en varios ticks si hace falta.

Los parametros son enteros y las comparaciones evitan la division: en vez de
comparar promedios sum_s/S y sum_l/L se compara L*sum_s con S*sum_l.
"""
from market import BUY, CASH0, FEE, SELL, encode, execute


class Base:
    MIN_BUY_VALUE = 0          # no comprar si q*p < este valor (evita ordenes chicas)

    def __init__(self, cash0=CASH0, fee=FEE):
        self.cash, self.shares, self.fee = cash0, 0, fee
        self.pending = 0
        self.hist = []          # precios recibidos
        self.want = -1          # empieza fuera del mercado

    def signal(self):
        raise NotImplementedError

    def step(self, p):
        self.cash, self.shares, _ = execute(self.pending, p, self.cash, self.shares, self.fee)
        self.hist.append(p)
        s = self.signal()
        if s:
            self.want = s
        byte = 0
        if self.want > 0:
            q = min(63, (self.cash - self.fee) // p) if self.cash > self.fee else 0
            if q > 0 and q * p >= self.MIN_BUY_VALUE:
                byte = encode(BUY, q)
        else:
            q = min(63, self.shares)
            if q > 0:
                byte = encode(SELL, q)
        self.pending = byte
        return byte


class SmaCross(Base):
    """Cruce de medias moviles: rapida (S) sobre lenta (L) = tendencia alcista."""
    def __init__(self, S=5, L=20, margin=0, **kw):
        super().__init__(**kw)
        self.S, self.L, self.m = S, L, margin

    def signal(self):
        h = self.hist
        if len(h) < self.L:
            return 0
        diff = self.L * sum(h[-self.S:]) - self.S * sum(h[-self.L:])   # (L*S)*(media_s - media_l)
        thr = self.m * self.S * self.L
        return 1 if diff > thr else (-1 if diff < -thr else 0)


class Momentum(Base):
    """Momentum: el precio subio mas de th en los ultimos k ticks."""
    def __init__(self, k=10, th=2, **kw):
        super().__init__(**kw)
        self.k, self.th = k, th

    def signal(self):
        h = self.hist
        if len(h) <= self.k:
            return 0
        d = h[-1] - h[-1 - self.k]
        return 1 if d > self.th else (-1 if d < -self.th else 0)


class MeanRevert(Base):
    """Reversion a la media: comprar barato respecto a la media, vender caro."""
    def __init__(self, L=20, th=4, **kw):
        super().__init__(**kw)
        self.L, self.th = L, th

    def signal(self):
        h = self.hist
        if len(h) < self.L:
            return 0
        d = self.L * h[-1] - sum(h[-self.L:])          # L*(p - media)
        thr = self.th * self.L
        return 1 if d < -thr else (-1 if d > thr else 0)


class Breakout(Base):
    """Canal de Donchian: rompe el maximo de L ticks = compra; rompe el minimo = vende."""
    def __init__(self, L=20, **kw):
        super().__init__(**kw)
        self.L = L

    def signal(self):
        h = self.hist
        if len(h) <= self.L:
            return 0
        win = h[-1 - self.L:-1]
        return 1 if h[-1] > max(win) else (-1 if h[-1] < min(win) else 0)


class EmaCross(Base):
    """Cruce de EMAs con alfa = 1/2^k (necesita desplazamientos: candidata a hardware).

    Las EMAs se guardan escaladas por 2^8 para no perder precision:
        E += (p*256 - E) >> k
    """
    def __init__(self, ks=2, kl=5, margin=0, **kw):
        super().__init__(**kw)
        self.ks, self.kl, self.m = ks, kl, margin
        self.es = self.el = None

    def signal(self):
        p = self.hist[-1] << 8
        if self.es is None:
            self.es = self.el = p
            return 0
        self.es += (p - self.es) >> self.ks
        self.el += (p - self.el) >> self.kl
        if len(self.hist) < (1 << self.kl):
            return 0
        d = self.es - self.el
        thr = self.m << 8
        return 1 if d > thr else (-1 if d < -thr else 0)


class MeanRevert2(Base):
    """Reversion a la media con umbrales de entrada y salida (algoritmo final).

    d = L*p - suma de los ultimos L precios  (= L * (p - media))
      d < -TIN*L  -> el precio cayo TIN bajo la media: quiero estar COMPRADO
      d >  TOUT*L -> el precio volvio sobre la media + TOUT: quiero estar FUERA
    """
    def __init__(self, L=60, tin=4, tout=0, **kw):
        super().__init__(**kw)
        self.L, self.ti, self.to = L, tin, tout

    def signal(self):
        h = self.hist
        if len(h) < self.L:
            return 0
        d = self.L * h[-1] - sum(h[-self.L:])
        if d < -self.ti * self.L:
            return 1
        if d > self.to * self.L:
            return -1
        return 0
