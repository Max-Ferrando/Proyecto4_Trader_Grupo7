# GENERADO por tools/make_demo.py a partir de sw/trade.s. NO EDITAR.
# Version DEMO: lee precios de una tabla (solo para probar la placa).
.equ DELAY,    1600000             # ~0,3 s por tick a 25 MHz
.equ DEMO_N,   96
.equ DEMO_IDX, 0x6FC               # indice de la tabla, justo antes del buffer
# =============================================================================
# trade.s - Pochoco Trader: agente de inversion para Espino Core (RV32E)
# Proyecto 4 - Arquitectura de Computadores 2026-2 - Grupo 7
#
# Ensamblar:  python3 tools/rvasm.py sw/trade.s -o sw/trade.hex -l sw/trade.lst
#
# ALGORITMO (cruce de medias moviles, version de referencia: algo/trade_ref.py)
#   * Media corta de S precios y media larga de L precios. Si la corta supera
#     a la larga por mas de M (en unidades de precio) la tendencia es alcista:
#     quiero estar COMPRADO. Si queda por debajo por mas de M: quiero estar
#     FUERA. Entre medio no cambio de opinion (histeresis, evita ordenes por
#     ruido).
#   * Para no dividir se compara L*suma_corta con S*suma_larga.
#   * Cantidad: comprado -> compra todo lo que alcance (max. 63 por orden);
#     fuera -> vende todo lo que tiene (max. 63 por orden).
#
# PROTOCOLO (enunciado 2.2): la orden escrita en DECISION despues de recibir
# p[n] la ejecuta la maestra al precio p[n+1]. Por eso al llegar cada precio
# primero se aplica la orden pendiente a la copia propia de la contabilidad.
#
# RESTRICCIONES DEL CORE: sin MUL/DIV y con los shifts deshabilitados.
#   * x*K constante -> lazo de K sumas.
#   * cantidad que alcanza (caja-C)/p -> lazo de sumas de p (afford).
#   * n*p de una venta -> lazo de n sumas.
#
# Mapa de memoria
#   0x0000_0000  programa (BRAM)
#   0x0000_0700  buffer circular de L precios (palabras de 32 bits)
#   0x8000_0000  perifericos: +0 display 7 seg, +4 LEDs, +0xC contador ciclos
#   0x8001_0000  SPI: +0 STATUS (bit0 = precio nuevo), +4 PRICE, +8 DECISION
#
# Registros (todos "globales", no hay pila)
#   s0 = base SPI          s1 = caja ($)          tp = acciones
#   gp = ultimo byte escrito en DECISION (orden pendiente)
#   a2 = suma corta        a3 = suma larga        a4 = indice del buffer (bytes)
#   a5 = precios recibidos (satura en L)          sp = 1 quiero estar comprado
#   a0 = precio actual     ra = retorno de afford
#   t0, t1, t2, a1 = temporales
# =============================================================================

# ----------------------------- Parametros ------------------------------------
.equ S,       3                 # ventana corta (ticks)
.equ L,       10                # ventana larga (ticks), 2 <= L <= 64, S < L
.equ M,       1                 # histeresis (unidades de precio)
.equ CASH0,   10000             # caja inicial
.equ FEE,     5                 # comision por orden ejecutada
.equ QMAX,    63                # cantidad maxima por orden

.equ THR,     M * S * L         # umbral para L*suma_corta - S*suma_larga
.equ LBYTES,  4 * L             # largo del buffer en bytes
.equ SOFF,    4 * (L - S)       # desplazamiento al precio de hace S ticks

.equ PERIPH,  0x80000000
.equ SPI,     0x80010000
.equ BUF,     0x700             # cabe en el inmediato de 12 bits de lw/sw

.equ ACT_BUY,  0x40
.equ ACT_SELL, 0x80

# ----------------------------- Inicio ----------------------------------------
start:
    li   s0, SPI
    li   s1, CASH0
    li   tp, 0
    li   gp, 0
    li   a2, 0
    li   a3, 0
    li   a4, 0
    li   a5, 0
    li   sp, 0
    li   t0, 0                      # buffer en cero (la BRAM puede venir con basura)
    li   t1, LBYTES
clear:
    sw   zero, BUF(t0)
    addi t0, t0, 4
    bne  t0, t1, clear
    sw   zero, 8(s0)                # DECISION = mantener
    sw   zero, DEMO_IDX(zero)       # DEMO: empieza en el primer precio

# ----------------------------- Ciclo principal -------------------------------
wait:                               # DEMO: precio desde la tabla
    li   t0, DELAY                  # pausa entre ticks
demo_dly:
    addi t0, t0, -1
    bnez t0, demo_dly
    lw   t1, DEMO_IDX(zero)         # indice actual (bytes)
    lw   a0, demo_tab(t1)
    addi t1, t1, 4
    li   t2, 4 * DEMO_N
    bne  t1, t2, demo_ok
    li   t1, 0                      # al terminar la tabla vuelve a empezar
demo_ok:
    sw   t1, DEMO_IDX(zero)

    # 2) aplicar la orden pendiente al precio recien llegado
