module uart (input clk ,reset,
input d,ready,
output reg [7:0] data,output reg done
);

//parameter
parameter baud_rate =9600 ;
parameter clkperbits=5208;
reg [12:0] counter;
parameter S0=2'b00 , S1=2'b01 , S2=2'b10, S3=2'b11;
reg [1:0] state ; 
integer i ;


always@(posedge clk or negedge reset) begin 

if(!reset) begin 
    i<=0;
    done<=0;
    counter<=0;
    data<=0;
    state<=S0;
    end

else begin 


case(state) 

S0:begin //idle
    if(ready)
    state<=S1;
    else
    state<=S0;
end

S1:begin //start
    if(counter<(clkperbits/2)-1)begin
        state<=S1;
        counter<=counter+1;
    end
    else begin
        state<=S2;
        counter<=0;
        i<=0;
    end
end

S2:begin //data
    if(i<8)begin
        if(counter<clkperbits-1)begin
            state<=S2;
            counter<=counter+1;
        end
        else begin
            state<=S2;
            data[i] <=d;
            i<=i+1;
            counter<=0;
        end
    end
    else begin
        if(d==1 && (counter==clkperbits-1)) begin
        done<=1;
        counter<=0;
        state<=S3;
        end

        else if(d==0 && counter<clkperbits-1) begin
        state<=S2;
            counter<=counter+1;
            state<=S2;
        end

        else if(d==0 && counter==clkperbits-1) begin
        done<=0;
        counter<=0;
        state<=S0;
    end

    else begin
        state<=S2;
        counter<=counter+1;
    end
end
end

S3:begin //stop
    if(d==1 && (counter==clkperbits-1) ) begin
        done<=0;
        counter<=0;
        state<=S0;
    end
    else if (d==0 && counter < clkperbits-1)  begin
    state<=S3;
    counter<=counter+1;
    end

    else begin
        done<=0;
        counter<=0;
        state<=S0;
    end
end

default: state <= S0;
endcase

end
end

endmodule