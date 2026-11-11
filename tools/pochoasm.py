"""pochoasm.py - Alias del assembler del grupo (tools/rvasm.py).

El testbench oficial (tb/tb_proyecto_4.sv) indica ensamblar con
    python3 tools/pochoasm.py sw/trade.s -o sw/trade.hex
Este archivo hace que ese comando funcione con nuestro assembler.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rvasm import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
