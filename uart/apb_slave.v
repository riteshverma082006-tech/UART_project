// ---------------------------------------------------------------
// apb_slave.v
//
// Generic APB3 slave bus-protocol layer. Handles the PSEL/PENABLE/
// PWRITE handshake and address decoding only. It knows nothing about
// what the registers *mean* — that semantic logic lives in whichever
// wrapper module instantiates this (see uart_apb_wrapper.v).
//
// 4 word-aligned registers are addressable at offsets 0x00, 0x04,
// 0x08, 0x0C. Any other address asserts PSLVERR.
//
// Zero-wait-state slave: PREADY is tied high. Add wait-state logic
// here later if a register ever needs multi-cycle access.
// ---------------------------------------------------------------
module apb_slave #(
  parameter DATA_W = 32,
  parameter ADDR_W = 32
)(
  input  wire              PCLK,
  input  wire              PRESETn,

  // APB bus
  input  wire [ADDR_W-1:0] PADDR,
  input  wire              PSEL,
  input  wire              PENABLE,
  input  wire              PWRITE,
  input  wire [DATA_W-1:0] PWDATA,
  output reg  [DATA_W-1:0] PRDATA,
  output wire              PREADY,
  output wire              PSLVERR,

  // Internal side — exposed to the wrapper instead of raw storage.
  // This module is a protocol shim, not a register file.
  output reg  [1:0]        reg_addr,  // which of the 4 regs is targeted
  output reg               wr_pulse,  // 1 cycle high on a valid write
  output reg               rd_pulse,  // 1 cycle high on a valid read
  input  wire [DATA_W-1:0] rd_data    // data supplied by wrapper for reads
);

  // Only offsets 0x0-0xC are valid; anything above aliases to an error
  // instead of silently wrapping into one of the 4 registers.
  wire addr_in_range = (PADDR[ADDR_W-1:4] == {(ADDR_W-4){1'b0}});

  assign PREADY  = 1'b1;
  assign PSLVERR = PSEL && PENABLE && !addr_in_range;

  always @(*) reg_addr = PADDR[3:2];

  // Write pulse: one cycle, asserted during the ACCESS phase of a
  // valid write transfer. The wrapper uses this edge to know exactly
  // when PWDATA is valid, rather than sampling combinationally.
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
      wr_pulse <= 1'b0;
    else
      wr_pulse <= PSEL && PENABLE && PWRITE && addr_in_range;
  end

  // Read pulse: one cycle, asserted during the ACCESS phase of a
  // valid read transfer. Used by the wrapper for read-triggered side
  // effects (e.g. clearing RX_VALID on a read of RX_DATA).
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
      rd_pulse <= 1'b0;
    else
      rd_pulse <= PSEL && PENABLE && !PWRITE && addr_in_range;
  end

  // Combinational read data. Sourced from the wrapper's rd_data mux,
  // not from any storage this module owns.
  always @(*) begin
    if (PSEL && !PWRITE && addr_in_range)
      PRDATA = rd_data;
    else
      PRDATA = {DATA_W{1'b0}};
  end

endmodule
