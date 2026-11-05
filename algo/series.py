"""series.py - Series de precios sinteticas mientras se publica la serie oficial.

La serie oficial y las tres series de evaluacion son desconocidas, asi que el
algoritmo se elige con varias FAMILIAS de series y muchas semillas, buscando
uno que funcione bien en promedio y que no pierda mucho en ninguna.

Todas se normalizan como dice el enunciado: enteros entre 1 y 255. Se usa una
normalizacion min-max sobre la serie completa (suponemos que la maestra hace
algo parecido con una accion real).
"""
import math
import random

N_TICKS = 1000


def normalize(xs, lo=1, hi=255, margin=0.05):
    a, b = min(xs), max(xs)
    span = (b - a) or 1.0
    # pequeno margen para no pegarse a 1 y 255
    return [max(lo, min(hi, round(lo + (hi - lo) * (margin + (1 - 2 * margin) * (x - a) / span))))
            for x in xs]


def gbm(rng, n, mu, sigma, x0=100.0):
    xs, x = [], x0
    for _ in range(n):
        x *= math.exp(mu - 0.5 * sigma * sigma + sigma * rng.gauss(0, 1))
        xs.append(x)
    return xs


def regimes(rng, n, sigma=0.012):
    """Tendencias alternadas (alcista/bajista) de largo aleatorio."""
    xs, x, left, mu = [], 100.0, 0, 0.0
    for _ in range(n):
        if left == 0:
            left = rng.randint(60, 250)
            mu = rng.choice([-1, 1]) * rng.uniform(0.002, 0.006)
        x *= math.exp(mu + sigma * rng.gauss(0, 1))
        xs.append(x)
        left -= 1
    return xs


def ou(rng, n, theta=0.05, sigma=2.0, mean=100.0):
    """Reversion a la media (Ornstein-Uhlenbeck)."""
    xs, x = [], mean
    for _ in range(n):
        x += theta * (mean - x) + sigma * rng.gauss(0, 1)
        xs.append(x)
    return xs


def cycles(rng, n):
    per = rng.uniform(80, 250)
    ph = rng.uniform(0, 2 * math.pi)
    return [100 + 30 * math.sin(2 * math.pi * i / per + ph) + rng.gauss(0, 3) for i in range(n)]


def bubble(rng, n):
    """Subida sostenida, crash y recuperacion lenta."""
    k = rng.randint(n // 3, 2 * n // 3)
    up = gbm(rng, k, 0.004, 0.01)
    down = gbm(rng, rng.randint(40, 120), -0.02, 0.02, up[-1])
    rest = gbm(rng, n - len(up) - len(down), 0.001, 0.012, down[-1])
    return up + down + rest


FAMILIES = {
    "paseo_aleatorio": lambda r, n: gbm(r, n, 0.0, 0.015),
    "alcista":         lambda r, n: gbm(r, n, 0.002, 0.015),
    "bajista":         lambda r, n: gbm(r, n, -0.002, 0.015),
    "tendencias":      regimes,
    "reversion_media": ou,
    "ciclos":          cycles,
    "burbuja":         bubble,
}


def make(family, seed, n=N_TICKS):
    rng = random.Random(f"{family}-{seed}")
    return normalize(FAMILIES[family](rng, n))


def suite(seeds=20, n=N_TICKS):
    """Todas las familias x semillas: {(familia, semilla): precios}."""
    return {(f, s): make(f, s, n) for f in FAMILIES for s in range(seeds)}


def save_csv(prices, path):
    with open(path, "w") as fh:
        fh.write("tick,precio\n")
        for i, p in enumerate(prices):
            fh.write(f"{i},{p}\n")


def load_csv(path):
    out = []
    for line in open(path):
        line = line.strip()
        if not line or not line[0].isdigit():
            continue
        out.append(int(line.split(",")[-1]))
    return out
