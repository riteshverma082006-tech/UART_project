`timescale 1ns/1ps

module tb_uart;

    // Reduced clkperbits for fast simulation (real design uses 5208)
    parameter CLKPERBITS = 20;

    reg clk;
    reg reset;
    reg d;
    reg ready;
    wire [7:0] data;
    wire done;

    // DUT instantiation with overridden clkperbits
    uart #(.clkperbits(CLKPERBITS)) dut (
        .clk    (clk),
        .reset  (reset),
        .d      (d),
        .ready  (ready),
        .data   (data),
        .done   (done)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    task send_byte(input [7:0] tx_byte);
        integer j;
        begin
            @(posedge clk);
            ready = 1;
            @(posedge clk);
            ready = 0;

            // Start bit
            d = 0;
            repeat (CLKPERBITS/2) @(posedge clk);

            // Data bits, LSB first
            for (j = 0; j < 8; j = j + 1) begin
                d = tx_byte[j];
                repeat (CLKPERBITS) @(posedge clk);
            end

            // Stop bit - first pass latches 'done'
            d = 1;
            repeat (CLKPERBITS) @(posedge clk);

            // Second pass clears 'done', returns FSM to S0
            repeat (CLKPERBITS) @(posedge clk);
        end
    endtask

    initial begin
        reset = 0;
        ready = 0;
        d     = 1;   // idle line is high

        // Async active-low reset
        repeat (3) @(posedge clk);
        reset = 1;
        repeat (3) @(posedge clk);

        send_byte(8'hA5);
        repeat (5) @(posedge clk);

        send_byte(8'h3C);
        repeat (5) @(posedge clk);

        send_byte(8'hFF);
        repeat (5) @(posedge clk);

        send_byte(8'h00);
        repeat (5) @(posedge clk);

        $display("Testbench completed");
        $finish;
    end

    always @(posedge clk) begin
        if (done)
            $display("[%0t] RX complete: data = 0x%0h (%0b)", $time, data, data);
    end

    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, tb_uart);
    end

endmodule