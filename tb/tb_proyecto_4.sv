// Testbench Proyecto 4: emula a la FPGA maestra.
// Correr desde la raíz del repositorio:
//   python3 tools/pochoasm.py sw/trade.s -o sw/trade.hex
//   iverilog -g2012 -s tb_proyecto_4 -o /tmp/tb_p4 $(yosys-config --datdir)/ice40/cells_sim.v rtl/*.v rtl/espino_core/*.v tb/tb_proyecto_4.sv
//   vvp -n /tmp/tb_p4

`timescale 1ns/1ps

module tb_proyecto_4;

  // Configuración: pueden cambiar estos valores
  localparam string PROGRAMA   = "sw/trade.hex";
  localparam string SERIE      = "tb/practica.csv";
  localparam int    PERIODO_NS = 100000;   // ronda 1: 10000000, ronda 2: 1000000, ronda 3: 100000
  localparam int    NTICKS     = 2000;     // la serie completa tiene 20000

  localparam int CAJA0    = 10000;
  localparam int COMISION = 5;
  localparam int SPI_NS   = 9500;          // duración de una transacción SPI

  // Pochoco SoC a 25 MHz
  logic clk = 0;
  always #20 clk = ~clk;

  logic sclk = 0, mosi = 0, cs_n = 1;
  wire  miso;

  pochoco_soc #(.MemFile(PROGRAMA)) dut (
    .i_Clk(clk), .o_LED(), .i_Switch(4'b0000),
    .o_Segment1_A(), .o_Segment1_B(), .o_Segment1_C(), .o_Segment1_D(),
    .o_Segment1_E(), .o_Segment1_F(), .o_Segment1_G(),
    .o_Segment2_A(), .o_Segment2_B(), .o_Segment2_C(), .o_Segment2_D(),
    .o_Segment2_E(), .o_Segment2_F(), .o_Segment2_G(),
    .i_SPI_SCLK(sclk), .i_SPI_MOSI(mosi), .i_SPI_CS_n(cs_n), .o_SPI_MISO(miso));

  // Lee la serie de precios (CSV "tick,price")
  int precio [20000];

  task automatic leer_serie;
    int fd, t, r;
    string encabezado;
    fd = $fopen(SERIE, "r");
    if (fd == 0) begin $display("ERROR: no se encontro %s", SERIE); $finish; end
    r = $fgets(encabezado, fd);
    for (int n = 0; n < NTICKS; n++) r = $fscanf(fd, "%d,%d\n", t, precio[n]);
    $fclose(fd);
  endtask

  // SPI modo 0: envía el precio y recibe la decisión
  int bits_x = 0;

  task automatic spi(input logic [7:0] enviar, output logic [7:0] recibido);
    cs_n = 0;
    #1000;
    for (int b = 7; b >= 0; b--) begin
      mosi = enviar[b];
      #500 sclk = 1;
      if (miso !== 1'b0 && miso !== 1'b1) bits_x++;
      recibido[b] = (miso === 1'b1);
      #500 sclk = 0;
    end
    #500 cs_n = 1;
  endtask

  // Contabilidad oficial
  int caja = CAJA0, acciones = 0, w = CAJA0, peak = CAJA0, max_dd = 0;
  int ordenes = 0;

  task automatic ejecutar(input logic [7:0] decision, input int p);
    int q = decision[5:0];
    case (decision[7:6])
      2'b01: begin                                         // comprar lo que alcance
        if (q > (caja - COMISION) / p) q = (caja - COMISION) / p;
        if (q > 0) begin caja -= q * p + COMISION; acciones += q; ordenes++; end
      end
      2'b10: begin                                         // vender lo que se tenga
        if (q > acciones) q = acciones;
        if (q > 0 && caja + q * p >= COMISION) begin caja += q * p - COMISION; acciones -= q; ordenes++; end
      end
      default: ;                                           // 00 y 11: mantener
    endcase
    w = caja + acciones * p;
    if (w > peak) peak = w;
    if (peak - w > max_dd) max_dd = peak - w;
  endtask

  // Mide los ciclos entre que llega el precio y el programa escribe DECISION
  int ciclos = 0, peor_caso = 0, respuestas = 0, precios_perdidos = 0;
  bit esperando = 0;

  always @(posedge clk) begin
    ciclos++;
    if (dut.u_spi.byte_done) begin
      if (dut.u_spi.new_price_q) precios_perdidos++;      // el precio anterior no se leyó
      ciclos = 0;
      esperando = 1;
    end else if (esperando && dut.u_spi.wr && dut.u_spi.off == 2) begin
      if (ciclos > peor_caso) peor_caso = ciclos;
      respuestas++;
      esperando = 0;
    end
  end

  // Chequeos
  int total_tests = 0, tests_aprobados = 0;

  task automatic chequear(input bit ok, input string nombre);
    total_tests++;
    if (ok) begin tests_aprobados++; $display("PASS %s", nombre); end
    else $display("FAIL %s", nombre);
  endtask

  // Simulación
  logic [7:0] decision;
  int fd, ref_q, ref_w, presupuesto;

  initial begin
    leer_serie();
    fd = $fopen("decisiones.csv", "w");
    $fdisplay(fd, "tick,precio,decision,caja,acciones,patrimonio");
    #4000;

    for (int n = 0; n < NTICKS; n++) begin
      spi(precio[n], decision);                            // decisión tomada con el precio anterior
      ejecutar(decision, precio[n]);                       // se ejecuta al precio actual
      $fdisplay(fd, "%0d,%0d,%02h,%0d,%0d,%0d", n, precio[n], decision, caja, acciones, w);
      #(PERIODO_NS - SPI_NS);
    end
    $fclose(fd);

    ref_q       = (CAJA0 - COMISION) / precio[0];
    ref_w       = CAJA0 - COMISION - ref_q * precio[0] + ref_q * precio[NTICKS - 1];
    presupuesto = (PERIODO_NS - SPI_NS) / 40;

    $display("Patrimonio final:          %0d", w);
    $display("Ordenes ejecutadas:        %0d", ordenes);
    $display("Perdida maxima:            %0d", max_dd);
    $display("No operar:                 %0d", CAJA0);
    $display("Comprar y mantener:        %0d", ref_w);
    $display("Peor caso precio->decision: %0d ciclos (disponibles: %0d)", peor_caso, presupuesto);
    $display("Detalle por tick en decisiones.csv");

    chequear(bits_x == 0,           "MISO sin valores X");
    chequear(respuestas > 0,        "el programa escribe DECISION");
    chequear(precios_perdidos == 0, "el programa lee todos los precios");
    chequear(peor_caso < presupuesto, "la decision llega antes del siguiente tick");

    $display("Testbenchs aprobados: %0d/%0d", tests_aprobados, total_tests);
    $finish;
  end

endmodule
