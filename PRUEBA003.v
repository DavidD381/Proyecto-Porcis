`timescale 1ns / 1ps
module PRUEBA003 (
    input wire clk,             // Clock de FPGA (50MHz)
    input wire reset_btn,       // Botón de reset
    input wire switch_temp_hum, // Switch: 0=Temperatura, 1=Humedad
    
    // --- Bus I2C #1 (Sensor) ---
    inout wire SDA_sensor,
    inout wire SCL_sensor,
    
    // Display 7 segmentos
    output wire [3:0] an,       // Ánodos
    output wire [6:0] seg      // Segmentos
    

);

// --- 1. SEÑALES DEL SENSOR ---
wire [15:0] temp_data;
wire [15:0] hum_data;
wire busy_sensor;
wire missed_ack_sensor;
wire [15:0] display_value;


// --- 2. RESET (con tu anti-rebote) ---
reg reset_sync1, reset_sync2, reset;
always @(posedge clk) begin
    reset_sync1 <= ~reset_btn;  // Invertido porque es activo en bajo
    reset_sync2 <= reset_sync1;
    reset <= reset_sync2;
end

// --- 3. INSTANCIA DEL SENSOR AHT20 ---
aht20_controller aht20_inst (
    .clock(clk),
    .reset(reset),
    .SDA(SDA_sensor), // Conectado al bus #1
    .SCL(SCL_sensor), // Conectado al bus #1
    .busy(busy_sensor),
    .missed_ack(missed_ack_sensor),
    .temp_data(temp_data),
    .hum_data(hum_data)
);

// Selector de valor a mostrar (para el 7-segmentos)
assign display_value = switch_temp_hum ? hum_data : temp_data;

// Instancia del display 7 segmentos
seven_segment_display display_inst (
    .clock(clk),
    .reset(reset),
    .value(display_value),
    .an(an),
    .seg(seg)
);

endmodule