apply:
    andi a1, gp, 63                 # q
    beqz a1, update
    andi t0, gp, 0xC0
    li   t1, ACT_BUY
    bne  t0, t1, apply_sell
    call afford                     # t0 = n, t1 = costo (FEE + n*p)
    beqz t0, update
    sub  s1, s1, t1
    add  tp, tp, t0
    j    update
apply_sell:
    li   t1, ACT_SELL
    bne  t0, t1, update             # 0xC0 = reservado = mantener
    bgeu tp, a1, sell_n             # n = min(q, acciones)
    mv   a1, tp
sell_n:
    beqz a1, update
    sub  tp, tp, a1
    li   t1, 0                      # t1 = n*p con sumas
sell_mul:
    add  t1, t1, a0
    addi a1, a1, -1
    bnez a1, sell_mul
    add  s1, s1, t1
    addi s1, s1, -FEE

    # 3) actualizar ventanas moviles (buffer circular)
update:
    lw   t0, BUF(a4)                # precio de hace L ticks (sale de la larga)
    sub  t0, a0, t0
    add  a3, a3, t0
    addi t2, a4, SOFF               # precio de hace S ticks (sale de la corta)
    li   t1, LBYTES
    blt  t2, t1, s_ok
    sub  t2, t2, t1
s_ok:
    lw   t0, BUF(t2)
    sub  t0, a0, t0
    add  a2, a2, t0
    sw   a0, BUF(a4)
    addi a4, a4, 4
    bne  a4, t1, idx_ok
    li   a4, 0
idx_ok:
    li   t1, L                      # calentamiento: hasta tener L precios
    beq  a5, t1, signal
    addi a5, a5, 1
    bne  a5, t1, decide

    # 4) senal: diff = L*suma_corta - S*suma_larga
signal:
    li   t0, 0
    li   t2, L
mul_l:
    add  t0, t0, a2
    addi t2, t2, -1
    bnez t2, mul_l
    li   t1, 0
    li   t2, S
mul_s:
    add  t1, t1, a3
    addi t2, t2, -1
    bnez t2, mul_s
    sub  t0, t0, t1
    li   t1, THR
    ble  t0, t1, not_up
    li   sp, 1                      # tendencia alcista: quiero estar comprado
    j    decide
not_up:
    li   t1, -THR
    bge  t0, t1, decide             # dentro de la banda: sin cambio
    li   sp, 0                      # tendencia bajista: quiero estar fuera

    # 5) decidir cantidad y escribir DECISION
decide:
    li   gp, 0
    beqz sp, dec_sell
    li   a1, QMAX
    call afford
    beqz t0, out
    ori  gp, t0, ACT_BUY
    j    out
dec_sell:
    mv   t0, tp                     # vender min(63, acciones)
    li   t1, QMAX
    bleu t0, t1, ds_ok
    mv   t0, t1
ds_ok:
    beqz t0, out
    ori  gp, t0, ACT_SELL
out:
    sw   gp, 8(s0)                  # DECISION

    # 6) display: precio en hexadecimal; LEDs: 0 = comprado, 1 = compra, 2 = venta
    li   t1, PERIPH
    sw   a0, 0(t1)
    mv   t2, sp
    andi t0, gp, 0xC0
    li   a1, ACT_BUY
    bne  t0, a1, led_s
    ori  t2, t2, 2
led_s:
    li   a1, ACT_SELL
    bne  t0, a1, led_w
    ori  t2, t2, 4
led_w:
    sw   t2, 4(t1)
    j    wait

# ----------------------------- Subrutina -------------------------------------
# afford: mayor n <= a1 tal que FEE + n*p <= caja.
#   entrada: a0 = p, a1 = maximo, s1 = caja
#   salida:  t0 = n, t1 = FEE + n*p      (usa t2)
afford:
    li   t0, 0
    li   t1, FEE
    beqz a1, aff_end
aff_loop:
    add  t2, t1, a0
    bltu s1, t2, aff_end            # caja < costo con una accion mas
    mv   t1, t2
    addi t0, t0, 1
    bne  t0, a1, aff_loop
aff_end:
    ret

# ----------------------------- Tabla DEMO ------------------------------------
demo_tab:
    .word 88, 88, 89, 88, 87, 86, 88, 87
    .word 88, 88, 86, 85, 83, 82, 82, 82
    .word 82, 79, 80, 77, 79, 80, 80, 79
    .word 79, 80, 81, 82, 81, 80, 81, 81
    .word 81, 83, 84, 85, 83, 82, 82, 84
    .word 84, 84, 85, 85, 85, 84, 85, 86
    .word 85, 86, 86, 86, 86, 87, 87, 88
    .word 88, 88, 87, 87, 88, 88, 88, 89
    .word 89, 90, 91, 91, 92, 92, 91, 92
    .word 92, 91, 95, 95, 97, 96, 97, 99
    .word 101, 100, 101, 99, 100, 101, 101, 103
    .word 105, 104, 105, 105, 105, 102, 102, 103
