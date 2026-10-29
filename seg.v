module seg (
    input wire [7:0] data,
    input clk,
    output reg [7:0] SEG,
    output reg [5:0] DIG
);

reg wei;

reg [15:0]data1;

always@(posedge clk)
begin
     
     case(data[3:0])
        4'h0 : data1[7:0]=~8'b11000000;
        4'h1 : data1[7:0]=~8'b11111001;
        4'h2 : data1[7:0]=~8'b10100100;
        4'h3 : data1[7:0]=~8'b10110000;
        4'h4 : data1[7:0]=~8'b10011001;
        4'h5 : data1[7:0]=~8'b10010010;
        4'h6 : data1[7:0]=~8'b10000010;
        4'h7 : data1[7:0]=~8'b11111000;
        4'h8 : data1[7:0]=~8'b10000000;
        4'h9 : data1[7:0]=~8'b10010000;
        4'ha : data1[7:0]=~8'b10001000;
        4'hb : data1[7:0]=~8'b10000011;
        4'hc : data1[7:0]=~8'b11000110;
        4'hd : data1[7:0]=~8'b10100001;
        4'he : data1[7:0]=~8'b10000110;
        4'hf : data1[7:0]=~8'b10001110;
        default : data1[7:0]=~8'b11000000;
     endcase
     case(data[7:4])
        4'h0 : data1[15:8]=~8'b11000000;
        4'h1 : data1[15:8]=~8'b11111001;
        4'h2 : data1[15:8]=~8'b10100100;
        4'h3 : data1[15:8]=~8'b10110000;
        4'h4 : data1[15:8]=~8'b10011001;
        4'h5 : data1[15:8]=~8'b10010010;
        4'h6 : data1[15:8]=~8'b10000010;
        4'h7 : data1[15:8]=~8'b11111000;
        4'h8 : data1[15:8]=~8'b10000000;
        4'h9 : data1[15:8]=~8'b10010000;
        4'ha : data1[15:8]=~8'b10001000;
        4'hb : data1[15:8]=~8'b10000011;
        4'hc : data1[15:8]=~8'b11000110;
        4'hd : data1[15:8]=~8'b10100001;
        4'he : data1[15:8]=~8'b10000110;
        4'hf : data1[15:8]=~8'b10001110;
        default : data1[15:8]=~8'b11000000;
     endcase


     case(wei)
            2'b00:
                begin DIG=6'b000010; SEG = data1[7:0]; end
            2'b01:
                begin DIG=6'b000001; SEG = data1[15:8]; end
            default:
                begin DIG=6'b000000; wei = 0; end
    endcase
wei=wei+1;
end



endmodule