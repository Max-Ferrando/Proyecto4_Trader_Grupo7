# =============================================================================
# trade.s - Pochoco Trader: agente de inversion para Espino Core (RV32E)
# Proyecto 4 - Arquitectura de Computadores 2026-2 - Grupo 7
#
# Ensamblar:  python3 tools/rvasm.py sw/trade.s -o sw/trade.hex -l sw/trade.lst
#
# ALGORITMO HIBRIDO (referencia exacta: algo/trade_ref.py)
#   * Tendencia: media corta (S) contra media larga (L). Si la corta supera a
#     la larga por mas de M -> trend = 1; si queda mas de M por debajo -> 0.
#   * Reversion a la media: si el precio cae mas de TIN bajo la media de LM
#     precios -> mr = 1; si sube mas de TOUT sobre esa media -> mr = 0.
#   * Quiero estar COMPRADO si trend, o si mr y no hay bajada fuerte (media
#     corta mas de M2 bajo la larga). Si no, quiero estar FUERA.
#   * Sin divisiones: se comparan sumas escaladas (L*suma_corta con
#     S*suma_larga, y LM*precio con la suma de LM precios).
#   * Cantidad: comprado -> compra todo lo que alcance (max. 63 por orden);
#     fuera -> vende todo lo que tiene (max. 63 por orden).
#   * Parametros elegidos con las dos series de practica.
#
# PROTOCOLO (enunciado 2.2): la orden escrita en DECISION despues de recibir
# p[n] la ejecuta la maestra al precio p[n+1]. Por eso al llegar cada precio
# primero se aplica la orden pendiente a la copia propia de la contabilidad,
# con las mismas reglas que tb/tb_proyecto_4.sv.
#
# RESTRICCIONES DEL CORE: sin MUL/DIV y con los shifts deshabilitados.
#   * x*K constante -> duplicaciones: suma x, 2x, 4x... segun los bits de K.
#   * cantidad que alcanza (caja-C)/p -> lazo de sumas de p (afford).
#   * n*p de una venta -> lazo de n sumas.
#
# Mapa de memoria
#   0x0000_0000  programa (BRAM de 2 KB)
#   0x0000_05F0  SUMM: suma de los ultimos LM precios   0x5F4 STATE: bit0 trend, bit1 mr
#   0x0000_0600  buffer circular de L precios (palabras de 32 bits)
#   0x8000_0000  perifericos: +0 display 7 seg, +4 LEDs, +0xC contador ciclos
#   0x8001_0000  SPI: +0 STATUS (bit0 = precio nuevo), +4 PRICE, +8 DECISION
#
# Registros (todos "globales", no hay pila)
#   s0 = base SPI          s1 = caja ($)          tp = acciones
#   gp = ultimo byte escrito en DECISION (orden pendiente)
#   a2 = suma corta (S)    a3 = suma larga (L)    a4 = indice del buffer (bytes)
#   a5 = precios recibidos (satura en L)          sp = 1 quiero estar comprado
#   a0 = precio actual     ra = retorno de afford
#   t0, t1, t2, a1 = temporales
# =============================================================================

# ----------------------------- Parametros ------------------------------------
.equ S,       20                # ventana corta (ticks)
.equ L,       120               # ventana larga (ticks), S < L <= 120
.equ M,       8                 # histeresis (unidades de precio)
.equ LM,      60                # ventana de la reversion a la media (LM <= L)
.equ TIN,     4                 # mr = 1 si el precio esta TIN bajo la media LM
.equ TOUT,    0                 # mr = 0 si el precio esta TOUT sobre la media LM
.equ M2,      4                 # bajada fuerte: corta mas de M2 bajo la larga
.equ CASH0,   10000             # caja inicial
.equ FEE,     5                 # comision por orden ejecutada
.equ QMAX,    63                # cantidad maxima por orden

.equ THR,     M * S * L         # umbral para L*suma_corta - S*suma_larga
.equ LBYTES,  4 * L             # largo del buffer en bytes
.equ SOFF,    4 * (L - S)       # desplazamiento al precio de hace S ticks
.equ MOFF,    4 * (L - LM)      # desplazamiento al precio de hace LM ticks
.equ THR2,    M2 * S * L        # umbral de bajada fuerte
.equ SUMM,    0x5F0
.equ STATE,   0x5F4

