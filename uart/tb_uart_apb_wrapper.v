// ---------------------------------------------------------------
// tb_uart_apb_wrapper.v
//
// Loopback testbench: uart_apb_wrapper's TXD is wired directly to
// its own RXD. A byte written to TX_DATA over the (simulated) APB
// bus should come back out through RX_DATA after transmission
// completes.
//
// This exercises your REAL uart_tx.v and uartreciever.v cores (not a
// mock) through the actual register interface — it's the closest
// thing to an end-to-end check we can do without real hardware.
//
// NOTE: this only proves the wrapper's register plumbing is correct
// and that the two cores agree on the wire. It does not independently
// verify the rx core's internal state machine (S1-S3) — if that FSM
// has a bug, this test would only catch it if it causes a wrong byte
// or a timeout, not diagnose it.
//
// Run with (paths assume this repo's flat uart/ folder layout):
//   iverilog -o sim tb_uart_apb_wrapper.v apb_slave.v uart_apb_wrapper.v tx.v uartreciever.v
//   vvp sim
// ---------------------------------------------------------------
`timescale 1ns/1ps

module tb_uart_apb_wrapper;

  localparam DATA_W = 32;
  localparam ADDR_W = 32;

  reg               PCLK;
  reg               PRESETn;
  reg  [ADDR_W-1:0] PADDR;
  reg               PSEL;
  reg               PENABLE;
  reg               PWRITE;
  reg  [DATA_W-1:0] PWDATA;
  wire [DATA_W-1:0] PRDATA;
  wire              PREADY;
  wire              PSLVERR;

  wire              serial_line; // txd looped back to rxd

  integer errors = 0;

  // ---- Clock / reset ----
  initial PCLK = 0;
  always #5 PCLK = ~PCLK; // 100 MHz

  initial begin
    PRESETn = 0;
    repeat (4) @(posedge PCLK);
    PRESETn = 1;
  end

  // ---- DUT ----
  uart_apb_wrapper #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) dut (
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
    .uart_txd (serial_line),
    .uart_rxd (serial_line)   // loopback
  );

  // ---- APB master BFM ----
  task apb_write(input [ADDR_W-1:0] addr, input [DATA_W-1:0] data);
    begin
      @(posedge PCLK);
      PADDR   <= addr;
      PWDATA  <= data;
      PWRITE  <= 1'b1;
      PSEL    <= 1'b1;
      PENABLE <= 1'b0;
      @(posedge PCLK);
      PENABLE <= 1'b1;
      @(posedge PCLK); // ACCESS phase completes here (PREADY tied high)
      PSEL    <= 1'b0;
      PENABLE <= 1'b0;
    end
  endtask

  task apb_read(input [ADDR_W-1:0] addr, output [DATA_W-1:0] data);
    begin
      @(posedge PCLK);
      PADDR   <= addr;
      PWRITE  <= 1'b0;
      PSEL    <= 1'b1;
      PENABLE <= 1'b0;
      @(posedge PCLK);
      PENABLE <= 1'b1;
      @(posedge PCLK);
      data     = PRDATA;
      PSEL    <= 1'b0;
      PENABLE <= 1'b0;
    end
  endtask

  task check(input cond, input [255:0] msg);
    begin
      if (!cond) begin
        $display("FAIL: %0s", msg);
        errors = errors + 1;
      end else begin
        $display("PASS: %0s", msg);
      end
    end
  endtask

  reg [DATA_W-1:0] rdata;

  // clkperbits = 5208 in both cores; 10 bits per frame (start+8+stop)
  // at a 10ns clock period. Generous margin added on top.
  localparam integer BIT_CYCLES   = 5208;
  localparam integer FRAME_CYCLES = 10 * BIT_CYCLES;

  // ---- Test sequence ----
  initial begin
    PADDR = 0; PWDATA = 0; PSEL = 0; PENABLE = 0; PWRITE = 0;

    @(posedge PRESETn);
    repeat (2) @(posedge PCLK);

    // 1) Enable the UART
    apb_write(32'h0C, 32'h1);
    apb_read(32'h0C, rdata);
    check(rdata[0] == 1'b1, "CONTROL.enable readback");

    // 2) Write TX_DATA — should kick off a transmit
    apb_write(32'h00, 32'h000000A5);

    @(posedge PCLK);
    apb_read(32'h08, rdata);
    check(rdata[0] == 1'b1, "STATUS.tx_busy=1 shortly after TX_DATA write");

    // 3) Wait out one full frame time (plus margin) for TX to finish
    //    and for the looped-back RX to receive it.
    repeat (FRAME_CYCLES + 2 * BIT_CYCLES) @(posedge PCLK);

    apb_read(32'h08, rdata);
    check(rdata[0] == 1'b0, "STATUS.tx_busy=0 after transmit completes");
    check(rdata[1] == 1'b1, "STATUS.rx_valid=1 after loopback reception");

    // 4) Read RX_DATA and confirm it matches what was sent
    apb_read(32'h04, rdata);
    check(rdata[7:0] == 8'hA5, "RX_DATA matches transmitted byte (0xA5)");

    // 5) Read-to-clear: rx_valid should drop after reading RX_DATA
    apb_read(32'h08, rdata);
    check(rdata[1] == 1'b0, "STATUS.rx_valid=0 after read-to-clear");

    // 6) Out-of-range address should assert PSLVERR
    @(posedge PCLK);
    PADDR <= 32'h20; PWRITE <= 1'b0; PSEL <= 1'b1; PENABLE <= 1'b0;
    @(posedge PCLK);
    PENABLE <= 1'b1;
    @(posedge PCLK);
    check(PSLVERR == 1'b1, "PSLVERR asserted for out-of-range address");
    PSEL <= 1'b0; PENABLE <= 1'b0;

    // 7) TX_DATA should read back as 0 (write-only)
    apb_read(32'h00, rdata);
    check(rdata == 32'h0, "TX_DATA reads as 0 (write-only)");

    @(posedge PCLK);
    if (errors == 0)
      $display("\nALL TESTS PASSED");
    else
      $display("\n%0d TEST(S) FAILED", errors);

    $finish;
  end

  // Safety timeout in case the loopback never completes
  initial begin
    #(20_000_000);
    $display("\nTIMEOUT — simulation did not finish in time");
    $finish;
  end

endmodule
