// ---------------------------------------------------------------
// uart_apb_wrapper.v
//
// Memory-mapped APB slave wrapper around an existing UART TX/RX
// core. This module owns all UART-specific register semantics;
// apb_slave.v stays a generic, reusable bus-protocol shim.
//
// Register map (word-aligned, byte offsets from base address):
//   0x00  TX_DATA   (WO)  bits[7:0]  = byte to transmit. Writing this
//                         register pulses uart_tx_start for one cycle.
//   0x04  RX_DATA   (RO)  bits[7:0]  = last received byte. Reading
//                         this register pulses uart_rx_clear, acking
//                         the byte (classic read-to-clear behavior).
//   0x08  STATUS    (RO)  bit0 = tx_busy, bit1 = rx_valid,
//                         bit2 = frame_err
//   0x0C  CONTROL   (RW)  bits[15:0] = baud_div, bit16 = enable
//
// *** PORT NAMES BELOW ARE PLACEHOLDERS ***
// Swap uart_tx_*/uart_rx_* for whatever your existing UART core's
// ports are actually called, and double check the tx_start pulse
// timing assumption noted above uart_tx_start (some UART cores want
// a single-cycle pulse, others want the start signal held until
// tx_busy rises — check your core before wiring this up).
// ---------------------------------------------------------------
module uart_apb_wrapper #(
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
  output wire [DATA_W-1:0] PRDATA,
  output wire              PREADY,
  output wire              PSLVERR,

  // --- UART core ports (placeholders — rename to match your core) ---
  output reg  [7:0]        uart_tx_data,
  output reg               uart_tx_start,   // pulse: load + start transmit
  input  wire              uart_tx_busy,

  input  wire [7:0]        uart_rx_data,
  input  wire              uart_rx_valid,   // high when a byte has arrived
  output reg               uart_rx_clear,   // pulse: ack / clear rx_valid
  input  wire              uart_frame_err,

  output reg  [15:0]       uart_baud_div,
  output reg               uart_enable
);

  localparam ADDR_TXDATA  = 2'b00;
  localparam ADDR_RXDATA  = 2'b01;
  localparam ADDR_STATUS  = 2'b10;
  localparam ADDR_CONTROL = 2'b11;

  wire              reg_addr_valid; // unused placeholder to avoid lint warnings
  wire [1:0]        reg_addr;
  wire              wr_pulse, rd_pulse;
  reg  [DATA_W-1:0] rd_data;

  apb_slave #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_apb (
    .PCLK     (PCLK),
    .PRESETn  (PRESETn),
    .PADDR    (PADDR),
    .PSEL     (PSEL),
    .PENABLE  (PENABLE),
    .PWRITE   (PWRITE),
    .PWDATA   (PWDATA),
    .PRDATA   (PRDATA),
    .PREADY   (PREADY),
    .PSLVERR  (PSLVERR),
    .reg_addr (reg_addr),
    .wr_pulse (wr_pulse),
    .rd_pulse (rd_pulse),
    .rd_data  (rd_data)
  );

  assign reg_addr_valid = 1'b1; // tie-off, silences "unused" lint noise

  // ---- WRITE side ----
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      uart_tx_data  <= 8'h0;
      uart_tx_start <= 1'b0;
      uart_baud_div <= 16'h0;
      uart_enable   <= 1'b0;
    end else begin
      uart_tx_start <= 1'b0; // default low; only pulses high for 1 cycle below

      if (wr_pulse) begin
        case (reg_addr)
          ADDR_TXDATA: begin
            uart_tx_data  <= PWDATA[7:0];
            uart_tx_start <= 1'b1;
          end
          ADDR_CONTROL: begin
            uart_baud_div <= PWDATA[15:0];
            uart_enable   <= PWDATA[16];
          end
          default: ; // RX_DATA (01) and STATUS (10) are read-only
        endcase
      end
    end
  end

  // ---- READ side ----
  // Read-to-clear: reading RX_DATA acks the byte and drops rx_valid.
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
      uart_rx_clear <= 1'b0;
    else
      uart_rx_clear <= rd_pulse && (reg_addr == ADDR_RXDATA);
  end

  always @(*) begin
    case (reg_addr)
      ADDR_TXDATA:  rd_data = {DATA_W{1'b0}}; // write-only, reads as 0
      ADDR_RXDATA:  rd_data = {{(DATA_W-8){1'b0}}, uart_rx_data};
      ADDR_STATUS:  rd_data = {{(DATA_W-3){1'b0}},
                                 uart_frame_err, uart_rx_valid, uart_tx_busy};
      ADDR_CONTROL: rd_data = {{(DATA_W-17){1'b0}}, uart_enable, uart_baud_div};
      default:      rd_data = {DATA_W{1'b0}};
    endcase
  end

endmodule
