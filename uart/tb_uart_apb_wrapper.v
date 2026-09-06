
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

  wire              serial_line;

  integer errors = 0;

  initial PCLK = 0;
  always #5 PCLK = ~PCLK; 

  initial begin
    PRESETn = 0;
    repeat (4) @(posedge PCLK);
    PRESETn = 1;
  end

  
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
    .uart_rxd (serial_line)  
  );

  
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
      @(posedge PCLK); 
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

  
  localparam integer BIT_CYCLES   = 5208;
  localparam integer FRAME_CYCLES = 10 * BIT_CYCLES;

  
  initial begin
    PADDR = 0; PWDATA = 0; PSEL = 0; PENABLE = 0; PWRITE = 0;

    @(posedge PRESETn);
    repeat (2) @(posedge PCLK);

  
    apb_write(32'h0C, 32'h1);
    apb_read(32'h0C, rdata);
    check(rdata[0] == 1'b1, "CONTROL.enable readback");

   
    apb_write(32'h00, 32'h000000A5);

    @(posedge PCLK);
    apb_read(32'h08, rdata);
    check(rdata[0] == 1'b1, "STATUS.tx_busy=1 shortly after TX_DATA write");

  
    repeat (FRAME_CYCLES + 2 * BIT_CYCLES) @(posedge PCLK);

    apb_read(32'h08, rdata);
    check(rdata[0] == 1'b0, "STATUS.tx_busy=0 after transmit completes");
    check(rdata[1] == 1'b1, "STATUS.rx_valid=1 after loopback reception");

 
    apb_read(32'h04, rdata);
    check(rdata[7:0] == 8'hA5, "RX_DATA matches transmitted byte (0xA5)");

    apb_read(32'h08, rdata);
    check(rdata[1] == 1'b0, "STATUS.rx_valid=0 after read-to-clear");

    
    @(posedge PCLK);
    PADDR <= 32'h20; PWRITE <= 1'b0; PSEL <= 1'b1; PENABLE <= 1'b0;
    @(posedge PCLK);
    PENABLE <= 1'b1;
    @(posedge PCLK);
    check(PSLVERR == 1'b1, "PSLVERR asserted for out-of-range address");
    PSEL <= 1'b0; PENABLE <= 1'b0;

 
    apb_read(32'h00, rdata);
    check(rdata == 32'h0, "TX_DATA reads as 0 (write-only)");

    @(posedge PCLK);
    if (errors == 0)
      $display("\nALL TESTS PASSED");
    else
      $display("\n%0d TEST(S) FAILED", errors);

    $finish;
  end

  initial begin
    #(20_000_000);
    $display("\nTIMEOUT — simulation did not finish in time");
    $finish;
  end

endmodule
