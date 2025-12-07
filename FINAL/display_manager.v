`timescale 1ns / 1ps
module display_manager (
    input wire clock,
    input wire reset,
    input wire [15:0] temp_in,
    input wire [15:0] hum_in,
    input wire lcd_ready_in,  //EL controller está libre
    output reg [7:0] lcd_data_out, //Byte a enviar
    output reg lcd_write_char, //Escrirbir carácter
    output reg lcd_write_cmd //Ejecutar comando
);

    // --- Conversión bianrio a Ascii ---

// Si temp_in = 25
// tens_digit = 25 / 10 = 2
// ones_digit = 25 % 10 = 5
// ASCII = Dígito + 0x30 

    wire [6:0] temp_val = temp_in[6:0];
    wire [3:0] temp_tens_digit = temp_val / 10;
    wire [3:0] temp_ones_digit = temp_val % 10;
    wire [7:0] temp_tens_ascii = temp_tens_digit + 8'h30;
    wire [7:0] temp_ones_ascii = temp_ones_digit + 8'h30;

    wire [6:0] hum_val = hum_in[6:0];
    wire [3:0] hum_tens_digit = hum_val / 10;
    wire [3:0] hum_ones_digit = hum_val % 10;
    wire [7:0] hum_tens_ascii = hum_tens_digit + 8'h30;
    wire [7:0] hum_ones_ascii = hum_ones_digit + 8'h30;

    // --- El Buffer (ROM implementado como un MUX) ---
    // Esta sección define qué se muestra en cada casilla de la LCD (0 a 31).
    // Es una tabla de búsqueda (Look-Up Table).

    reg [7:0] data_to_send;

    always @(*) begin
        case (char_index)
            // --- Línea 1: "Temp: xx C" ---
            0:  data_to_send = "T";
            1:  data_to_send = "e";
            2:  data_to_send = "m";
            3:  data_to_send = "p";
            4:  data_to_send = ":";
            5:  data_to_send = " ";
            6:  data_to_send = temp_tens_ascii;
            7:  data_to_send = temp_ones_ascii;
            8:  data_to_send = " ";
            9:  data_to_send = "C";
            10: data_to_send = " ";
            11: data_to_send = " ";
            12: data_to_send = " ";
            13: data_to_send = " ";
            14: data_to_send = " ";
            15: data_to_send = " ";
            
            // --- Línea 2: "Hum: xx %" ---
            16: data_to_send = "H";
            17: data_to_send = "u";
            18: data_to_send = "m";
            19: data_to_send = ":";
            20: data_to_send = " ";
            21: data_to_send = hum_tens_ascii;
            22: data_to_send = hum_ones_ascii;
            23: data_to_send = " ";
            24: data_to_send = "%";
            25: data_to_send = " ";
            26: data_to_send = " ";
            27: data_to_send = " ";
            28: data_to_send = " ";
            29: data_to_send = " ";
            30: data_to_send = " ";
            31: data_to_send = " ";
            
            default: data_to_send = "?";
        endcase
    end

    // --- 3. La FSM principal (CON POSICIONAMIENTO EXPLÍCITO) ---
    
    localparam IDLE = 0;
    localparam GOTO_LINE_1_CMD = 1;   // Posicionar en línea 1
    localparam WAIT_LINE1_ACK = 2;    // Esperar que el controlador acepte
    localparam WAIT_LINE1_FINISH = 3; // Esperar que el controlador termine I2C
    localparam SET_DATA = 4;          // Preparar carácter
    localparam ASSERT_REQ = 5;        // Solicitar envío
    localparam WAIT_FINISH = 6;       // Esperar fin de envío
    localparam GOTO_LINE_2_CMD = 7;   // Mover cursor a la segunda línea
    localparam WAIT_CMD_ACK = 8;
    localparam WAIT_CMD_FINISH = 9;

    reg [3:0] state = IDLE;  
    reg [4:0] char_index = 0;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            char_index <= 0;
            lcd_data_out <= 0;
            lcd_write_char <= 0;
            lcd_write_cmd <= 0;       
        end
        else begin
            lcd_write_char <= 0;
            lcd_write_cmd <= 0;
            
            case(state)
                IDLE: begin
                    if (lcd_ready_in) begin
                        //Posicionar en línea 1
                        state <= GOTO_LINE_1_CMD;
                        char_index <= 0;
                    end
                end
                
                GOTO_LINE_1_CMD: begin
                    lcd_data_out <= 8'h80;  // Comando: DDRAM address 0x00 (línea 1, columna 0)
                    state <= WAIT_LINE1_ACK;
                end

                WAIT_LINE1_ACK: begin
                    lcd_write_cmd <= 1;  // Activar señal de comando
                    if (!lcd_ready_in) begin
                        state <= WAIT_LINE1_FINISH;
                    end
                end
                
                WAIT_LINE1_FINISH: begin
                    if (lcd_ready_in) begin
                        state <= SET_DATA;  // Ahora sí escribir caracteres
                    end
                end
                
                SET_DATA: begin
                    // 1. Poner el dato seleccionado por el ROM en el cable
                    lcd_data_out <= data_to_send;
                    // 2. Ir a pedir que lo escriban
                    state <= ASSERT_REQ;
                end
                
                ASSERT_REQ: begin
                    // 3. Activar la señal "write_char"
                    lcd_write_char <= 1;
                    
                    // 4. Esperar el "ACK" (reconocimiento)
                    if (!lcd_ready_in) begin
                        state <= WAIT_FINISH;
                    end
                end
                
                WAIT_FINISH: begin
                    // 5. Esperar a que el trabajador TERMINE (ready=1)
                    if (lcd_ready_in) begin
                        // Avanzar al siguiente carácter
                        char_index <= char_index + 1;
                        
                        if (char_index == 15) begin
                            // Terminamos línea 1, ir a línea 2
                            state <= GOTO_LINE_2_CMD;
                        end
                        else if (char_index == 31) begin
                            // Terminamos todo, volver a empezar
                            state <= IDLE;
                        end
                        else begin
                            // Siguiente carácter
                            state <= SET_DATA;
                        end
                    end
                end
                
                // --- Lógica para el Comando de Línea 2 ---
                
                GOTO_LINE_2_CMD: begin
                    lcd_data_out <= 8'hC0;  // Comando: DDRAM address 0x40 (línea 2, columna 0)
                    state <= WAIT_CMD_ACK;
                end

                WAIT_CMD_ACK: begin
                    lcd_write_cmd <= 1;
                    if (!lcd_ready_in) begin
                        state <= WAIT_CMD_FINISH;
                    end
                end
                
                WAIT_CMD_FINISH: begin
                    if (lcd_ready_in) begin
                        state <= SET_DATA;  // Volver a enviar caracteres
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
