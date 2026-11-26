// tb_mavg.v - Testbench autoverificado de rtl/pochoco_mavg.v
//
// Empuja NPUSH precios (rampa, extremos 1/255, maximo sostenido y aleatorios)
// y, despues de cada uno, lee los registros con la cadencia mas exigente que
// puede producir el Espino: primer acceso 2 ciclos despues de la escritura y
// uno cada 3 ciclos. Compara cada lectura con un modelo de referencia que
// recalcula las sumas recorriendo la historia completa.
//
//   Modo normal (SUM60, SUM20, SUM120):
//     iverilog -g2012 -o sim/out/tb_mavg.vvp tb/tb_mavg.v rtl/pochoco_mavg.v
//   Modo senales (MR, TREND):
//     iverilog -g2012 -DPOCHOCO_MAVG_SIG -o sim/out/tb_mavg_sig.vvp tb/tb_mavg.v rtl/pochoco_mavg.v
//   vvp -n sim/out/tb_mavg.vvp
`timescale 1ns/1ps
module tb_mavg;
  localparam NPUSH = 3000;

  reg clk = 1'b0;
  always #20 clk = ~clk;

  reg         rst_n = 1'b0;
  reg         req = 1'b0, we = 1'b0;
  reg  [7:0]  addr = 8'd0;
  reg  [31:0] wdata = 32'd0;
  wire [31:0] rdata;

  pochoco_mavg dut (
    .clk_i(clk), .rst_ni(rst_n), .sel_i(1'b1), .req_i(req), .we_i(we),
    .addr_i(addr), .wdata_i(wdata), .rdata_o(rdata)
  );

  // ---- modelo de referencia: historia completa y sumas recalculadas ----
  integer hist [0:NPUSH-1];
  integer n_hist = 0;
  function integer ref_sum(input integer k);
    integer j, s;
    begin
      s = 0;
      for (j = 0; j < k; j = j + 1)
        if (n_hist - 1 - j >= 0) s = s + hist[n_hist - 1 - j];
      ref_sum = s;
    end
  endfunction

  integer errors = 0, checks = 0;

  task bus_write(input [7:0] a, input [31:0] d);
    begin
      @(negedge clk); req = 1'b1; we = 1'b1; addr = a; wdata = d;
      @(negedge clk); req = 1'b0; we = 1'b0;
    end
  endtask

  task bus_read_check(input [7:0] a, input signed [31:0] expected, input [8*8-1:0] name);
    begin
      req = 1'b1; we = 1'b0; addr = a;
      @(negedge clk); req = 1'b0;
      checks = checks + 1;
      if (rdata !== expected) begin
        errors = errors + 1;
        if (errors <= 10)
          $display("ERROR push %0d: %0s = %0d, esperado %0d", n_hist, name, $signed(rdata), expected);
      end
      @(negedge clk); @(negedge clk);        // un lw del Espino tarda 3 ciclos
    end
  endtask

  integer n, p, seed;
  initial begin
    seed = 32'h1234_5678;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    for (n = 0; n < NPUSH; n = n + 1) begin
      if      (n < 300)  p = 1 + (n % 255);                   // rampa
      else if (n < 600)  p = ((n / 7) % 2) ? 255 : 1;         // extremos alternados
      else if (n < 900)  p = 255;                             // maximo sostenido
      else               p = 1 + ({$random(seed)} % 255);     // aleatorio 1..255
      hist[n_hist] = p; n_hist = n_hist + 1;
      bus_write(8'h00, p);
      @(negedge clk);                                         // 2 ciclos tras el sw
`ifdef POCHOCO_MAVG_SIG
      bus_read_check(8'h04, 60 * p - ref_sum(60),            "MR");
      bus_read_check(8'h00, 6 * ref_sum(20) - ref_sum(120),  "TREND");
`else
      bus_read_check(8'h04, ref_sum(60),  "SUM60");
      bus_read_check(8'h00, ref_sum(20),  "SUM20");
      bus_read_check(8'h08, ref_sum(120), "SUM120");
`endif
    end

    $display("tb_mavg: %0d precios, %0d lecturas comparadas, %0d errores", NPUSH, checks, errors);
    if (errors == 0) $display("PASS pochoco_mavg coincide con el modelo de referencia");
    else             $display("FAIL pochoco_mavg");
    $finish;
  end
endmodule
