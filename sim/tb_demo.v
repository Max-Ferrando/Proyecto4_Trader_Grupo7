// tb_demo.v - Comprueba el modo demo: muestra LEDs y display en cada cambio.
`timescale 1ns/1ps
module tb_demo;
  reg clk = 0; always #20 clk = ~clk;
  wire [3:0] led;
  wire s1a,s1b,s1c,s1d,s1e,s1f,s1g;
  game_top dut (.i_Clk(clk), .o_LED(led), .i_Switch(4'b0), .i_SPI_SCLK(1'b0), .i_SPI_MOSI(1'b0),
                .i_SPI_CS_n(1'b1), .o_SPI_MISO());
  reg [3:0] last = 4'hx;
  always @(posedge clk) if (led !== last) begin
    $display("t=%0d ciclos  LEDs=%b  precio=%0d  decision=%02x", $time/40, led,
             dut.u_soc.u_periph.digit_q, dut.u_soc.u_spi.tx_hold);
    last <= led;
  end
  initial begin #(40*400000); $finish; end
endmodule
