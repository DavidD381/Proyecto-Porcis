module sensor_controller(
    input wire clk,           
    input wire rst,           
    inout wire sda,           
    inout wire scl,           
    output reg [15:0] temp_data,   
    output reg [15:0] hum_data,    
    output reg data_ready,
    output wire busy,
    output wire missed_ack
);

// Parámetros del i2c_master
parameter PRESCALE = 16'd124;

// Señales del i2c_master
reg [6:0] cmd_address;
reg cmd_start;
reg cmd_read;
reg cmd_write;
reg cmd_write_multiple;
reg cmd_stop;
reg cmd_valid;
wire cmd_ready;

reg [7:0] data_out;
reg data_out_valid;
wire data_out_ready;
reg data_out_last;

wire [7:0] data_in;
wire data_in_valid;
reg data_in_ready;
wire data_in_last;

wire bus_control;
wire bus_active;

wire scl_i, scl_o, scl_t;
wire sda_i, sda_o, sda_t;

// Instancia del i2c_master (se asume que esta parte es correcta)
i2c_master i2c_master_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_cmd_address(cmd_address),
    .s_axis_cmd_start(cmd_start),
    .s_axis_cmd_read(cmd_read),
    .s_axis_cmd_write(cmd_write),
    .s_axis_cmd_write_multiple(cmd_write_multiple),
    .s_axis_cmd_stop(cmd_stop),
    .s_axis_cmd_valid(cmd_valid),
    .s_axis_cmd_ready(cmd_ready),
    .s_axis_data_tdata(data_out),
    .s_axis_data_tvalid(data_out_valid),
    .s_axis_data_tready(data_out_ready),
    .s_axis_data_tlast(data_out_last),
    .m_axis_data_tdata(data_in),
    .m_axis_data_tvalid(data_in_valid),
    .m_axis_data_tready(data_in_ready),
    .m_axis_data_tlast(data_in_last),
    .scl_i(scl_i),
    .scl_o(scl_o),
    .scl_t(scl_t),
    .sda_i(sda_i),
    .sda_o(sda_o),
    .sda_t(sda_t),
    .busy(busy),
    .bus_control(bus_control),
    .bus_active(bus_active),
    .missed_ack(missed_ack),
    .prescale(PRESCALE),
    .stop_on_idle(1'b1)
);

// Control de pines I2C (open-drain)
assign scl = scl_t ? 1'bz : scl_o;
assign sda = sda_t ? 1'bz : sda_o;
assign scl_i = scl;
assign sda_i = sda;

// Máquina de estados
localparam IDLE                 = 0;
localparam WAIT_40MS            = 1;
localparam CHECK_STATUS         = 2;
localparam WAIT_STATUS          = 3;
localparam INIT_SENSOR          = 4;
localparam SEND_INIT            = 5;
localparam WAIT_10MS            = 6;
localparam TRIGGER_MEAS         = 7;
localparam SEND_TRIGGER         = 8;
localparam WAIT_80MS            = 9;
localparam CHECK_BUSY           = 10; 
localparam WAIT_BUSY            = 11; 
localparam READ_DATA            = 12;
localparam PROCESS_DATA         = 13;
localparam DELAY                = 14;
localparam POST_STATUS_DELAY    = 15; // <--- NUEVO ESTADO

reg [3:0] state;
reg [31:0] counter;
reg [2:0] byte_count;
reg [47:0] sensor_data; 
reg [7:0] status_byte;

