// pochoco_mavg.v - Periferico MMIO de sumas moviles (Proyecto 4, co-diseno).
//
// Mantiene en hardware las tres sumas moviles que usa trade.s:
//   SUM20  = suma de los ultimos 20 precios
//   SUM60  = suma de los ultimos 60 precios
//   SUM120 = suma de los ultimos 120 precios
// El Espino sigue leyendo el precio por SPI, decidiendo y escribiendo DECISION:
// este bloque solo reemplaza la actualizacion de las ventanas circulares.
//
// Mapa de registros (base 0x8002_0000), modo normal (variante "mavg"):
//   +0x0  W  PUSH    wdata[7:0] = precio nuevo; inicia la actualizacion
//   +0x0  R  SUM20
//   +0x4  R  SUM60
//   +0x8  R  SUM120
//
// Con `POCHOCO_MAVG_SIG (variante "sig") entrega las dos senales ya combinadas,
// que es lo que trade.s calculaba con cadenas de sumas:
//   +0x0  R  TREND = 6*SUM20 - SUM120 = 120 * (media20 - media120)   (con signo)
//   +0x4  R  MR    = 60*precio - SUM60 = 60 * (precio - media60)     (con signo)
// Multiplicar por 6 y por 60 es solo cableado y sumadores: 6x = 4x + 2x,
// 60x = 64x - 4x.
//
// Historia: 256 precios de 8 bits en una BRAM (1 SB_RAM40_4K) usada como
// anillo. El precio de hace k ticks esta en hist[idx - k] (resta de 8 bits; el
// desborde hace de modulo 256). La BRAM parte en cero, igual que el buffer que
// trade.s limpia por software, asi que el calentamiento es identico.
//
// Actualizacion en 3 ciclos despues de la escritura (una lectura de BRAM por
// ciclo y un solo restador compartido):
//   C0  escritura: hist[idx] <= p; se pide hist[idx-60]
//   C1  SUM60  += p - hist[idx-60];  se pide hist[idx-20]
//   C2  SUM20  += p - hist[idx-20];  se pide hist[idx-120]
//   C3  SUM120 += p - hist[idx-120]; idx <= idx + 1
// Validez: SUM60 y MR desde C2, SUM20 desde C3, SUM120 y TREND desde C4.
// El Espino tarda al menos 2 ciclos por instruccion y 3 por lw, de modo que
// leer en el orden SUM60, SUM20, SUM120 (o MR, TREND) inmediatamente despues
// del sw siempre entrega valores actualizados. tb/tb_mavg.v verifica ese caso.
module pochoco_mavg (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        sel_i,
  input  wire        req_i,
  input  wire        we_i,
  input  wire [7:0]  addr_i,
  input  wire [31:0] wdata_i,
  output reg  [31:0] rdata_o
);
  wire [1:0] off    = addr_i[3:2];
  wire       access = sel_i & req_i;
  wire       push   = access & we_i & (off == 2'd0);

  reg [7:0] hist [0:255];
  integer i;
  initial for (i = 0; i < 256; i = i + 1) hist[i] = 8'd0;

  reg [1:0]  st_q;                 // 0 = reposo, 1..3 = pasos de actualizacion
  reg [7:0]  idx_q;                // posicion donde se escribe el proximo precio
  reg [7:0]  p_q;                  // precio que se esta incorporando
  reg [7:0]  old_q;                // salida registrada de la BRAM
  reg [12:0] sum20_q;              // maximo 20*255  =  5100
  reg [13:0] sum60_q;              // maximo 60*255  = 15300
  reg [14:0] sum120_q;             // maximo 120*255 = 30600

  // Direccion de lectura: el precio que sale de la ventana que toca actualizar
  wire [7:0] tap   = (st_q == 2'd1) ? 8'd20 : (st_q == 2'd2) ? 8'd120 : 8'd60;
  wire [7:0] raddr = idx_q - tap;

  always @(posedge clk_i) begin
    old_q <= hist[raddr];
    if (push) hist[idx_q] <= wdata_i[7:0];
  end

  // delta = precio que entra - precio que sale (con signo, 9 bits)
  wire signed [8:0] delta = {1'b0, p_q} - {1'b0, old_q};

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q     <= 2'd0;
      idx_q    <= 8'd0;
      p_q      <= 8'd0;
      sum20_q  <= 13'd0;
      sum60_q  <= 14'd0;
      sum120_q <= 15'd0;
    end else begin
      case (st_q)
        2'd0: if (push) begin
                p_q  <= wdata_i[7:0];
                st_q <= 2'd1;
              end
        2'd1: begin sum60_q  <= sum60_q  + {{5{delta[8]}}, delta}; st_q <= 2'd2; end
        2'd2: begin sum20_q  <= sum20_q  + {{4{delta[8]}}, delta}; st_q <= 2'd3; end
        2'd3: begin sum120_q <= sum120_q + {{6{delta[8]}}, delta};
                    idx_q    <= idx_q + 8'd1;
                    st_q     <= 2'd0; end
      endcase
    end
  end

`ifdef POCHOCO_MAVG_SIG
  wire signed [17:0] trend = {1'b0, sum20_q, 2'b0} + {2'b0, sum20_q, 1'b0} - {3'b0, sum120_q};
  wire signed [15:0] mr    = {2'b0, p_q, 6'b0} - {6'b0, p_q, 2'b0} - {2'b0, sum60_q};
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rdata_o <= 32'b0;
    else if (access & ~we_i)
      rdata_o <= off[0] ? {{16{mr[15]}}, mr} : {{14{trend[17]}}, trend};
  end
`else
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rdata_o <= 32'b0;
    else if (access & ~we_i) begin
      case (off)
        2'd0:    rdata_o <= {19'b0, sum20_q};
        2'd1:    rdata_o <= {18'b0, sum60_q};
        2'd2:    rdata_o <= {17'b0, sum120_q};
        default: rdata_o <= 32'b0;
      endcase
    end
  end
`endif
endmodule
