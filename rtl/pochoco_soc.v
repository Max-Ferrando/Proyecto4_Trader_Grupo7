// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
// Authors:
// - Nicolas Villegas <navillegas@miuandes.cl>
// - Grupo 7 (Proyectos 2 a 4)
//
// pochoco_soc - Top-level del Pochoco SoC para la Go Board (iCE40 HX1K).
// [PROYECTO 4] Vuelve a la interfaz del repositorio base (puertos de la placa y
// parametro MemFile) para que tb/tb_proyecto_4.sv del curso lo instancie tal
// cual. Incluye lo que es propio de la placa:
//  * power-on reset: el bitstream carga por_cnt = 0 (valido solo en FPGA),
//  * display de anodo comun: segmentos activos en bajo.
`ifndef POCHOCO_MEMFILE
`define POCHOCO_MEMFILE "sw/trade.hex"
`endif

module pochoco_soc #(
  parameter MemFile = `POCHOCO_MEMFILE
) (
  input  wire       i_Clk,            // 25 MHz

  output wire [3:0] o_LED,
  input  wire [3:0] i_Switch,

  output wire       o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D,
  output wire       o_Segment1_E, o_Segment1_F, o_Segment1_G,
  output wire       o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D,
  output wire       o_Segment2_E, o_Segment2_F, o_Segment2_G,

  input  wire       i_SPI_SCLK,
  input  wire       i_SPI_MOSI,
  input  wire       i_SPI_CS_n,
  output wire       o_SPI_MISO
);

  // Power-on reset (FPGA): el bitstream inicializa por_cnt en 0.
  reg  [3:0] por_cnt = 4'b0;
  always @(posedge i_Clk) begin
    if (por_cnt != 4'hF) por_cnt <= por_cnt + 4'd1;
  end
  wire rst_n = (por_cnt == 4'hF);

  wire [6:0] seg1_o, seg2_o;

  // Core-memory wiring
  wire        instr_req;
  wire [31:0] instr_addr, instr_rdata;

  wire        data_req, data_we;
  wire [3:0]  data_be;
  wire [31:0] data_addr, data_wdata, data_rdata;

  espino_core #(.BootAddr(32'h0000_0000)) u_core (
    .clk_i         (i_Clk),
    .rst_ni        (rst_n),
    .instr_req_o   (instr_req),
    .instr_addr_o  (instr_addr),
    .instr_rdata_i (instr_rdata),
    .data_req_o    (data_req),
    .data_we_o     (data_we),
    .data_be_o     (data_be),
    .data_addr_o   (data_addr),
    .data_wdata_o  (data_wdata),
    .data_rdata_i  (data_rdata)
  );

  wire is_mmio, spi_sel, per_sel;
  assign is_mmio = data_addr[31];
  assign per_sel = is_mmio & ~data_addr[16];
  assign spi_sel = is_mmio &  data_addr[16];

  wire mem_b_req, per_req, spi_req;
  assign mem_b_req = data_req & ~is_mmio;
  assign per_req   = data_req &  per_sel;
  assign spi_req   = data_req &  spi_sel;

  wire [31:0] mem_b_rdata, per_rdata, spi_rdata;

  reg rd_is_per, rd_is_spi;
  always @(posedge i_Clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_is_per <= 1'b0;
      rd_is_spi <= 1'b0;
    end else if (data_req & ~data_we) begin
      rd_is_per <= per_sel;
      rd_is_spi <= spi_sel;
    end
  end
  assign data_rdata = rd_is_per ? per_rdata :
                      rd_is_spi ? spi_rdata : mem_b_rdata;

  pochoco_mem #(.MemFile(MemFile)) u_mem (
    .clk_i     (i_Clk),
    .rst_ni    (rst_n),
    .a_req_i   (instr_req),
    .a_addr_i  (instr_addr),
    .a_rdata_o (instr_rdata),
    .b_req_i   (mem_b_req),
    .b_we_i    (data_we),
    .b_be_i    (data_be),
    .b_addr_i  (data_addr),
    .b_wdata_i (data_wdata),
    .b_rdata_o (mem_b_rdata)
  );

  pochoco_periph u_periph (
    .clk_i     (i_Clk),
    .rst_ni    (rst_n),
    .sel_i     (per_sel),
    .req_i     (per_req),
    .we_i      (data_we),
    .addr_i    (data_addr[7:0]),
    .wdata_i   (data_wdata),
    .rdata_o   (per_rdata),
    .leds_o    (o_LED),
    .btn_i     (i_Switch),
    .seg1_o    (seg1_o),
    .seg2_o    (seg2_o)
  );

  pochoco_spi_slave u_spi (
    .clk_i      (i_Clk),
    .rst_ni     (rst_n),
    .sel_i      (spi_sel),
    .req_i      (spi_req),
    .we_i       (data_we),
    .addr_i     (data_addr[7:0]),
    .wdata_i    (data_wdata),
    .rdata_o    (spi_rdata),
    .spi_sclk_i (i_SPI_SCLK),
    .spi_mosi_i (i_SPI_MOSI),
    .spi_cs_n_i (i_SPI_CS_n),
    .spi_miso_o (o_SPI_MISO)
  );


  // Display de anodo comun: segmento activo en bajo
  assign {o_Segment1_G, o_Segment1_F, o_Segment1_E, o_Segment1_D,
          o_Segment1_C, o_Segment1_B, o_Segment1_A} = ~seg1_o;
  assign {o_Segment2_G, o_Segment2_F, o_Segment2_E, o_Segment2_D,
          o_Segment2_C, o_Segment2_B, o_Segment2_A} = ~seg2_o;

endmodule
