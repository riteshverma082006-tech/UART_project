
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


  output reg  [1:0]        reg_addr,  
  output reg               wr_pulse,  
  output reg               rd_pulse, 
  input  wire [DATA_W-1:0] rd_data   
);

 
  wire addr_in_range = (PADDR[ADDR_W-1:4] == {(ADDR_W-4){1'b0}});

  assign PREADY  = 1'b1;
  assign PSLVERR = PSEL && PENABLE && !addr_in_range;

  always @(*) reg_addr = PADDR[3:2];

  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
      wr_pulse <= 1'b0;
    else
      wr_pulse <= PSEL && PENABLE && PWRITE && addr_in_range;
  end

  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
      rd_pulse <= 1'b0;
    else
      rd_pulse <= PSEL && PENABLE && !PWRITE && addr_in_range;
  end

  always @(*) begin
    if (PSEL && !PWRITE && addr_in_range)
      PRDATA = rd_data;
    else
      PRDATA = {DATA_W{1'b0}};
  end

endmodule
