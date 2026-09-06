module uart_tx (
    input clk, reset,
    input send,              
    input [7:0] data_in,     
    output reg tx,          
    output reg done          
);

parameter clkperbits = 5208;            
parameter S0=2'b00, S1=2'b01, S2=2'b10, S3=2'b11;

reg [1:0] state;
reg [12:0] counter;
reg [7:0] data_reg;
integer i;

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        state    <= S0;
        counter  <= 0;
        i        <= 0;
        tx       <= 1'b1;    
        done     <= 1'b0;
        data_reg <= 8'b0;
    end
    else begin
        case (state)
            S0: begin // idle
                tx   <= 1'b1;
                done <= 1'b0;
                counter <= 0;
                i    <= 0;
                if (send) begin
                    data_reg <= data_in; 
                    state    <= S1;
                end
            end

            S1: begin
                tx <= 1'b0;
                if (counter < clkperbits-1) begin
                    counter <= counter + 1;
                end else begin
                    counter <= 0;
                    i       <= 0;
                    state   <= S2;
                end
            end

            S2: begin 
                tx <= data_reg[i];
                if (counter < clkperbits-1) begin
                    counter <= counter + 1;
                end else begin
                    counter <= 0;
                    if (i < 7) begin
                        i <= i + 1;
                    end else begin
                        i     <= 0;
                        state <= S3;
                    end
                end
            end

            S3: begin // stop bit
                tx <= 1'b1;
                if (counter < clkperbits-1) begin
                    counter <= counter + 1;
                end else begin
                    counter <= 0;
                    done    <= 1'b1;
                    state   <= S0;
                end
            end

            default: state <= S0;
        endcase
    end
end

endmodule