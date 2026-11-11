// tb_trader.v - Emula a la FPGA maestra del Proyecto 4 y mide cada tick.
//
// * Instancia pochoco_soc (el mismo top que va a la Go Board) con sw/trade.hex
//   (o el archivo dado con -DPOCHOCO_MEMFILE).
// * Por cada tick: baja CS_n, envia el precio por SPI modo 0 (CPOL=0, CPHA=0,
//   MSB primero, SCLK ~0,96 MHz), lee por MISO el byte de DECISION y sube CS_n.
//   El siguiente tick empieza TICK ciclos despues (por defecto 2500 = ronda 3).
// * Hace N+1 transacciones: el byte leido en la transaccion n+1 es la decision
//   del grupo para el precio n.
// * Mide, para cada tick, desde que el precio queda en PRICE (fin del byte SPI):
//     dec  = ciclos e instrucciones hasta escribir DECISION
//     loop = ciclos e instrucciones hasta volver a leer STATUS (fin del tick)
//   Una instruccion se cuenta cuando el core la completa (commit en ID).
// * Marca como ATRASADO el tick cuya decision no se escribio antes de que
//   bajara el CS_n siguiente.
//
// Plusargs: +PRICES=archivo.hex  +N=ticks  +TICK=ciclos  +HALF=ciclos_medio_SCLK
//           +OUT=decisiones.txt  +PROF=perfil.csv
`timescale 1ns/1ps
`ifndef POCHOCO_MEMFILE
`define POCHOCO_MEMFILE "sw/trade.hex"
`endif

module tb_trader;
  reg clk = 1'b0;
  always #20 clk = ~clk;                 // 25 MHz, igual que la Go Board

  reg  sclk = 1'b0, mosi = 1'b0, cs_n = 1'b1;
  wire miso;
  wire [3:0] led;

  pochoco_soc dut (
    .i_Clk      (clk),
    .o_LED      (led),
    .i_Switch   (4'b0000),
    .i_SPI_SCLK (sclk),
    .i_SPI_MOSI (mosi),
    .i_SPI_CS_n (cs_n),
    .o_SPI_MISO (miso)
  );

  // ---------------- parametros ----------------
  reg [8*256-1:0] prices_file, out_file, prof_file, pcprof_file;
  integer N, TICK, HALF;
  reg [7:0] price [0:65535];

  // ---------------- contadores ----------------
  integer cyc = 0, ic = 0;
  integer tick_id = -1;
  // Perfil por instruccion: ciclos que cada PC pasa en ID e instrucciones completadas
  integer pc_cyc [0:511];
  integer pc_ic  [0:511];
  integer k0;
  initial for (k0 = 0; k0 < 512; k0 = k0 + 1) begin pc_cyc[k0] = 0; pc_ic[k0] = 0; end
  wire [8:0] pc_w = dut.u_core.u_id.pc_id_i[10:2];
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (dut.u_core.u_id.commit) ic <= ic + 1;
    if (tick_id >= 0) begin
      pc_cyc[pc_w] = pc_cyc[pc_w] + 1;
      if (dut.u_core.u_id.commit) pc_ic[pc_w] = pc_ic[pc_w] + 1;
    end
  end

  wire spi_byte_done = dut.u_spi.byte_done;
  wire spi_wr_dec    = dut.u_spi.wr & (dut.u_spi.off == 6'd2);
  wire spi_rd_status = dut.u_spi.rd & (dut.u_spi.off == 6'd0);

  // ---------------- medicion por tick ----------------
  integer t_arr, ic_arr;
  integer dec_cyc, dec_ic;
  reg     waiting_dec = 0, waiting_loop = 0;
  integer pf;
  integer late = 0;
  integer cs_fall_cyc = 0;

  always @(posedge clk) begin
    if (spi_byte_done) begin
      tick_id      <= tick_id + 1;
      t_arr        <= cyc;
      ic_arr       <= ic;
      waiting_dec  <= 1'b1;
      waiting_loop <= 1'b0;
    end else if (waiting_dec && spi_wr_dec) begin
      dec_cyc      <= cyc - t_arr;
      dec_ic       <= ic - ic_arr;
      waiting_dec  <= 1'b0;
      waiting_loop <= 1'b1;
    end else if (waiting_loop && spi_rd_status) begin
      $fdisplay(pf, "%0d,%0d,%0d,%0d,%0d,%0d", tick_id, price[tick_id], dec_cyc, dec_ic,
                cyc - t_arr, ic - ic_arr);
      waiting_loop <= 1'b0;
    end
  end

  // Un tick esta atrasado si al bajar CS_n todavia no se escribio su decision
  always @(negedge cs_n) begin
    cs_fall_cyc = cyc;
    if (waiting_dec) begin
      late = late + 1;
      $display("ATRASADO: la decision del tick %0d no alcanzo a escribirse", tick_id);
    end
  end

  // ---------------- maestra SPI ----------------
  task wait_cycles(input integer n);
    integer k;
    begin
      for (k = 0; k < n; k = k + 1) @(posedge clk);
    end
  endtask

  task spi_xfer(input [7:0] tx, output [7:0] rx);
    integer b;
    begin
      cs_n = 1'b0;
      wait_cycles(HALF);
      for (b = 7; b >= 0; b = b - 1) begin
        mosi = tx[b];
        wait_cycles(HALF);
        sclk = 1'b1;                       // flanco de subida: ambos muestrean
        rx[b] = miso;
        wait_cycles(HALF);
        sclk = 1'b0;                       // flanco de bajada: el esclavo cambia MISO
      end
      wait_cycles(HALF);
      cs_n = 1'b1;
    end
  endtask

  integer n, of, t0;
  reg [7:0] rx;
  initial begin
    if (!$value$plusargs("PRICES=%s", prices_file)) prices_file = "data/precios.hex";
    if (!$value$plusargs("N=%d", N))       N = 1000;
    if (!$value$plusargs("TICK=%d", TICK)) TICK = 2500;
    if (!$value$plusargs("HALF=%d", HALF)) HALF = 13;      // 25 MHz / 26 = 0,96 MHz
    if (!$value$plusargs("OUT=%s", out_file))  out_file  = "sim/out/decisiones_asm.txt";
    if (!$value$plusargs("PROF=%s", prof_file)) prof_file = "sim/out/perfil.csv";
    if (!$value$plusargs("PCPROF=%s", pcprof_file)) pcprof_file = "sim/out/perfil_pc.csv";
    $readmemh(prices_file, price);
    of = $fopen(out_file, "w");
    pf = $fopen(prof_file, "w");
    $fdisplay(pf, "tick,precio,ciclos_decision,ic_decision,ciclos_tick,ic_tick");

    wait_cycles(200);                      // reset + inicializacion del programa
    for (n = 0; n <= N; n = n + 1) begin
      t0 = cyc;
      spi_xfer(price[(n < N) ? n : N - 1], rx);
      if (n > 0) $fdisplay(of, "%02x", rx);   // respuesta al precio n-1
      while (cyc < t0 + TICK) @(posedge clk);
    end
    $fclose(of);
    $fclose(pf);
    of = $fopen(pcprof_file, "w");
    $fdisplay(of, "pc,ciclos,instrucciones");
    for (k0 = 0; k0 < 512; k0 = k0 + 1)
      if (pc_cyc[k0] != 0) $fdisplay(of, "%0d,%0d,%0d", 4 * k0, pc_cyc[k0], pc_ic[k0]);
    $fclose(of);
    $display("FIN: %0d ticks, TICK = %0d ciclos, atrasados = %0d", N, TICK, late);
    $finish;
  end
endmodule
