// buscar_pines.v - Detecta en que pines del PMOD hay actividad (SOLO ENTRADAS).
// No maneja ningun pin del PMOD: es seguro conectarlo a la maestra en cualquier posicion.
//
// Display (hexadecimal): mascara de pines que cambiaron alguna vez
//   digito derecho  = pines 1,2,3,4   (bit0 = pin 1 ... bit3 = pin 4)
//   digito izquierdo = pines 7,8,9,10 (bit0 = pin 7 ... bit3 = pin 10)
// LEDs: los pines 1-4 que estan en 0 AHORA MISMO (LED1 = pin 1 ... LED4 = pin 4)
// Boton 1: borra la mascara.
module buscar_pines (
  input  wire       i_Clk,
  input  wire [3:0] i_Switch,
  output wire [3:0] o_LED,
  output wire       o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D,
  output wire       o_Segment1_E, o_Segment1_F, o_Segment1_G,
  output wire       o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D,
  output wire       o_Segment2_E, o_Segment2_F, o_Segment2_G,
  input  wire [7:0] i_PMOD          // [0..3] = pines 1..4, [4..7] = pines 7..10
);
  reg [7:0] s1 = 8'hFF, s2 = 8'hFF, s3 = 8'hFF, act = 0;
  always @(posedge i_Clk) begin
    s1 <= i_PMOD; s2 <= s1; s3 <= s2;
    if (i_Switch[0]) act <= 0;
    else act <= act | (s2 ^ s3);
  end
  assign o_LED = ~s2[3:0];

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
  wire [6:0] d1 = hex2seg(act[7:4]), d2 = hex2seg(act[3:0]);
  assign {o_Segment1_G, o_Segment1_F, o_Segment1_E, o_Segment1_D, o_Segment1_C, o_Segment1_B, o_Segment1_A} = ~d1;
  assign {o_Segment2_G, o_Segment2_F, o_Segment2_E, o_Segment2_D, o_Segment2_C, o_Segment2_B, o_Segment2_A} = ~d2;
endmodule
