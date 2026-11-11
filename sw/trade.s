# =============================================================================
# trade.s - Pochoco Trader: agente de inversion para Espino Core (RV32E)
# Proyecto 4 - Arquitectura de Computadores 2026-2 - Grupo 7
#
# Ensamblar:  python3 tools/rvasm.py sw/trade.s -o sw/trade.hex -l sw/trade.lst
#
# ALGORITMO (reversion a la media, referencia exacta: algo/trade_ref.py)
#   * Media de los ultimos L precios. Si el precio cae mas de TIN unidades
#     bajo la media, se espera que vuelva: quiero estar COMPRADO. Si el precio
#     sube mas de TOUT unidades sobre la media (TOUT = 0: vuelve a la media),
#     quiero estar FUERA. Entre medio no cambio de opinion.
#   * Para no dividir se usa d = L*p - suma = L*(p - media) y se compara con
#     -TIN*L y TOUT*L.
#   * Cantidad: comprado -> compra todo lo que alcance (max. 63 por orden);
#     fuera -> vende todo lo que tiene (max. 63 por orden).
#   * Parametros elegidos con la serie de practica (algo/tune_practica.py).
#
# PROTOCOLO (enunciado 2.2): la orden escrita en DECISION despues de recibir
# p[n] la ejecuta la maestra al precio p[n+1]. Por eso al llegar cada precio
# primero se aplica la orden pendiente a la copia propia de la contabilidad,
# con las mismas reglas que tb/tb_proyecto_4.sv.
#
# RESTRICCIONES DEL CORE: sin MUL/DIV y con los shifts deshabilitados.
#   * L*p           -> duplicaciones: suma p, 2p, 4p... segun los bits de L.
#   * cantidad que alcanza (caja-C)/p -> lazo de sumas de p (afford).
#   * n*p de una venta -> lazo de n sumas.
#
# Mapa de memoria
#   0x0000_0000  programa (BRAM de 2 KB)
#   0x0000_0700  buffer circular de L precios (palabras de 32 bits)
#   0x8000_0000  perifericos: +0 display 7 seg, +4 LEDs, +0xC contador ciclos
#   0x8001_0000  SPI: +0 STATUS (bit0 = precio nuevo), +4 PRICE, +8 DECISION
#
# Registros (todos "globales", no hay pila)
#   s0 = base SPI          s1 = caja ($)          tp = acciones
#   gp = ultimo byte escrito en DECISION (orden pendiente)
#   a3 = suma de los ultimos L precios            a4 = indice del buffer (bytes)
#   a5 = precios recibidos (satura en L)          sp = 1 quiero estar comprado
#   a0 = precio actual     ra = retorno de afford
#   t0, t1, t2, a1, a2 = temporales
# =============================================================================

# ----------------------------- Parametros ------------------------------------
.equ L,       60                # ventana de la media (ticks), 2 <= L <= 64
.equ TIN,     4                 # entrar: precio TIN unidades bajo la media
.equ TOUT,    0                 # salir: precio TOUT unidades sobre la media
.equ CASH0,   10000             # caja inicial
.equ FEE,     5                 # comision por orden ejecutada
.equ QMAX,    63                # cantidad maxima por orden

.equ THR_IN,  -TIN * L          # d <  THR_IN  -> comprado
.equ THR_OUT, TOUT * L          # d >  THR_OUT -> fuera
.equ LBYTES,  4 * L             # largo del buffer en bytes

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

# ----------------------------- Ciclo principal -------------------------------
wait:                               # 1) esperar precio
    lw   t0, 0(s0)                  # STATUS
    andi t0, t0, 1
    beqz t0, wait
    lw   a0, 4(s0)                  # PRICE (leerlo baja el bit de precio nuevo)

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
    li   t1, 0                      # t1 = n*p con sumas
    mv   t2, a1
sell_mul:
    add  t1, t1, a0
    addi t2, t2, -1
    bnez t2, sell_mul
    add  t1, s1, t1                 # caja + n*p
    li   t2, FEE
    blt  t1, t2, update             # la maestra no vende si caja + n*p < C
    sub  s1, t1, t2
    sub  tp, tp, a1

    # 3) actualizar la ventana movil (buffer circular)
update:
    lw   t0, BUF(a4)                # precio de hace L ticks
    sub  t0, a0, t0
    add  a3, a3, t0                 # suma += p - viejo
    sw   a0, BUF(a4)
    addi a4, a4, 4
    li   t1, LBYTES
    bne  a4, t1, idx_ok
    li   a4, 0
idx_ok:
    li   t1, L                      # calentamiento: hasta tener L precios
    beq  a5, t1, signal
    addi a5, a5, 1
    bne  a5, t1, decide

    # 4) senal: d = L*p - suma, con L*p por duplicaciones
signal:
    li   t0, 0                      # acumulado
    mv   t1, a0                     # p * 2^k
    li   t2, 1                      # mascara del bit k de L
mul_l:
    li   a1, L
    and  a1, a1, t2
    beqz a1, mul_next
    add  t0, t0, t1
mul_next:
    add  t1, t1, t1
    add  t2, t2, t2
    li   a1, 256                    # L < 256: 8 bits
    bltu t2, a1, mul_l
    sub  t0, t0, a3                 # d
    li   t1, THR_IN
    bge  t0, t1, not_low
    li   sp, 1                      # muy bajo la media: quiero estar comprado
    j    decide
not_low:
    li   t1, THR_OUT
    ble  t0, t1, decide             # en la banda: sin cambio
    li   sp, 0                      # volvio sobre la media: quiero estar fuera

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