.equ PERIPH,  0x80000000
.equ SPI,     0x80010000
.equ BUF,     0x600             # cabe en el inmediato de 12 bits de lw/sw

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
    sw   zero, SUMM(zero)
    sw   zero, STATE(zero)
    sw   zero, 8(s0)                # DECISION = mantener

# ----------------------------- Ciclo principal -------------------------------
wait:                               # 1) esperar precio
    lw   t0, 0(s0)                  # STATUS
    andi t0, t0, 1
    beqz t0, wait
    lw   a0, 4(s0)                  # PRICE (leerlo baja el bit de precio nuevo)

    # 2) aplicar la orden pendiente al precio recien llegado
apply:
    j    update
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

    # 3) actualizar las ventanas moviles (buffer circular)
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
    addi t2, a4, MOFF               # precio de hace LM ticks (sale de la media LM)
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
    li   t1, L                      # calentamiento: hasta tener L precios
    beq  a5, t1, signal
    addi a5, a5, 1
    bne  a5, t1, decide

    # 4) senal: diff = L*suma_corta - S*suma_larga
    #    Multiplicacion por constante con duplicaciones: recorre los 8 bits de
    #    la constante con una mascara y suma x, 2x, 4x... (ra se usa como
    #    registro temporal: aqui no hay ninguna llamada en curso).
signal:
    li   ra, 0                      # ra = LM * precio
    mv   t1, a0
    li   t2, 1
mul_m:
    andi a1, t2, LM
    beqz a1, mul_m_next
    add  ra, ra, t1
mul_m_next:
    add  t1, t1, t1
    add  t2, t2, t2
    li   a1, 256
    bltu t2, a1, mul_m
    lw   t1, SUMM(zero)
    sub  ra, ra, t1                 # d = LM*p - suma = LM*(p - media)
    lw   a1, STATE(zero)
    li   t1, -TIN * LM
    bge  ra, t1, mr_not_low
    ori  a1, a1, 2                  # muy bajo la media: mr = 1
    j    mr_done
mr_not_low:
    li   t1, TOUT * LM
    ble  ra, t1, mr_done
    andi a1, a1, 1                  # volvio sobre la media: mr = 0
mr_done:
    sw   a1, STATE(zero)
    li   t0, 0                      # t0 = L * suma_corta
    mv   t1, a2
    li   t2, 1
mul_l:
    andi a1, t2, L
    beqz a1, mul_l_next
    add  t0, t0, t1
mul_l_next:
    add  t1, t1, t1
    add  t2, t2, t2
    li   a1, 256
    bltu t2, a1, mul_l
    li   ra, 0                      # ra = S * suma_larga
    mv   t1, a3
    li   t2, 1
mul_s:
    andi a1, t2, S
    beqz a1, mul_s_next
    add  ra, ra, t1
mul_s_next:
    add  t1, t1, t1
    add  t2, t2, t2
    li   a1, 256
    bltu t2, a1, mul_s
    sub  t0, t0, ra                 # diff
    lw   a1, STATE(zero)
    li   t1, THR
    ble  t0, t1, tr_not_up
    ori  a1, a1, 1                  # tendencia alcista: trend = 1
    j    tr_done
tr_not_up:
    li   t1, -THR
    bge  t0, t1, tr_done
    andi a1, a1, 2                  # tendencia bajista: trend = 0
tr_done:
    sw   a1, STATE(zero)
    andi sp, a1, 1                  # quiero = trend ...
    bnez sp, decide
    li   t1, -THR2
    blt  t0, t1, decide             # bajada fuerte: fuera
    andi t1, a1, 2
    beqz t1, decide
    li   sp, 1                      # ... o mr sin bajada fuerte

    # 5) decidir cantidad y escribir DECISION
decide:
    li   gp, 0xBF
    beqz sp, out
    li   gp, 0x7F
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
