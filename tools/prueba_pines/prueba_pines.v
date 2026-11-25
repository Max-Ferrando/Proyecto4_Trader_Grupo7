// prueba_pines.v - Prueba de la conexion fisica con la FPGA maestra.
// Reemplaza al Pochoco SoC: no hay procesador, solo mira los cables del PMOD.
//
//   LED 1: se enciende (y queda encendido) si alguna vez CS_n bajo a 0
//   LED 2: se enciende si alguna vez hubo un flanco en SCLK
//   LED 3: se enciende si alguna vez MOSI estuvo en 1
//   LED 4: parpadea en cada transaccion (cambia de estado con cada CS_n que baja)
//   Display: cantidad de transacciones (CS_n que bajan), modulo 256, en hexadecimal
//   MISO: responde siempre 0x41 (comprar 1 accion) para probar la linea de vuelta
//
// Boton 1 (SW1): borra los LEDs y el contador.
module prueba_pines (
  input  wire       i_Clk,
  input  wire [3:0] i_Switch,
  output wire [3:0] o_LED,
  output wire       o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D,
  output wire       o_Segment1_E, o_Segment1_F, o_Segment1_G,
  output wire       o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D,
  output wire       o_Segment2_E, o_Segment2_F, o_Segment2_G,
  input  wire       i_SPI_SCLK,
  input  wire       i_SPI_MOSI,
  input  wire       i_SPI_CS_n,
  output wire       o_SPI_MISO
);
  reg [2:0] sclk_s = 0, cs_s = 3'b111, mosi_s = 0;
  always @(posedge i_Clk) begin
    sclk_s <= {sclk_s[1:0], i_SPI_SCLK};
    cs_s   <= {cs_s[1:0],   i_SPI_CS_n};
    mosi_s <= {mosi_s[1:0], i_SPI_MOSI};
  end
  wire cs_fall = cs_s[2] & ~cs_s[1];
  wire sclk_edge = sclk_s[2] ^ sclk_s[1];

  reg seen_cs = 0, seen_sclk = 0, seen_mosi = 0, blink = 0;
  reg [7:0] count = 0;
  always @(posedge i_Clk) begin
    if (i_Switch[0]) begin
      seen_cs <= 0; seen_sclk <= 0; seen_mosi <= 0; count <= 0;
    end else begin
      if (!cs_s[1]) seen_cs <= 1;
      if (sclk_edge) seen_sclk <= 1;
      if (mosi_s[1]) seen_mosi <= 1;
      if (cs_fall) begin count <= count + 1; blink <= ~blink; end
    end
  end
  assign o_LED = {blink, seen_mosi, seen_sclk, seen_cs};

  // MISO: desplaza 0x41 en modo 0 (cambia en el flanco de bajada de SCLK)
  reg [7:0] tx = 8'h41;
  always @(posedge i_Clk) begin
    if (cs_fall) tx <= 8'h41;
    else if (!cs_s[1] && sclk_s[2] && !sclk_s[1]) tx <= {tx[6:0], 1'b0};
  end
  assign o_SPI_MISO = cs_s[1] ? 1'b0 : tx[7];

  function [6:0] hex2seg(input [3:0] h);
    case (h)
      4'h0: hex2seg = 7'b0111111; 4'h1: hex2seg = 7'b0000110; 4'h2: hex2seg = 7'b1011011;
      4'h3: hex2seg = 7'b1001111; 4'h4: hex2seg = 7'b1100110; 4'h5: hex2seg = 7'b1101101;
      4'h6: hex2seg = 7'b1111101; 4'h7: hex2seg = 7'b0000111; 4'h8: hex2seg = 7'b1111111;
      4'h9: hex2seg = 7'b1101111; 4'hA: hex2seg = 7'b1110111; 4'hB: hex2seg = 7'b1111100;
      4'hC: hex2seg = 7'b0111001; 4'hD: hex2seg = 7'b1011110; 4'hE: hex2seg = 7'b1111001;
      default: hex2seg = 7'b1110001;
    endcase
  endfunction
  wire [6:0] s1 = hex2seg(count[7:4]), s2 = hex2seg(count[3:0]);
  assign {o_Segment1_G, o_Segment1_F, o_Segment1_E, o_Segment1_D, o_Segment1_C, o_Segment1_B, o_Segment1_A} = ~s1;
  assign {o_Segment2_G, o_Segment2_F, o_Segment2_E, o_Segment2_D, o_Segment2_C, o_Segment2_B, o_Segment2_A} = ~s2;
endmodule
