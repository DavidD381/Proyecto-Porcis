`timescale 1ns / 1ps

module lcd_controller (
    input wire clock,
    input wire reset,

    input wire [7:0] data_in,
    input wire write_char,
    input wire write_cmd,

    inout SDA,
    inout SCL,

    output wire busy,
    output wire missed_ack,

    output wire ready
);

reg [6:0]  s_cmd_address;
reg        s_cmd_start;
reg        s_cmd_read;
reg        s_cmd_write;
reg        s_cmd_write_multiple;
reg        s_cmd_read_multiple; 
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
     * State
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
    .s_axis_cmd_read_multiple(s_cmd_read_multiple), 
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

assign ready = (state == IDLE);



//Máquina de estados
localparam POWER_ON = 0;

localparam INIT_03 = 1;
localparam SEND_03_0 = 2;
localparam SEND_03_1 = 3;
localparam SEND_03_2 = 4;

localparam WAIT_4_1MS = 81;

localparam INIT_03_1 = 5;
localparam SEND_03_0_1 = 6;
localparam SEND_03_1_1 = 7;
localparam SEND_03_2_1 = 8;
localparam WAIT_100US = 9;

localparam INIT_03_2 = 10;
localparam SEND_03_0_2 = 11;
localparam SEND_03_1_2 = 12;
localparam SEND_03_2_2 = 13;
localparam WAIT_100US_1 = 14;

localparam INIT_02 = 15; 
localparam SEND_02_0 = 16;
localparam SEND_02_1 = 17;
localparam SEND_02_2 = 18;

localparam ERROR_STATE =25;

// Pausa después de poner en 4-bits
localparam WAIT_100US_2 = 26;

// --- Comando 0x28 (Function Set) ---
localparam INIT_028_H = 27;  // Nibble Alto (0x2)
localparam SEND_028_H0 = 28;
localparam SEND_028_H1 = 29;
localparam SEND_028_H2 = 30;
localparam INIT_028_L = 31;  // Nibble Bajo (0x8)
localparam SEND_028_L0 = 32;
localparam SEND_028_L1 = 33;
localparam SEND_028_L2 = 34;
localparam WAIT_100US_3 = 35; // Pausa

// --- Comando 0x08 (Display OFF) ---
localparam INIT_008_H = 36; // Nibble Alto (0x0)
localparam SEND_008_H0 = 37;
localparam SEND_008_H1 = 38;
localparam SEND_008_H2 = 39;
localparam INIT_008_L = 40; // Nibble Bajo (0x8)
localparam SEND_008_L0 = 41;
localparam SEND_008_L1 = 42;
localparam SEND_008_L2 = 43;
localparam WAIT_100US_4 = 44; // Pausa

// --- Comando 0x01 (Clear Display) ---
localparam INIT_001_H = 45; // Nibble Alto (0x0)
localparam SEND_001_H0 = 46;
localparam SEND_001_H1 = 47;
localparam SEND_001_H2 = 48;
localparam INIT_001_L = 49; // Nibble Bajo (0x1)
localparam SEND_001_L0 = 50;
localparam SEND_001_L1 = 51;
localparam SEND_001_L2 = 52;
localparam WAIT_CLEAR = 53; // Pausa LARGA (1.64ms)

// --- Comando 0x06 (Entry Mode) ---
localparam INIT_006_H = 54; // Nibble Alto (0x0)
localparam SEND_006_H0 = 55;
localparam SEND_006_H1 = 56;
localparam SEND_006_H2 = 57;
localparam INIT_006_L = 58; // Nibble Bajo (0x6)
localparam SEND_006_L0 = 59;
localparam SEND_006_L1 = 60;
localparam SEND_006_L2 = 61;
localparam WAIT_100US_5 = 62; // Pausa

// --- Comando 0x0C (Display ON) ---
localparam INIT_00C_H = 63; // Nibble Alto (0x0)
localparam SEND_00C_H0 = 64;
localparam SEND_00C_H1 = 65;
localparam SEND_00C_H2 = 66;
localparam INIT_00C_L = 67; // Nibble Bajo (0xC)
localparam SEND_00C_L0 = 68;
localparam SEND_00C_L1 = 69;
localparam SEND_00C_L2 = 70;


localparam IDLE = 71;

localparam WRITE_H_INIT = 72; // Nibble Alto: Iniciar I2C
localparam WRITE_H_SEND_0 = 73; // Nibble Alto: Enviar E=0
localparam WRITE_H_SEND_1 = 74; // Nibble Alto: Enviar E=1
localparam WRITE_H_SEND_2 = 75; // Nibble Alto: Enviar E=0

localparam WRITE_L_INIT = 76; // Nibble Bajo: Iniciar I2C
localparam WRITE_L_SEND_0 = 77; // Nibble Bajo: Enviar E=0
localparam WRITE_L_SEND_1 = 78; // Nibble Bajo: Enviar E=1
localparam WRITE_L_SEND_2 = 79; // Nibble Bajo: Enviar E=0

localparam WRITE_WAIT = 80; // Pausa corta (40us) antes de volver a IDLE


reg [32:0] counter; 
reg [7:0] state;
reg [7:0] data_reg;
reg rs_reg;

always @(posedge clock )begin

    s_cmd_valid = 0;
    s_cmd_start = 0;
    s_cmd_write = 0;
    s_cmd_write_multiple = 0;
    s_cmd_read_multiple = 0; 
    s_cmd_read = 0;
    s_cmd_stop = 0;     
    s_data_tvalid = 0;
    m_data_tready = 0;
    s_cmd_address = 7'h00;

    if (reset) begin
        counter <= 32'd0;
        state <= POWER_ON;
    end 

    else begin 

        s_cmd_valid = 0;
        s_cmd_start = 0;
        s_cmd_write_multiple = 0;
        s_cmd_stop = 0;
        s_data_tvalid = 0;
        s_data_tlast = 0;
        m_data_tready = 0;

    case (state)
        POWER_ON: begin
            counter <= counter + 1;
            if (counter >= 32'd2_000_000) begin
                state <= INIT_03;
                counter <= 0;
            end
        end

        INIT_03: begin
            s_cmd_valid <= 1;
            s_cmd_address <= 7'h27;
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1;
            s_cmd_stop <= 1;
            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_cmd_ready) begin
                state <= SEND_03_0;
            end
        end

        SEND_03_0: begin
            s_data_tvalid <= 1;
            s_data_tdata <= 8'h38;
            s_data_tlast <= 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_03_1;
            end
        end

        SEND_03_1: begin
            s_data_tdata <= 8'h3C;
            s_data_tvalid <= 1;
            s_data_tlast <= 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_03_2;
            end
        end

        SEND_03_2: begin
            s_data_tdata <= 8'h38;
            s_data_tvalid <= 1;
            s_data_tlast <= 1;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= WAIT_4_1MS;
            end
        end

        WAIT_4_1MS: begin
            counter <= counter + 1;
            if (counter >= 32'd205_000) begin
                state <= INIT_03_1;
                counter <= 0;
            end
        end

        INIT_03_1: begin
            s_cmd_valid <= 1;
            s_cmd_address <= 7'h27;
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1;
            s_cmd_stop <= 1;
            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_cmd_ready) begin
                state <= SEND_03_0_1;
            end
        end

        SEND_03_0_1: begin
            s_data_tdata = 8'h38;
            s_data_tvalid = 1;
            s_data_tlast = 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_03_1_1;
            end
        end

        SEND_03_1_1: begin
            s_data_tdata = 8'h3C;
            s_data_tvalid = 1;
            s_data_tlast = 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_03_2_1;
            end
        end

        SEND_03_2_1: begin
            s_data_tdata = 8'h38;
            s_data_tvalid = 1;
            s_data_tlast = 1;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= WAIT_100US;
            end
        end

        WAIT_100US: begin
            counter <= counter + 1;
            if (counter >= 32'd5_000) begin
                state <= INIT_03_2;
                counter <= 0;
            end
        end


        INIT_03_2: begin
            s_cmd_valid <= 1;
            s_cmd_address <= 7'h27;
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1;
            s_cmd_stop <= 1;
            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_cmd_ready) begin
                state <= SEND_03_0_2;
            end
        end

        SEND_03_0_2: begin
            s_data_tdata <= 8'h38;
            s_data_tvalid <= 1;
            s_data_tlast <= 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_03_1_2;
            end
        end

        SEND_03_1_2: begin
            s_data_tdata <= 8'h3C;
            s_data_tvalid <= 1;
            s_data_tlast <= 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_03_2_2;
            end
        end

        SEND_03_2_2: begin
            s_data_tdata <= 8'h38;
            s_data_tvalid <= 1;
            s_data_tlast <= 1;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= WAIT_100US_1;
            end
        end

        WAIT_100US_1: begin
            counter <= counter + 1;
            if (counter >= 32'd5_000) begin
                state <= INIT_02;
                counter <= 0;
            end
        end

//PONER EN 4 BITS
        INIT_02: begin
            s_cmd_valid <= 1;
            s_cmd_address <= 7'h27;
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1;
            s_cmd_stop <= 1;
            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_cmd_ready) begin
                state <= SEND_02_0;
            end
        end 

        SEND_02_0: begin
            s_data_tdata <= 8'h28;
            s_data_tvalid <= 1;
            s_data_tlast <= 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_02_1;
            end
        end

        SEND_02_1: begin
            s_data_tdata <=8'h2C;
            s_data_tvalid <= 1;
            s_data_tlast <= 0;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= SEND_02_2;
            end
        end

        SEND_02_2: begin
            s_data_tdata <= 8'h28;
            s_data_tvalid <= 1;
            s_data_tlast <= 1;

            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= WAIT_100US_2;
                counter <= 0;
            end
        end
// Pausa corta antes de enviar comandos de 4-bits
        WAIT_100US_2: begin
            counter <= counter + 1;
            if (counter >= 32'd5_000) begin // 100us
                state <= INIT_028_H; // Ir al comando 0x28
                counter <= 0;
            end
        end

// --- INICIA COMANDO 0x28 (Function Set: 4-bit, 2-line) ---
        // Nibble Alto (0x2)
        INIT_028_H: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_028_H0; 
                end
        end
        SEND_028_H0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h28; //(0010 1000) Dato:2 || Luz: 1 || Enable 0 || 00 cmd
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_028_H1; 
                end
        end
        SEND_028_H1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h2C;  //(0010 1100) Dato:2 || Luz: 1 || Enable 1 || 00 cmd
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_028_H2; 
                end
        end
        SEND_028_H2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h28; //Repite H0
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= INIT_028_L; 
            end
        end
        
        // Nibble Bajo (0x8)
        INIT_028_L: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_028_L0; 
                end
        end
        SEND_028_L0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h88; // (1000 1000) Dato:8 || Luz: 1 || Enable 0 || 00 cmd
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_028_L1; 
                end
        end
        SEND_028_L1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h8C; // (1000 1100) Dato:8 || Luz: 1 || Enable 1 || 00 cmd
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
            end
            else if (s_data_tready) begin 
                state <= SEND_028_L2; 
                end
        end
        SEND_028_L2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h88; //Se repite L1
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= WAIT_100US_3; counter <= 0; 
                end
        end

        // Pausa
        WAIT_100US_3: begin
            counter <= counter + 1;
            if (counter >= 32'd5_000) begin
                state <= INIT_008_H; // Ir al comando 0x08
                counter <= 0;
            end
        end

// --- INICIA COMANDO 0x08 (Display OFF) ---
        // Nibble Alto (0x0)
        INIT_008_H: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_008_H0; 
                end
        end
        SEND_008_H0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h08; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_008_H1; 
                end
        end
        SEND_008_H1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h0C; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_008_H2; 
                end
        end
        SEND_008_H2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h08; 
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= INIT_008_L; 
                end
        end

        // Nibble Bajo (0x8)
        INIT_008_L: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_008_L0; 
                end
        end
        SEND_008_L0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h88; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_008_L1; 
                end
        end
        SEND_008_L1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h8C; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_008_L2; 
                end
        end
        SEND_008_L2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h88; 
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; end
            else if (s_data_tready) begin 
                state <= WAIT_100US_4; 
                counter <= 0; 
                end
        end

        // Pausa
        WAIT_100US_4: begin
            counter <= counter + 1;
            if (counter >= 32'd5_000) begin
                state <= INIT_001_H; // Ir al comando 0x01
                counter <= 0;
            end
        end

// --- INICIA COMANDO 0x01 (Clear Display) ---
        // Nibble Alto (0x0)
        INIT_001_H: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_001_H0; 
                end
        end
        SEND_001_H0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h08; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_001_H1; 
                end
        end
        SEND_001_H1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h0C; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_001_H2; 
                end
        end
        SEND_001_H2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h08; 
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= INIT_001_L; 
                end
        end

        // Nibble Bajo (0x1)
        INIT_001_L: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_001_L0; 
                end
        end
        SEND_001_L0: begin
            s_data_tvalid <= 1; s_data_tdata <= 8'h18; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; end
            else if (s_data_tready) begin 
                state <= SEND_001_L1; 
                end
        end
        SEND_001_L1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h1C; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_001_L2; 
                end
        end
        SEND_001_L2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h18; 
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= WAIT_CLEAR; counter <= 0; 
                end
        end

        // PAUSA LARGA (1.64ms) - ¡OBLIGATORIA!
        WAIT_CLEAR: begin
            counter <= counter + 1;
            if (counter >= 32'd82_000) begin // 1.64ms @ 50MHz
                state <= INIT_006_H; // Ir al comando 0x06
                counter <= 0;
            end
        end

// --- INICIA COMANDO 0x06 (Entry Mode) ---
        // Nibble Alto (0x0)
        INIT_006_H: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_006_H0; 
                end
        end
        SEND_006_H0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h08; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_006_H1; 
                end
        end
        SEND_006_H1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h0C; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_006_H2; 
                end
        end
        SEND_006_H2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h08; 
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= INIT_006_L; 
                end
        end

        // Nibble Bajo (0x6)
        INIT_006_L: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_006_L0; 
                end
        end
        SEND_006_L0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h68; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_006_L1; 
                end
        end
        SEND_006_L1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h6C; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_006_L2; 
                end
        end
        SEND_006_L2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h68; 
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= WAIT_100US_5; 
                counter <= 0; end
        end

        // Pausa
        WAIT_100US_5: begin
            counter <= counter + 1;
            if (counter >= 32'd5_000) begin
                state <= INIT_00C_H; // Ir al comando 0x0C
                counter <= 0;
            end
        end

// --- INICIA COMANDO 0x0C (Display ON, Cursor OFF) ---
        // Nibble Alto (0x0)
        INIT_00C_H: begin
            s_cmd_valid <= 1; 
            s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_00C_H0; 
                end
        end
        SEND_00C_H0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h08; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; end
            else if (s_data_tready) begin 
                state <= SEND_00C_H1; 
                end
        end
        SEND_00C_H1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'h0C; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_00C_H2; 
                end
        end
        SEND_00C_H2: begin
            s_data_tvalid <= 1;
            s_data_tdata <= 8'h08; 
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= INIT_00C_L; 
                end
        end

        // Nibble Bajo (0xC)
        INIT_00C_L: begin
            s_cmd_valid <= 1; s_cmd_address <= 7'h27; 
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1; 
            s_cmd_stop <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_cmd_ready) begin 
                state <= SEND_00C_L0; 
                end
        end
        SEND_00C_L0: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'hC8; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; end
            else if (s_data_tready) begin 
                state <= SEND_00C_L1; 
                end
        end
        SEND_00C_L1: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'hCC; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= SEND_00C_L2; 
                end
        end
        SEND_00C_L2: begin
            s_data_tvalid <= 1; 
            s_data_tdata <= 8'hC8; 
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= IDLE; 
                end // ¡TERMINADO!
        end

// --- ESTADOS FINALES ---
        IDLE: begin
            // La inicialización terminó.
            // Aquí es donde esperarías un comando para escribir un carácter.
            if (write_char) begin
                data_reg <= data_in;
                rs_reg <= 1;
                state <= WRITE_H_INIT;
            end
            else if (write_cmd) begin
                data_reg <= data_in;
                rs_reg <= 0; 
                state <= WRITE_H_INIT;
            end
        end

        //NIBBLE ALTO

        WRITE_H_INIT: begin
            s_cmd_valid <= 1;
            s_cmd_address <= 7'h27;
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1;
            s_cmd_stop <= 1;
            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_cmd_ready) begin
                state <= WRITE_H_SEND_0;
            end
        end

        WRITE_H_SEND_0: begin
            s_data_tvalid <= 1;
            // Construimos el byte: (Dato[7:4] << 4) | (BL=1, E=0, RW=0) | (RS)
            s_data_tdata <= (data_reg[7:4] << 4) | 8'h08 | rs_reg; 
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= WRITE_H_SEND_1; 
                end
        end

        WRITE_H_SEND_1: begin
            s_data_tvalid <= 1;
            // Construimos el byte: (Dato[7:4] << 4) | (BL=1, E=1, RW=0) | (RS)
            s_data_tdata <= (data_reg[7:4] << 4) | 8'h0C | rs_reg;
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= WRITE_H_SEND_2;
                end
        end
        
        WRITE_H_SEND_2: begin
            s_data_tvalid <= 1;
            // Construimos el byte: (Dato[7:4] << 4) | (BL=1, E=0, RW=0) | (RS)
            s_data_tdata <= (data_reg[7:4] << 4) | 8'h08 | rs_reg;
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= WRITE_L_INIT; 
                end // Ir al Nibble Bajo
        end

        //NIBBLE BAJO
        WRITE_L_INIT: begin
            s_cmd_valid <= 1;
            s_cmd_address <= 7'h27;
            s_cmd_start <= 1;
            s_cmd_write_multiple <= 1;
            s_cmd_stop <= 1;
            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_cmd_ready) begin
                state <= WRITE_L_SEND_0;
            end
        end

        WRITE_L_SEND_0: begin
            s_data_tvalid <= 1;
            //(Dato[3:0] << 4) | (BL=1, E=0, RW=0) | (RS)
            s_data_tdata <= (data_reg[3:0]) << 4 | 8'h08 | rs_reg;
            s_data_tlast <= 0;
            if (missed_ack) begin
                state <= ERROR_STATE;
            end
            else if (s_data_tready) begin
                state <= WRITE_L_SEND_1;
            end
        end

        WRITE_L_SEND_1: begin
            s_data_tvalid <= 1;
            //(Dato[3:0] << 4) | (BL=1, E=1, RW=0) | (RS)
            s_data_tdata <= (data_reg[3:0] << 4) | 8'h0C | rs_reg;
            s_data_tlast <= 0;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= WRITE_L_SEND_2; 
                end
        end

        WRITE_L_SEND_2: begin
            s_data_tvalid <= 1;
            //(Dato[3:0] << 4) | (BL=1, E=0, RW=0) | (RS)
            s_data_tdata <= (data_reg[3:0] << 4) | 8'h08 | rs_reg;
            s_data_tlast <= 1;
            if (missed_ack) begin 
                state <= ERROR_STATE; 
                end
            else if (s_data_tready) begin 
                state <= WRITE_WAIT; 
                counter <= 0; 
                end // Ir a la pausa
        end

        WRITE_WAIT: begin
            counter <= counter + 1;
            if (counter >= 32'd2_000) begin // 40us @ 50MHz
                state <= IDLE; // ¡Listos para el próximo carácter!
                counter <= 0;
            end
        end



        ERROR_STATE: begin
        end
    endcase
    end
end
endmodule

