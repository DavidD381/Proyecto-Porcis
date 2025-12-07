module PRUEBA004 (
    input wire clk,        // 50MHz
    input wire reset_n,    // Reset activo en BAJO (0 = reset, 1 = normal)
    output reg tx,          // Conectar a HC-05 RXD
    output reg vent,
    input wire [15:0] temp_in, 
    input wire [15:0] hum_in
);


    // Parámetros para 9600 baud con 50MHz
    localparam CLKS_PER_BIT = 5208;
    localparam ONE_SEC = 50_000_000;

    localparam TEMP_MAX = 16'd24; 
    localparam TEMP_MIN = 16'd14;
    localparam HUM_MAX = 16'd80;
    localparam HUM_MIN = 16'd60;

    
    wire t_alta = (temp_in > TEMP_MAX);
    wire t_baja = (temp_in < TEMP_MIN);
    wire h_alta = (hum_in > HUM_MAX);
    wire h_baja = (hum_in < HUM_MIN);
    wire es_ideal = (!t_alta && !t_baja && !h_alta && !h_baja);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) 
            vent <= 1'b0;
        else begin
            // Si temp alta O humedad alta -> Prender
            if (t_alta || h_alta) 
                vent <= 1'b1;
            else 
                vent <= 1'b0;
        end
    end



    reg [63: 0] msg_t_alta = "T Alta\n";
    reg [63: 0] msg_t_baja = "T Baja\n";
    reg [63: 0] msg_h_alta = "H Alta\n";
    reg [63: 0] msg_h_baja = "H Baja\n";
    reg [63:0] msg_ideal  = "Ideal \n";
    reg [2:0] msg_selector = 0;

    reg t_alta_save = 0;
    reg t_baja_save = 0;
    reg h_alta_save = 0;
    reg h_baja_save = 0;
    

    reg [2:0] current_msg_step = 0;
    
    // Estados UART
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;
    
    reg [1:0] uart_state = IDLE;
    reg [12:0] clk_count = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] tx_byte = 0;
    
    // Control de envío
    reg [25:0] timer = 0;
    reg [2:0] char_index = 0;
    reg [15:0] char_delay = 0;
    reg sending_msg = 0;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin  // Reset cuando reset_n = 0
            tx <= 1'b1;
            uart_state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            timer <= 0;
            char_index <= 0;
            char_delay <= 0;
            sending_msg <= 0;
        end
        else begin
            // Temporizador de 1 segundo
            if (!sending_msg) begin
                if (timer < ONE_SEC - 1) begin
                    timer <= timer + 1;
                end
                else begin
                    timer <= 0;

                    t_alta_save <= t_alta;
                    t_baja_save <= t_baja;
                    h_alta_save <= h_alta;
                    h_baja_save <= h_baja;


                    char_index <= 7;
                    sending_msg <= 1;
                    current_msg_step <= 1;
                end
            end
            
            // Máquina de estados UART
            case(uart_state)

                IDLE: begin 
                    tx <= 1'b1;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (sending_msg) begin
                        if (char_delay == 0) begin
                            case (current_msg_step)
                            1: begin 
                                if (t_alta_save) begin  
                                tx_byte <= msg_t_alta[(char_index*8) +: 8];
                                end

                                else begin 
                                    current_msg_step <= 2; 
                                    char_index <= 7; 
                                end // Saltar
                            end

                            2: begin
                                if (t_baja_save) begin  
                                    tx_byte <= msg_t_baja[(char_index*8) +: 8];
                                end
                                else begin 
                                    current_msg_step <= 3;
                                    char_index <= 7; 
                                end // Saltar
                            end

                            3: begin
                                if (h_alta_save) begin  
                                tx_byte <= msg_h_alta[(char_index*8) +: 8];                                end 
                                else begin
                                    current_msg_step <= 4; 
                                    char_index <= 7; 
                                end // Saltar
                            end

                            4: begin
                                if (h_baja_save) begin 
                                tx_byte <= msg_h_baja[(char_index*8) +: 8];
                                end 
                                else begin 
                                    current_msg_step <= 5; 
                                    char_index <= 7; 
                                end // Saltar
                            end
                            5: begin
                                if (!t_alta_save && !t_baja_save && !h_alta_save && !h_baja_save) begin 
                                tx_byte <= msg_ideal[(char_index*8) +: 8];
                                end 
                                else begin 
                                    sending_msg <= 0; 
                                end
                            end

                            default: sending_msg <=0; 

                            endcase
                            if ( (current_msg_step == 1 && t_alta_save) ||
                                (current_msg_step == 2 && t_baja_save) ||
                                (current_msg_step == 3 && h_alta_save) ||
                                (current_msg_step == 4 && h_baja_save) ||
                                (current_msg_step == 5 && !t_alta_save && !t_baja_save && !h_alta_save && !h_baja_save) ) 
                            begin
                                uart_state <= START;
                            end
                        end
                        else begin
                            char_delay <= char_delay -1;
                        end
                    end
                end

                START: begin
                    tx <= 1'b0;  // Start bit
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin 
                        clk_count <= 0; uart_state <= DATA; 
                    end
                end

                DATA: begin
                    tx <= tx_byte[bit_index];
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0;
                        if (bit_index < 7) bit_index <= bit_index + 1;
                        else begin 
                            bit_index <= 0; uart_state <= STOP; 
                        end
                    end
                end

                STOP: begin
                    tx <= 1'b1;  // Stop bit
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0;
                        uart_state <= IDLE;
                        
                        // --- LÓGICA PARA AVANZAR DE LETRA O DE MENSAJE ---
                        if (char_index > 0) begin
                            char_index <= char_index - 1; // Siguiente letra
                            char_delay <= 1000; // Pequeña pausa entre letras
                        end
                        else begin
                            // Se acabó la palabra actual, vamos al siguiente paso (mensaje)
                            current_msg_step <= current_msg_step + 1;
                            char_index <= 7;    // Reiniciar para la siguiente palabra
                            char_delay <= 5000; // Pausa un poco más larga entre mensajes
                        end
                    end
                end

                default: uart_state <= IDLE;
            endcase
        end
    end
endmodule
