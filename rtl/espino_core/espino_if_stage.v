// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
// 
// Authors:
// - Nicolás Villegas <navillegas@miuandes.cl>

module espino_if_stage #(
  parameter [31:0] BootAddr = 32'h0000_0000
) (
  input  wire        clk_i,
  input  wire        rst_ni,

  input  wire        pc_set_i,
  input  wire [31:0] pc_target_i,
  input  wire        stall_i,

  output wire        instr_req_o,
  output wire [31:0] instr_addr_o,

  output wire [31:0] pc_id_o,
  output wire        instr_valid_id_o
);

  reg  [31:0] pc_q;
  wire [31:0] pc_next;
  reg  [31:0] pc_id_q;
  reg         valid_q;
  wire        valid_d;

  // [PROYECTO 4] PC angosto: la memoria del SoC es de 2 KB, asi que el PC solo
  // necesita ESPINO_PC_BITS bits. Forzar a cero los bits altos permite que la
  // sintesis elimine sus flip-flops y la parte alta de los sumadores PC+4 y
  // PC+inmediato. Sin el define el core queda identico al original (32 bits).
`ifdef ESPINO_PC_BITS
  localparam PcBits = `ESPINO_PC_BITS;
  wire [31:0] pc_next_full = pc_set_i ? pc_target_i : (pc_q + 32'd4);
  assign pc_next = {{(32-PcBits){1'b0}}, pc_next_full[PcBits-1:0]};
`else
  assign pc_next = pc_set_i ? pc_target_i : (pc_q + 32'd4);
`endif
  assign valid_d = ~pc_set_i;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q    <= BootAddr;
      pc_id_q <= BootAddr;
      valid_q <= 1'b0;
    end else if (!stall_i) begin
      pc_q    <= pc_next;
      pc_id_q <= pc_q;
      valid_q <= valid_d;
    end
  end

  assign instr_req_o      = ~stall_i;
  assign instr_addr_o     = pc_q;
  assign pc_id_o          = pc_id_q;
  assign instr_valid_id_o = valid_q;

endmodule