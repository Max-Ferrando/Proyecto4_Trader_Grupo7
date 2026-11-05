"""market.py - Simulador de la FPGA maestra del Proyecto 4 (Pochoco Trader).

Reproduce las reglas del enunciado (secciones 2.2 a 2.4):

  * En la transaccion n la maestra envia el precio p[n] y, en la MISMA
    transaccion, lee el byte que estaba en DECISION cuando bajo CS_n. Ese byte
    es la respuesta del grupo al precio ANTERIOR p[n-1]; la maestra lo ejecuta
    al precio p[n]. En la transaccion 0 DECISION vale 0 (mantener).
  * Si el programa no alcanzo a escribir una nueva decision, se ejecuta otra
    vez la anterior (aqui se modela con `late`, una lista de ticks atrasados).
  * Byte de decision: bits [7:6] accion (00 mantener, 01 comprar, 10 vender,
    11 = mantener), bits [5:0] cantidad q (0..63).
  * Compra: cuesta q*p + C. Si la caja no alcanza se compra el maximo posible.
  * Venta: entrega q*p - C y no puede superar las acciones que se tienen.
  * Patrimonio W[n] = caja[n] + acciones[n] * p[n].

Supuestos (el enunciado no los fija; se cambian aqui si la maestra oficial
hace otra cosa):
  * Una orden que termina con 0 acciones (q = 0, sin caja o sin acciones) no
    se ejecuta y no paga comision.
  * Una venta mayor que las acciones disponibles vende todas las disponibles.
  * Una compra solo se ejecuta si la caja alcanza para al menos 1 accion mas
    la comision.
"""

CASH0 = 10_000
FEE = 5

HOLD, BUY, SELL = 0, 1, 2


def encode(action, q):
    return ((action & 3) << 6) | (q & 63)


def decode(byte):
    action = (byte >> 6) & 3
    if action == 3:
        action = HOLD
    return action, byte & 63


def execute(byte, price, cash, shares, fee=FEE):
    """Ejecuta un byte de decision al precio dado. Devuelve (caja, acciones, ejecutada)."""
    action, q = decode(byte)
    if action == BUY and q > 0:
        afford = (cash - fee) // price if cash > fee else 0
        q = min(q, afford)
        if q > 0:
            return cash - q * price - fee, shares + q, True
    elif action == SELL and q > 0:
        q = min(q, shares)
        if q > 0:
            return cash + q * price - fee, shares - q, True
    return cash, shares, False


def run(prices, bot, cash0=CASH0, fee=FEE, late=()):
    """Corre un bot contra la serie. `bot` es un objeto con step(p) -> byte.

    Devuelve un dict con la historia y las metricas pedidas en la seccion 3.1.
    """
    late = set(late)
    cash, shares = cash0, 0
    decision = 0                  # DECISION al reiniciar: mantener
    orders = 0
    fees = 0
    wealth = []
    bytes_out = []
    for n, p in enumerate(prices):
        # Transaccion n: la maestra ejecuta el byte que estaba en DECISION
        cash, shares, done = execute(decision, p, cash, shares, fee)
        if done:
            orders += 1
            fees += fee
        wealth.append(cash + shares * p)
        # El programa recibe p[n] y escribe la nueva decision (si llega a tiempo)
        new = bot.step(p)
        bytes_out.append(new)
        if n not in late:
            decision = new
    peak, mdd, mdd_pct = wealth[0], 0, 0.0
    for w in wealth:
        peak = max(peak, w)
        mdd = max(mdd, peak - w)
        mdd_pct = max(mdd_pct, (peak - w) / peak)
    return {
        "final": wealth[-1],
        "orders": orders,
        "fees": fees,
        "max_drawdown": mdd,
        "max_drawdown_pct": 100 * mdd_pct,
        "wealth": wealth,
        "decisions": bytes_out,
        "shares": shares,
        "cash": cash,
    }


class Hold:
    """Referencia 1: no operar."""
    def step(self, p):
        return 0


class BuyAndHold:
    """Referencia 2: comprar al inicio (todo lo que alcance) y mantener.

    Como cada orden tiene a lo mas 63 acciones, compra 63 por tick hasta que
    la caja ya no alcance para una accion mas la comision.
    """
    def __init__(self, cash0=CASH0, fee=FEE):
        self.cash, self.shares, self.fee = cash0, 0, fee
        self.pending = 0

    def step(self, p):
        # Aplica la orden anterior al precio p (copia de la contabilidad)
        self.cash, self.shares, _ = execute(self.pending, p, self.cash, self.shares, self.fee)
        q = min(63, (self.cash - self.fee) // p) if self.cash > self.fee else 0
        self.pending = encode(BUY, q) if q > 0 else 0
        return self.pending
