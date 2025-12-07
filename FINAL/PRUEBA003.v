`timescale 1ns / 1ps


//Módulo TOP
//Arquitectura:
//1. EL sensor AHT20 obtiene la temperatura y humedad
//2. Display manager 
//3. Se encarga del protocolo i2c para la pantalla
//4. El módulo Bluetooth utiliza el protocolo UART y trnasmite las alertas 


module PRUEBA003 (
    input wire clk,             // Clock de FPGA (50MHz)
    input wire reset_btn,       // Botón de reset (Activo en bajo)
    // --- Bus I2C #1 (Sensor) ---
    inout wire SDA_sensor,      // Serial data line (Inout)
    inout wire SCL_sensor,      // Serial clock line (Controlada por la FPGA)
    
    // --- Bus I2C #2 (LCD) ---
    inout wire SDA_lcd,
    inout wire SCL_lcd,

    //Ventilador y BLuetooth
    output vent,
    output wire tx
    
);

// --- SEÑALES DEL SENSOR ---
wire [15:0] temp_data;
wire [15:0] hum_data;
wire busy_sensor;           // Bandera de sensor ocupado
wire missed_ack_sensor;     //BAndera de error, el sensor no responde

// --- SEÑALES DEL LCD ---
wire [7:0] lcd_data_wire; // Es el byte que se quiere mostrar
wire       lcd_write_char_wire; // "EScribir como carécter"
wire       lcd_write_cmd_wire; // Ejecutar como comando
wire       lcd_ready_wire; //Controller indica que está listo
wire       lcd_busy_lcd; // Controller indica que está ocupado
wire       lcd_missed_ack_lcd; //Error, pantalla no responde

// --- RESET (con tu anti-rebote) ---
reg reset_sync1, reset_sync2, reset;
always @(posedge clk) begin
    reset_sync1 <= ~reset_btn;  // Se invierte la señal
    reset_sync2 <= reset_sync1; // Se sincroniza por medio de flip-flops
    reset <= reset_sync2;
end

// --- INSTANCIA DEL SENSOR AHT20 ---
aht20_controller aht20_inst (
    .clock(clk),
    .reset(reset),
    .SDA(SDA_sensor), 
    .SCL(SCL_sensor),
    .busy(busy_sensor),
    .missed_ack(missed_ack_sensor),
    .temp_data(temp_data),
    .hum_data(hum_data)
);

// --- INSTANCIA DEL SISTEMA LCD ---

// "El que manda" (display_manager)
display_manager manager (
    .clock(clk),
    .reset(reset),
    
    .temp_in(temp_data), //Recibe los datos de temp del sensor
    .hum_in(hum_data), //REcibe los datos de hum del sensor

    .lcd_ready_in(lcd_ready_wire), //Indica sie l controller está libre
    .lcd_data_out(lcd_data_wire), //Indica que escribir
    .lcd_write_char(lcd_write_char_wire), //Da la orden de escribir 
    .lcd_write_cmd(lcd_write_cmd_wire) //Da la orden de ejecutar comando
);

// "El que hace caso" (lcd_controller)
lcd_controller mi_controlador_lcd (
    .clock(clk),
    .reset(reset),

    // Conectado a las salidas del "Jefe"
    .data_in    ( lcd_data_wire ),
    .write_char ( lcd_write_char_wire ),
    .write_cmd  ( lcd_write_cmd_wire ),
    .ready      ( lcd_ready_wire ), //INdica que está libre
    
    // ¡Conectado al bus I2C #2!
    .SDA(SDA_lcd), 
    .SCL(SCL_lcd), 
    
    // Salidas de estado
    .busy(lcd_busy_lcd),
    .missed_ack(lcd_missed_ack_lcd)
);

PRUEBA004 modulo_bluetooth(
    .clk(clk),
    .reset_n(reset_btn),
    .temp_in(temp_data), 
    .hum_in(hum_data),
    .vent(vent),
    .tx(tx)
);
endmodule