// Siempre limpiar los comandos del I2C
always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        counter <= 0;
        cmd_valid <= 0;
        cmd_read <= 0;
        cmd_write <= 0;
        cmd_write_multiple <= 0;
        cmd_start <= 0;
        cmd_stop <= 0;
        data_out_valid <= 0;
        data_in_ready <= 0;
        data_ready <= 0;
        byte_count <= 0;
        status_byte <= 0;
    end else begin
        // Limpiar cmd_valid y cmd_start si el maestro los ha aceptado
        if (cmd_ready && cmd_valid) begin
             cmd_valid <= 0;
             cmd_start <= 0;
        end

        case (state)
            IDLE: begin
                counter <= 0;
                state <= WAIT_40MS;
            end
            
            // 1. Espera 40ms
            WAIT_40MS: begin
                counter <= counter + 1;
                if (counter >= 32'd2_000_000) begin
                    counter <= 0;
                    state <= CHECK_STATUS;
                end
            end
            
            // 2. Enviar el comando 0x71 (Solicitar Estado)
            CHECK_STATUS: begin
                if (!busy && cmd_ready) begin
                    cmd_address <= 7'h38;
                    cmd_start <= 1;
                    cmd_write <= 1; 
                    cmd_read <= 0;
                    cmd_write_multiple <= 0;
                    cmd_stop <= 0; 
                    cmd_valid <= 1;
                    data_out <= 8'h71;
                    data_out_valid <= 1;
                    data_out_last <= 1; 
                    
                    state <= WAIT_STATUS;
                end
            end
            
            WAIT_STATUS: begin  
                // Esperamos que el byte 0x71 se haya escrito
                if (cmd_write && data_out_valid && data_out_ready) begin
                    data_out_valid <= 0;
                    cmd_write <= 0;
                end
                
                // Si la ESCRITURA terminó (bus libre), iniciamos la LECTURA
                if (!busy && cmd_ready && data_out_last) begin 
                    // Solicitamos RESTART (cmd_start) + Lectura de 1 byte + STOP
                    cmd_address <= 7'h38;
                    cmd_start <= 1; 
                    cmd_read <= 1;
                    cmd_stop <= 1;
                    cmd_valid <= 1;
                    data_in_ready <= 1;
                    data_out_last <= 0; // Reset
                end
                
                // Si la LECTURA terminó (data_in_valid)
                if (data_in_valid && data_in_ready) begin
                    status_byte <= data_in;
                    data_in_ready <= 0;
                    cmd_valid <= 0;
                    cmd_start <= 0;
                    cmd_read <= 0;
                    cmd_stop <= 0;
                    
                    // La transición va al nuevo estado de limpieza
                    state <= POST_STATUS_DELAY; 
                end
            end

            // *** NUEVO ESTADO DE LIMPIEZA ***
            POST_STATUS_DELAY: begin
                counter <= counter + 1;
                // Espera unos pocos ciclos para limpiar las señales de bus
                if (counter >= 32'd10) begin 
                    counter <= 0;
                    
                    // Aquí re-evaluamos la calibración, si es necesario
                    if (status_byte[3] == 1'b0) begin
                        state <= INIT_SENSOR;
                    end else begin
                        state <= TRIGGER_MEAS;
                    end
                end
            end
            // *** FIN NUEVO ESTADO ***
            
            // 3. Inicialización (0xBE, 0x08, 0x00)
            INIT_SENSOR: begin
                if (!busy && cmd_ready) begin
                    cmd_address <= 7'h38;
                    cmd_start <= 1;
                    cmd_write_multiple <= 1;
                    cmd_stop <= 0;
                    cmd_valid <= 1;
                    data_out <= 8'hBE;
                    data_out_valid <= 1;
                    data_out_last <= 0;
                    byte_count <= 0;
                    state <= SEND_INIT;
                end
            end
            
            SEND_INIT: begin
                if (data_out_ready && data_out_valid) begin
                    data_out_valid <= 0;
                    
                    if (byte_count == 0) begin
                        data_out <= 8'h08;
                        data_out_valid <= 1;
                        data_out_last <= 0;
                        byte_count <= 1;
                    end else if (byte_count == 1) begin
                        data_out <= 8'h00;
                        data_out_valid <= 1;
                        data_out_last <= 1;
                        cmd_stop <= 1;
                        cmd_valid <= 1;
                        byte_count <= 2;
                    end
                end
                
                if (byte_count == 2 && !data_out_valid && cmd_ready) begin
                    cmd_valid <= 0;
                    cmd_stop <= 0;
                    cmd_write_multiple <= 0;
                    state <= WAIT_10MS;
                    counter <= 0;
                end
            end
            
            // 4. Espera 10ms
            WAIT_10MS: begin
                counter <= counter + 1;
                if (counter >= 32'd500_000) begin
                    counter <= 0;
                    state <= TRIGGER_MEAS;
                end
            end
            
            // 5. Trigger medición (0xAC, 0x33, 0x00)
            TRIGGER_MEAS: begin
                if (!busy && cmd_ready) begin
                    cmd_address <= 7'h38;
                    cmd_start <= 1;
                    cmd_write_multiple <= 1;
                    cmd_stop <= 0;
                    cmd_valid <= 1;
                    data_out <= 8'hAC;
                    data_out_valid <= 1;
                    data_out_last <= 0;
                    byte_count <= 0;
                    state <= SEND_TRIGGER;
                end
            end
            
            SEND_TRIGGER: begin
                if (data_out_ready && data_out_valid) begin
                    data_out_valid <= 0;
                    
                    if (byte_count == 0) begin
                        data_out <= 8'h33;
                        data_out_valid <= 1;
                        data_out_last <= 0;
                        byte_count <= 1;
                    end else if (byte_count == 1) begin
                        data_out <= 8'h00;
                        data_out_valid <= 1;
                        data_out_last <= 1;
                        cmd_stop <= 1;
                        cmd_valid <= 1;
                        byte_count <= 2;
                    end
                end
                
                if (byte_count == 2 && !data_out_valid && cmd_ready) begin
                    cmd_valid <= 0;
                    cmd_stop <= 0;
                    cmd_write_multiple <= 0;
                    state <= WAIT_80MS;
                    counter <= 0;
                end
            end
            
            // 6. Espera 80ms
            WAIT_80MS: begin
                counter <= counter + 1;
                if (counter >= 32'd4_000_000) begin
                    counter <= 0;
                    state <= CHECK_BUSY; 
                    byte_count <= 0;
                end
            end
            
            // 7. Verificar estado de ocupado (Bit[7])
            CHECK_BUSY: begin
                if (!busy && cmd_ready) begin
                    cmd_address <= 7'h38;
                    cmd_start <= 1;
                    cmd_write <= 1;
                    cmd_stop <= 0;
                    cmd_valid <= 1;
                    data_out <= 8'h71;
                    data_out_valid <= 1;
                    data_out_last <= 1;
                    state <= WAIT_BUSY;
                end
            end
            
            WAIT_BUSY: begin
                 // Espera a que el comando 0x71 se envíe
                if (cmd_write && data_out_valid && data_out_ready) begin
                    data_out_valid <= 0;
                    cmd_write <= 0;

                    // Ahora inicia la lectura (Start repetido + Lectura de 1 byte)
                    cmd_address <= 7'h38;
                    cmd_start <= 1;
                    cmd_read <= 1;
                    cmd_stop <= 1;
                    cmd_valid <= 1;
                    data_in_ready <= 1;
                end
                
                if (data_in_valid && data_in_ready) begin
                    status_byte <= data_in;
                    data_in_ready <= 0;
                    cmd_valid <= 0;
                    cmd_start <= 0;
                    cmd_read <= 0;
                    cmd_stop <= 0;
                    
                    // Si Bit[7] es 1 (ocupado), volvemos a intentar
                    if (status_byte[7] == 1'b1) begin
                        // Añadir un pequeño retraso antes de reintentar la lectura de estado
                        state <= WAIT_80MS; 
                    end else begin
                        state <= READ_DATA; // Bit[7] es 0 (no ocupado), leer datos
                    end
                end
            end

            // 8. Lectura de 6 bytes de datos
            READ_DATA: begin
                // Iniciar la transacción: START + DIR_R
                if (!busy && cmd_ready && byte_count == 0) begin
                    cmd_address <= 7'h38;
                    cmd_start <= 1;
                    cmd_read <= 1;
                    cmd_stop <= 0; // **IMPORTANTE: NO STOP INICIALMENTE**
                    cmd_valid <= 1;
                    data_in_ready <= 1;
                end
                
                // Recibir datos y activar STOP al final
                if (data_in_valid && data_in_ready) begin
                    case (byte_count)
                        0: sensor_data[47:40] <= data_in;
                        1: sensor_data[39:32] <= data_in;
                        2: sensor_data[31:24] <= data_in;
                        3: sensor_data[23:16] <= data_in;
                        4: sensor_data[15:8]  <= data_in;
                        5: begin
                            sensor_data[7:0] <= data_in;
                            
                            // Activar STOP/NACK para el último byte
                            cmd_valid <= 1;
                            cmd_stop <= 1; 
                            data_in_ready <= 0;
                        end
                    endcase
                    
                    if (byte_count < 5) byte_count <= byte_count + 1;
                    else if (byte_count == 5) byte_count <= 6;
                end
                
                // Esperar a que el comando STOP sea aceptado y la comunicación termine
                if (byte_count == 6 && cmd_ready && cmd_valid) begin
                    cmd_valid <= 0;
                    cmd_stop <= 0;
                    state <= PROCESS_DATA;
                end
            end
            
            PROCESS_DATA: begin
                // Ajuste de los bits de datos
                hum_data <= sensor_data[47:32]; 
                temp_data <= sensor_data[27:12]; 
                data_ready <= 1;
                state <= DELAY;
                counter <= 0;
            end
            
            // 9. Delay 1 segundo entre mediciones
            DELAY: begin
                data_ready <= 0;
                counter <= counter + 1;
                if (counter >= 32'd50_000_000) begin
                    state <= TRIGGER_MEAS;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end
endmodule