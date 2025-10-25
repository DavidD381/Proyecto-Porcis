module i2c_clock #(
    parameter CLK_FREQ = 50_000_000,
    parameter I2C_FREQ = 100_000
)(
    input wire clk,
    input wire rst_n,
    input wire enable,
    output reg i2c_clk,
    output reg i2c_clk_tick
);
    // Calcular divisor explícitamente
    localparam DIVIDER = CLK_FREQ / (2 * I2C_FREQ);  // 250
    localparam COUNTER_BITS = 8;  // 8 bits para contar hasta 250
    
    reg [COUNTER_BITS-1:0] counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            i2c_clk <= 1'b1;
            i2c_clk_tick <= 1'b0;
        end
        else if (enable) begin
            if (counter == DIVIDER - 1) begin
                counter <= 0;
                i2c_clk <= ~i2c_clk;
                i2c_clk_tick <= 1'b1;  // Pulso de tick
            end
            else begin
                counter <= counter + 1'b1;  // Usar 1'b1 explícitamente
                i2c_clk_tick <= 1'b0;
            end
        end
        else begin
            counter <= 0;
            i2c_clk <= 1'b1;
            i2c_clk_tick <= 1'b0;
        end
    end
    
endmodule
