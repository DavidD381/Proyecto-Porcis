`timescale 1ns / 1ps

module aht20_controller (
    input wire clock, //El clock está dado por i2c_clock que garantiza 100 khz
    input reset, 

    inout wire SDA,
    inout wire SCL,

    output wire busy, //El sensor está ocupado
    output wire missed_ack, // El sensor no respondió

    output reg [15:0] temp_data,
    output reg [15:0] hum_data,
    output wire [5:0] debug_state

);

assign debug_state = state;

reg [6:0]  s_cmd_address;
reg        s_cmd_start;
reg        s_cmd_read;
reg        s_cmd_write;
reg        s_cmd_write_multiple;
reg        s_cmd_read_multiple; // Puerto para read_multiple
reg        s_cmd_stop;
reg        s_cmd_valid;
wire       s_cmd_ready;
reg [7:0]  s_data_tdata;
reg        s_data_tvalid;
wire       s_data_tready;
reg        s_data_tlast;

wire [7:0]  m_data_tdata;
wire        m_data_tvalid;
reg        m_data_tready;
wire        m_data_tlast;

    /*
     * I2C interface
     */
wire        scl_i;
wire        scl_o;
wire        scl_t;
wire        sda_i;
wire        sda_o;
wire        sda_t;

    /*
     * Status
     */
wire        bus_control;
wire        bus_active;


    /*
     * Configuration
     */
wire [15:0] prescale = 16'd125;
wire        stop_on_idle = 1'b1; // Mantenemos esto, ya que la Solución 1 lo permite


i2c_master i2c_master_inst(
    .clk(clock),
    .rst(reset),

    .s_axis_cmd_address(s_cmd_address),
    .s_axis_cmd_start(s_cmd_start),
    .s_axis_cmd_read(s_cmd_read),
    .s_axis_cmd_write(s_cmd_write),
    .s_axis_cmd_write_multiple(s_cmd_write_multiple),
    .s_axis_cmd_read_multiple(s_cmd_read_multiple), // Conectado
    .s_axis_cmd_stop(s_cmd_stop),
    .s_axis_cmd_valid(s_cmd_valid),
    .s_axis_cmd_ready(s_cmd_ready),
    .s_axis_data_tdata(s_data_tdata),
    .s_axis_data_tvalid(s_data_tvalid),
    .s_axis_data_tready(s_data_tready),
    .s_axis_data_tlast(s_data_tlast),

    .m_axis_data_tdata(m_data_tdata),
    .m_axis_data_tvalid(m_data_tvalid),
    .m_axis_data_tready(m_data_tready),
    .m_axis_data_tlast(m_data_tlast),

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

    .prescale(prescale),
    .stop_on_idle(stop_on_idle)
);




// Control de pines I2C (open-drain)
assign scl_i = SCL;
assign SCL = scl_o ? 1'bz : 1'b0;
assign sda_i = SDA;
assign SDA = sda_o ? 1'bz : 1'b0;



//Máquina de estados
localparam POWER_ON = 0;
localparam IDLE = 1;
localparam READ_STATUS = 2;
localparam RECEIVE_STATUS = 3;
// localparam CALIBRATION = 4; // ELIMINADO
localparam INIT_BE = 5;
localparam INIT_SENSOR = 6;
localparam SEND_BE = 7;
localparam SEND_BE_08 = 8;
localparam SEND_BE_00 = 9;
localparam WAIT_10MS = 10;
localparam SEND_AC = 11;
localparam SEND_PARAM1 = 12;
localparam SEND_PARAM2 = 13;
localparam WAIT_MEASURE = 14;
localparam READ_STATUS_MEASURE = 15;
localparam RECEIVE_STATUS_MEASURE = 16;
localparam CHECK_MEASURE = 17;
// localparam START_READ_DATA = 18; // No se usa
localparam READ_BYTE0 = 19;
localparam READ_BYTE1 = 20;
localparam READ_BYTE2 = 21;
localparam READ_BYTE3 = 22;
localparam READ_BYTE4 = 23;
localparam READ_BYTE5 = 24;
localparam PROCESS_DATA = 25;
localparam STOP_READ_DATA = 26; 
localparam INIT_71 = 27;
localparam SEND_0x71 =28;
localparam INIT_71_1 = 29;
localparam SEND_0x71_1 =30;
localparam ERROR_STATE =31;


reg [5:0] state;
reg [32:0]counter; 
reg [7:0] status_byte;
reg [7:0] byte0;
reg [7:0] byte1;
reg [7:0] byte2;
reg [7:0] byte3;
reg [7:0] byte4;
reg [7:0] byte5;
reg [19:0] hum_raw;
reg [19:0] temp_raw;

always @(posedge clock) begin
    // --- VALORES POR DEFECTO ---
    s_cmd_valid = 0;
    s_cmd_start = 0;
    s_cmd_write = 0;
    s_cmd_write_multiple = 0;
    s_cmd_read_multiple = 0; // CORRECCIÓN
    s_cmd_read = 0;
    s_cmd_stop = 0;          // CORRECCIÓN (MUY IMPORTANTE)
    s_data_tvalid = 0;
    m_data_tready = 0;
    s_cmd_address = 7'h00;

    if(reset) begin
        counter <= 32'd0;
        state <= POWER_ON;
    end 

    else begin
    case(state)
        POWER_ON: begin
            counter <= counter + 1;
            if (counter >= 32'd2_000_000) begin
                counter <= 32'd0;
                state <= IDLE;
            end
        end

        IDLE: begin
            if (busy == 0) begin
                state <= INIT_71;
            end 
        end

        INIT_71: begin
            s_cmd_address = 7'h38;
            s_cmd_start = 1;
            s_cmd_write = 1;  // Escribir 0x71
            s_cmd_valid = 1;
            if (s_cmd_ready) begin
                state <= SEND_0x71;
            end            
        end

        SEND_0x71: begin
            s_data_tdata = 8'h71;
            s_data_tvalid = 1;
            s_data_tlast = 1;
            if (s_data_tready) begin
                state <= READ_STATUS;
            end
        end

        READ_STATUS: begin 
            s_cmd_address = 7'h38;
            s_cmd_start = 1; // Genera un REPEATED START
            s_cmd_read = 1;
            s_cmd_valid = 1;

            if (s_cmd_ready) begin
                state <= RECEIVE_STATUS;
            end
        end

        // ----- INICIO DE LA MODIFICACIÓN (SOLUCIÓN 1) -----
        RECEIVE_STATUS: begin
            m_data_tready = 1; // Listo para recibir el status byte

            if (m_data_tvalid) begin
                status_byte <= m_data_tdata; // Guarda el status
                
                // ¡Decisión inmediata para evitar el ciclo de 'idle'!
                if (m_data_tdata[3] == 1) begin
                    state <= INIT_SENSOR; // Salta directo a la siguiente operación I2C
                end
                else begin
                    state <= INIT_BE; // Salta directo a la siguiente operación I2C
                end
            end
        end

        /* ¡ESTADO 'CALIBRATION' ELIMINADO!
        CALIBRATION: begin 
            if (status_byte[3] == 1) begin
                state <= INIT_SENSOR;
            end
            else begin
                state <= INIT_BE;
            end 
        end
        */
        // ----- FIN DE LA MODIFICACIÓN -----

        INIT_BE: begin
            s_cmd_address = 7'h38;
            s_cmd_start = 1;
            s_cmd_write_multiple = 1; // CORRECCIÓN
            s_cmd_stop = 1;           // CORRECCIÓN (Stop al inicio)
            s_cmd_valid = 1;
            if (s_cmd_ready) begin
                state <= SEND_BE;
            end
        end

        SEND_BE: begin
            s_data_tdata = 8'hBE;
            s_data_tvalid = 1;
            s_data_tlast = 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_BE_08;
            end
        end

        SEND_BE_08: begin
            s_data_tdata = 8'h8;
            s_data_tvalid = 1;
            s_data_tlast = 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_BE_00;
            end
        end

        SEND_BE_00: begin
            s_data_tdata = 8'h0;
            s_data_tvalid = 1;
            s_data_tlast = 1; // El master verá esto y aplicará el stop

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                counter <= 32'd0;
                state <= WAIT_10MS;
                // s_cmd_stop = 1; // CORRECCIÓN (Removido)
            end
        end

        WAIT_10MS: begin
            counter <= counter + 1;
            if (counter >= 32'd500_000) begin
                counter <= 32'd0;
                state <= IDLE;
            end
        end

        INIT_SENSOR: begin
            s_cmd_address = 7'h38;
            s_cmd_start = 1;
            s_cmd_write_multiple = 1;
            s_cmd_stop = 1; // CORRECCIÓN (Stop al inicio)
            s_cmd_valid = 1;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_cmd_ready) begin
                state <= SEND_AC;
            end
        end

        SEND_AC: begin
            s_data_tdata = 8'hAC;
            s_data_tvalid = 1;
            s_data_tlast = 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_PARAM1;
            end
        end

        SEND_PARAM1: begin
            s_data_tdata = 8'h33;
            s_data_tvalid = 1;
            s_data_tlast = 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_PARAM2;
            end
        end

        SEND_PARAM2: begin
            s_data_tdata = 8'h0;
            s_data_tvalid = 1;
            s_data_tlast = 1; // El master verá esto y aplicará el stop

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                counter <= 0;
                state <= WAIT_MEASURE;
                // s_cmd_stop = 1; // CORRECCIÓN (Removido)
            end
        end

        WAIT_MEASURE: begin
            counter <= counter + 1;
            if (counter >= 32'd4_000_000) begin
                counter <= 32'd0;
                state <= READ_STATUS_MEASURE;
            end
        end 

        // Estados de inicialización '0x71' (parecen redundantes pero OK)
        INIT_71_1: begin
            s_cmd_address = 7'h38;
            s_cmd_start = 1;
            s_cmd_write = 1;
            s_cmd_valid = 1;
            if (s_cmd_ready) begin
                state <= SEND_0x71;
            end            
        end

        SEND_0x71_1: begin
            s_data_tdata = 8'h71;
            s_data_tvalid = 1;
            s_data_tlast = 1;
            if (s_data_tready) begin
                state <= READ_STATUS;
            end
        end

        // --- LÓGICA DE READ_MULTIPLE ---

        READ_STATUS_MEASURE: begin 
            s_cmd_address = 7'h38;
            s_cmd_start = 1;
            s_cmd_read_multiple = 1; // Inicia el stream de lectura
            s_cmd_valid = 1;

            if (s_cmd_ready) begin
                state <= RECEIVE_STATUS_MEASURE;
            end
        end

        RECEIVE_STATUS_MEASURE: begin
            m_data_tready = 1; // Listo para recibir el 1er byte (Status)
            if (m_data_tvalid) begin
                status_byte <= m_data_tdata;
                state <= CHECK_MEASURE;
            end
        end

        CHECK_MEASURE: begin
            if (status_byte[7] == 0) begin
                // Sensor listo, continuar leyendo bytes
                state <= READ_BYTE0;
            end
            else begin
                // Sensor ocupado, detener la transacción
                state <= STOP_READ_DATA;
            end 
        end

        READ_BYTE0: begin 
            m_data_tready = 1; // Listo para recibir el 2do byte (Hum Hi)
            if(m_data_tvalid) begin
                byte0 <= m_data_tdata;
                state <= READ_BYTE1;
            end
        end

        READ_BYTE1: begin 
            m_data_tready = 1; // Listo para recibir el 3er byte (Hum Lo)
            if(m_data_tvalid) begin
                byte1 <= m_data_tdata;
                state <= READ_BYTE2 ;
            end
        end

        READ_BYTE2: begin 
            m_data_tready = 1; // Listo para recibir el 4to byte (Mix)
            if(m_data_tvalid) begin
                byte2 <= m_data_tdata;
                state <= READ_BYTE3 ;
            end
        end

        READ_BYTE3: begin 
            m_data_tready = 1; // Listo para recibir el 5to byte (Temp Hi)
            if(m_data_tvalid) begin
                byte3 <= m_data_tdata;
                state <= READ_BYTE4 ;
            end
        end

        READ_BYTE4: begin 
            m_data_tready = 1; // Listo para recibir el 6to byte (Temp Lo)
            if(m_data_tvalid) begin
                byte4 <= m_data_tdata;
                state <= READ_BYTE5 ; // Ir a leer el último byte (CRC)

            end
        end

        READ_BYTE5: begin 
            m_data_tready = 1; // Listo para recibir el 7mo byte (CRC)
            if(m_data_tvalid) begin
                byte5 <= m_data_tdata;
                state <= STOP_READ_DATA; // Terminamos, ir a detener
            end
        end

        STOP_READ_DATA: begin
            s_cmd_stop = 1; // Enviar comando de STOP
            s_cmd_valid = 1;
            
            if (s_cmd_ready) begin
                // Master aceptó el stop. Decidir qué hacer.
                if (status_byte[7] == 0) begin
                    state <= PROCESS_DATA; // Ir a procesar
                end else begin
                    state <= WAIT_MEASURE; // Reintentar
                end
            end
        end
        // --- FIN LÓGICA READ_MULTIPLE ---

        PROCESS_DATA: begin
            hum_raw <= {byte0, byte1, byte2[7:4]};    
            temp_raw <= {byte2[3:0], byte3, byte4};
            
            hum_data <= (hum_raw * 100) >> 20;
            temp_data <= (temp_raw * 200) >> 20;
            
            counter <= 32'd0;
            state <= WAIT_10MS;
        end

        ERROR_STATE: begin
            state <= IDLE;  
        end

    endcase
    end
end
endmodule
