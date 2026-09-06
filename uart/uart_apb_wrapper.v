module uart_apb_wrapper #(
  parameter DATA_W = 32,
  parameter ADDR_W = 32
)(
  input  wire              PCLK,
  input  wire              PRESETn,

  input  wire [ADDR_W-1:0] PADDR,
  input  wire              PSEL,
  input  wire              PENABLE,
  input  wire              PWRITE,
  input  wire [DATA_W-1:0] PWDATA,
  output wire [DATA_W-1:0] PRDATA,
  output wire              PREADY,
  output wire              PSLVERR,
  output wire              uart_txd,
  input  wire              uart_rxd
);
  localparam ADDR_TXDATA  = 2'b00;
  localparam ADDR_RXDATA  = 2'b01;
  localparam ADDR_STATUS  = 2'b10;
  localparam ADDR_CONTROL = 2'b11;
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
  reg enable;
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
      enable <= 1'b0;
    else if (wr_pulse && reg_addr == ADDR_CONTROL)
      enable <= PWDATA[0];
  end
  reg  [7:0] tx_data_reg;
  reg        tx_send_pulse;
  reg        tx_busy;
  wire       tx_done;
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      tx_data_reg   <= 8'h0;
      tx_send_pulse <= 1'b0;
    end else begin
      tx_send_pulse <= 1'b0;
      if (wr_pulse && reg_addr == ADDR_TXDATA) begin
        tx_data_reg   <= PWDATA[7:0];
        tx_send_pulse <= 1'b1;
      end
    end
  end
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
      tx_busy <= 1'b0;
    else if (tx_done)
      tx_busy <= 1'b0;
    else if (tx_send_pulse)
      tx_busy <= 1'b1;
  end
  uart_tx u_tx (
    .clk     (PCLK),
    .reset   (PRESETn),
    .send    (tx_send_pulse),
    .data_in (tx_data_reg),
    .tx      (uart_txd),
    .done    (tx_done)
  );

  // ---- RX start-bit detection ----
  // The raw 'uart' core needs an external 'ready' pulse timed exactly at
  // the start of an incoming start bit -- it does NOT detect the start bit
  // itself. Previously this was tied straight to 'enable' (a level, held
  // high indefinitely once enabled), which only happened to work in the
  // loopback testbench because the TX write landed at a lucky offset.
  // Real, asynchronously-timed traffic would not be reliably received.
  //
  // Fix: synchronize uart_rxd, detect a real falling edge (line idles
  // high, start bit pulls it low), and only recognize it once 'enable'
  // is set. This mirrors the uart_rx_wrapper approach used in the
  // RISC-V SoC integration.
  reg d_sync, d_prev;
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      d_sync <= 1'b1;
      d_prev <= 1'b1;
    end else begin
      d_sync <= uart_rxd;
      d_prev <= d_sync;
    end
  end
  wire start_detect = enable & d_prev & ~d_sync;

  reg rx_ready_pulse;
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
      rx_ready_pulse <= 1'b0;
    else
      rx_ready_pulse <= start_detect;
  end

  reg  [7:0] rx_data_reg;
  reg        rx_valid;
  wire [7:0] rx_data_core;
  wire       rx_done;
  wire       rx_clear_pulse = rd_pulse && (reg_addr == ADDR_RXDATA);
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      rx_data_reg <= 8'h0;
      rx_valid    <= 1'b0;
    end else if (rx_done) begin
      rx_data_reg <= rx_data_core;
      rx_valid    <= 1'b1;
    end else if (rx_clear_pulse) begin
      rx_valid <= 1'b0;
    end
  end
  uart u_rx (
    .clk   (PCLK),
    .reset (PRESETn),
    .d     (d_sync),          
    .ready (rx_ready_pulse),  
    .data  (rx_data_core),
    .done  (rx_done)
  );
  always @(*) begin
    case (reg_addr)
      ADDR_TXDATA:  rd_data = {DATA_W{1'b0}};
      ADDR_RXDATA:  rd_data = {{(DATA_W-8){1'b0}}, rx_data_reg};
      ADDR_STATUS:  rd_data = {{(DATA_W-2){1'b0}}, rx_valid, tx_busy};
      ADDR_CONTROL: rd_data = {{(DATA_W-1){1'b0}}, enable};
      default:      rd_data = {DATA_W{1'b0}};
    endcase
  end
endmodule
