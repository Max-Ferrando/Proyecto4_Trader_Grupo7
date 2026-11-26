"""sintesis.py - Resume la sintesis de cada variante (build/<variante>/).

Lee build/<v>/stat.txt (Yosys) y build/<v>/nextpnr.log y escribe
docs/mediciones/sintesis.csv con LUT4, celdas logicas, BRAM y Fmax.
Las variantes que no caben quedan con cabe = no y el error de nextpnr.

  make bin VARIANTE=base  (y pc12, mavg, sig, shifter, mul8, pll)
  python3 tools/sintesis.py
"""
import csv
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
ORDER = ["base", "pc12", "mavg", "sig", "mul8", "shifter", "pll"]


def read(path):
    return open(path, errors="replace").read() if os.path.exists(path) else ""


def main():
    rows = []
    for v in ORDER:
        d = os.path.join(ROOT, "build", v)
        st, pn = read(os.path.join(d, "stat.txt")), read(os.path.join(d, "nextpnr.log"))
        if not st:
            continue
        def cnt(cell):
            m = re.search(r"^\s*(\d+)\s+(?:[\d.eE+]+\s+)?" + cell + r"\s*$", st, re.M)
            return int(m.group(1)) if m else 0
        lc = re.findall(r"ICESTORM_LC:\s*(\d+)/\s*(\d+)", pn)
        fm = re.findall(r"Max frequency for clock[^:]*: ([\d.]+) MHz", pn)
        err = re.findall(r"ERROR: (.*)", pn)
        ff = sum(int(n) for n in re.findall(r"^\s*(\d+)\s+(?:[\d.eE+]+\s+)?SB_DFF\w*\s*$", st, re.M))
        rows.append({"variante": v, "lut4": cnt("SB_LUT4"), "carry": cnt("SB_CARRY"), "ff": ff,
                     "celdas": lc[-1][0] if lc else "", "bram": cnt("SB_RAM40_4K"),
                     "fmax_mhz": fm[-1] if (fm and not err) else "",
                     "cabe": "no" if err else "si",
                     "error": (err[0][:70] if err else "")})
    out = os.path.join(ROOT, "docs", "mediciones", "sintesis.csv")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    for r in rows:
        print(r)


if __name__ == "__main__":
    main()
