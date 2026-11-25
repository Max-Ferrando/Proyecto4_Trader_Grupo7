# Proyecto 4 - Pochoco Trader - Grupo 7
# Hibrido con trailing stop y cooldown. Solo usa precios ya recibidos.
# Referencia: algo/trade_ref.py. El testbench oficial ejecuta la orden
# al precio del tick siguiente y limita q a caja/acciones disponibles.
# Por eso enviamos q=63 en direccion objetivo: la maestra ajusta el fill.
# Si no hay caja/acciones suficientes para una unidad, no hay orden ni fee.
# No se guardan series ni se modifica RTL, reloj ni protocolo SPI.
# RV32E: sin MUL, DIV ni shifts (deshabilitados en el Espino).
.equ S,       20
.equ L,       120
.equ LM,      60
.equ ENTRY,   4
.equ EXIT,    2
.equ M2,      4
.equ TIN,     4
.equ STOP,    8
.equ COOL,    64
.equ SHOCK,   32             # salto de precio: abstenerse durante cooldown
.equ LBYTES,  4 * L
.equ SOFF,    4 * (L - S)
.equ MOFF,    4 * (L - LM)
.equ SUMM,    0x5F0
.equ STATE,   0x5F4
.equ BUF,     0x600
.equ SPI,     0x80010000
.equ PERIPH,  0x80000000

# s0 = SPI; s1 = maximo desde entrada; tp = cooldown restante
# sp = objetivo anterior (0 fuera, 1 comprado); gp = byte de decision
# a2/a3 = sumas S/L; a4 = indice en bytes; a5 = calentamiento
# a0 = precio; ra = precio anterior; t0/t1/t2/a1 = temporales
start:
    li   s0, SPI
    li   s1, 0
    li   tp, 0
    li   gp, 0
    li   a2, 0
    li   a3, 0
    li   a4, 0
    li   a5, 0
    li   sp, 0
    li   ra, 0
    li   t0, 0
    li   t1, LBYTES
clear:
    sw   zero, BUF(t0)
    addi t0, t0, 4
    bne  t0, t1, clear
    sw   zero, SUMM(zero)
    sw   zero, STATE(zero)
    sw   zero, 8(s0)                # DECISION = mantener

wait:                               # 1) esperar precio
    lw   t0, 0(s0)                  # STATUS
    andi t0, t0, 1
    beqz t0, wait
    lw   a0, 4(s0)                  # PRICE (leerlo baja el bit de precio nuevo)

# Ventanas circulares: O(1) por tick, no se recorre el historial.
update:
    lw   t0, BUF(a4)
    sub  t0, a0, t0
    add  a3, a3, t0
    addi t2, a4, SOFF
    li   t1, LBYTES
    blt  t2, t1, s_ok
    sub  t2, t2, t1
s_ok:
    lw   t0, BUF(t2)
    sub  t0, a0, t0
    add  a2, a2, t0
    addi t2, a4, MOFF
    blt  t2, t1, m_ok
    sub  t2, t2, t1
m_ok:
    lw   t0, BUF(t2)
    sub  t0, a0, t0
    lw   t2, SUMM(zero)
    add  t2, t2, t0
    sw   t2, SUMM(zero)
    sw   a0, BUF(a4)
    addi a4, a4, 4
    bne  a4, t1, idx_ok
    li   a4, 0
idx_ok:
    li   t1, L
    beq  a5, t1, signal
    addi a5, a5, 1
    beq  a5, t1, signal
    li   gp, 0
    j    out

# Reversion: d = 60*p - suma_60. 60*p = (16*p - p)*4.
# Las constantes 20/120/60 son fijas para las cadenas de sumas.
signal:
    add  t0, a0, a0
    add  t0, t0, t0
    add  t0, t0, t0
    add  t0, t0, t0
    sub  t0, t0, a0
    add  t0, t0, t0
    add  t0, t0, t0
    lw   t1, SUMM(zero)
    sub  t0, t0, t1
    lw   a1, STATE(zero)
    li   t1, -TIN * LM
    bge  t0, t1, mr_not_low
    ori  a1, a1, 2
    j    mr_done
mr_not_low:
    ble  t0, zero, mr_done
    andi a1, a1, 1
mr_done:
# Tendencia: diff = 6*suma_20 - suma_120 = 120*(media20-media120).
    add  t0, a2, a2
    add  t1, t0, a2
    add  t0, t1, t1
    sub  t0, t0, a3
    li   t1, ENTRY * L
    ble  t0, t1, tr_not_up
    ori  a1, a1, 1
    j    tr_done
tr_not_up:
    li   t1, -EXIT * L
    bge  t0, t1, tr_done
    andi a1, a1, 2
tr_done:
    sw   a1, STATE(zero)
    andi t2, a1, 1
    bnez t2, risk
    li   t1, -M2 * L
    blt  t0, t1, risk
    andi t1, a1, 2
    beqz t1, risk
    li   t2, 1

# t2 = objetivo candidato; sp = objetivo del tick previo.
# Stop relativo al maximo de precio observado desde la entrada de la senal.
# No garantiza precio de salida: la orden se ejecuta al precio siguiente.
risk:
    beqz tp, check_peak
    addi tp, tp, -1
check_peak:
    beqz sp, enforce_cool
    bge  s1, a0, check_stop
    mv   s1, a0
check_stop:
    sub  t0, s1, a0
    li   t1, STOP
    blt  t0, t1, enforce_cool
    li   tp, COOL
    sw   zero, STATE(zero)
    li   t2, 0
enforce_cool:
    beqz tp, new_entry
    li   t2, 0
new_entry:
    beqz t2, decide
    bnez sp, decide
    mv   s1, a0
decide:
    # Si el ultimo salto fue extremo, no perseguir el precio ni comprar el dip.
    sub  t0, a0, ra
    li   t1, SHOCK
    bge  t0, t1, shock
    li   t1, -SHOCK
    blt  t1, t0, no_shock
shock:
    li   tp, COOL
    sw   zero, STATE(zero)
    li   t2, 0
no_shock:
    mv   sp, t2
    li   gp, 0xBF                  # vender hasta 63; si no hay acciones, no-op
    beqz sp, out
    li   gp, 0x7F                  # comprar hasta 63; la maestra limita a caja
out:
    sw   gp, 8(s0)
    mv   ra, a0
    li   t1, PERIPH
    sw   a0, 0(t1)
    mv   t2, sp
    andi t0, gp, 0xC0
    li   a1, 0x40
    bne  t0, a1, led_s
    ori  t2, t2, 2
led_s:
    li   a1, 0x80
    bne  t0, a1, led_w
    ori  t2, t2, 4
led_w:
    sw   t2, 4(t1)
    j    wait
