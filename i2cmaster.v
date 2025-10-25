module i2cmaster (
    input wire clk, //Se declara el reloj
    input wire rst_n, //Se declara una variable de reset

    //Control

    input wire start, //Se declara el pulso que indica el comienzo
    input wire [6:0] addr, //Se declaran las entradas para los 7 bits de la dirección del esclavo
    input wire rw, //Se declara si se va a escribir al esclavo con (0) o a leer al esclavo con (1)
    input wire [7:0] data_wr, //Se declaran los 8 bits de información a enviar
    
    output reg [7:0] data_rd, //Se declara la información que quiere ser leida del esclavo
    output reg busy, // Indica si el esclavo está transmitiendo, ocupado (1) o si está disponible (0)
    output reg ack_error, //Indica si el esclavo no respondió al llamado o si todo está bien
    output reg done, //Indica si se completó la transacción

    //Bus I2C

    inout wire i2c_sda, 
    inout wire i2c_scl//El esclavo puede escribir datos y el maestro también, es bidireccional
    
);


    localparam IDLE = 4'd0; // En (0000) está inactiva, esperando el pulso de inicio con start
    localparam START = 4'd1; // Envía la condición de inicio (SDA 0 y SCL 1)
    localparam ADDR = 4'd2; // Envía la dirección del esclavo
    localparam RW = 4'd3; //Envía el bit que indica lectura o escritura
    localparam ACK_ADDR = 4'd4; //Lee el bit que envía el esclavo de reconocimiento
    localparam WRITE_DATA = 4'd5; // Escribe los datos para el esclavo (rw=0)
    localparam ACK_WR = 4'd6; // Espera el ACK del esclavo
    localparam READ_DATA = 4'd7; // Lee los datos provenientes del esclavo (rw=1)
    localparam ACK_RD = 4'd8; //El maestro envía una señal de recibido
    localparam STOP = 4'd9; //Se genera condición de stop (SDA 1 y SCL 1)

    reg [3:0] state, next_state; //Representa el estado actual y el siguiente de la máquina son 4 bits, debido a que son 10 estados
    reg [2:0] bit_counter; //Cuenta los bits ya sea que se esten recibiendo o enviando
    reg [7:0] shift_reg; //Guarda los datos a transmitir
    reg [6:0] addr_reg; //Guarda la dirección del esclavo
    reg rw_reg; //Guarda el bit de escritura o lectura

    reg scl_out, sda_out; //Almacena el valor de SCL y SDA antes de enviarlos
    reg scl_enable, sda_enable; //Las lineas son controladas por el usuario (1)

    wire i2c_clk, i2c_clk_tick;
    reg clk_enable;

    i2c_clock #(
        .CLK_FREQ(50000000),
        .I2C_FREQ(100000)
    ) clk_div (
        .clk(clk), 
        .rst_n(rst_n),
        .enable(clk_enable), 
        .i2c_clk(i2c_clk),
        .i2c_clk_tick(i2c_clk_tick)
    );

    //Bidireccional 

    assign i2c_scl = scl_enable ? scl_out : 1'bz; // Si (1) entonces es controlada por el maestro, si (0) alta impedancia
    assign i2c_sda = sda_enable ? sda_out : 1'bz;

    //Máquina de estados - Registro de estado

    always @(posedge clk or negedge rst_n) begin //Se activa si el reloj cambia de (0 a 1) o si el reset pasa de (1 a 0)
        if (!rst_n) //Si el reset está en (0, activado), entonces se mantiene en reposo
            state <= IDLE;
        else if (i2c_clk_tick) //SI el reset está en (1, descativado), entonces se pasa al siguiente estado
            state <= next_state; //Además se tiene en cuenta que el tick debe estar en 1, que indica que el clock cambió, pues este es un pulso que ocurre cuando cambia y mantiene la frecuencia de 100kHz
    end

    //Máquina de estados - lógica cmobinacional

    always@(*) begin  //Se ejecuta cada vez que alguna señal de adentro cambie
        next_state = state;

        case (state)
            IDLE: begin //SI start (1), entonces se pasa al estado START
                if (start)
                next_state = START;
            end

            START: begin //Se pasa al estado ADDR sin importar
                next_state = ADDR;
            end

            ADDR: begin //Se está enviando la dirección, cuando se envié el último bit de dirección se pasa al otro estado
                if (bit_counter == 6)
                    next_state = RW;
            end 

            RW: begin //Evía el bit de lectura o escritura
                next_state = ACK_ADDR;
            end 

            ACK_ADDR: begin
                if (i2c_sda == 0) //ACK recibido, el esclavo confirmó
                    next_state = rw_reg ? READ_DATA : WRITE_DATA; //Indica si va a leer (1) o si va a escribir (0)
                else //El esclavo no confirmó. se para
                next_state = STOP;
            end 

            WRITE_DATA: begin //Se envian los 8 bits y se pasa al siguiente estado
                if (bit_counter == 7)
                    next_state = ACK_WR;
            end

            ACK_WR: begin
                next_state = STOP; //Se espera la confirmación del esclavo y se para 
            end

            READ_DATA: begin //El esclavo escribe los datos, cuando acaba se pasa al otro estado
                if (bit_counter == 7)
                    next_state = ACK_RD;
            end

            ACK_RD: begin //EL maestro indica que ya recibió los datos
                next_state = STOP;
            end

            STOP: begin // Se genera el stop y luego vuelve a reposo
                next_state = IDLE;
            end 

            default: next_state = IDLE;
        endcase
    end

    //Lógica de control de señales

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            busy <= 0; //No ecupado
            done <= 0; //Nada terminado 
            ack_error <= 0; //NO hay error
            clk_enable <= 0; // EL divisor de clock genera el clock?
            scl_enable <= 0; // No se controlan las líneas, están en alta impedancia
            sda_enable <= 0; //
            sda_out<= 1;
            scl_out <= 1;
            bit_counter <= 0; //Registros en 0
            shift_reg <= 0;
            addr_reg <= 0;
            rw_reg <= 0;
            data_rd <= 0;
        end

        else begin
            done <= 0;
            if (i2c_clk_tick) begin //Se da inicio cuando hay untick, para sincronizar todo
                case (state)

                    IDLE: begin 
                        busy <= 0;
                        clk_enable <= 0; //No se genera el clock

                        scl_enable <= 0; //No se controla, alta impedancia
                        sda_enable <= 0;
                        scl_out <= 1;
                        sda_out <= 1;

                        if (start) begin //Empieza todo
                            busy <= 1; //Ahora si está ocupado
                            addr_reg <= addr; //Se guardan los registros
                            rw_reg <= rw;
                            shift_reg <= data_wr; //Se guarda el dato a escribir
                            clk_enable <= 1; //Se enciende el clock
                            ack_error <= 0; //Se borran los errores
                        end
                    end

                    START: begin
                        scl_enable <= 1; //Se controlan las líneas
                        sda_enable <= 1; 
                        scl_out <= 1; //Se pone genera la condición de START, SCL se mantiene(1) 
                        sda_out <= 0; // Y sda se pasa a (0)
                        bit_counter <= 0; //Se deja listo el contador para el siguiente estado
                    end  
                    
                    ADDR: begin
                        scl_out <= i2c_clk; // SCL sigue la señal del reloj de 100kHz
                        sda_out <= addr_reg[6 - bit_counter]; //Se envía la dirección

                        if (i2c_clk == 0) //Cuando SCL está bajo se cambian los datos, cuando está en alto se leen
                        bit_counter <= bit_counter + 1;
                    end 

                    RW: begin //Se envía el bit que indica lectura o escritura
                        scl_out <= i2c_clk;
                        sda_out <= rw_reg; //SDA toma el valor de  escritura(0) o de lectura (1) 
                        bit_counter <= 0;
                    end 

                    ACK_ADDR: begin
                        scl_out <= i2c_clk; 
                        sda_enable <= 0; //Libera la SDA para que el esclavo responda

                        if (i2c_clk == 1 && i2c_sda == 1) //Espera para leer la respuesta del esclavo, si el esclavo baja a SDA, respondió, sino, entonces se da error
                            ack_error <= 1; //EL esclavo no respondió
                    end

                    WRITE_DATA: begin
                        scl_out <= i2c_clk;
                        sda_enable <= 1; //El maestro vuelve a tomar el control de la línea
                        sda_out <= shift_reg[7- bit_counter]; // Se envían los 8 bits con el bit más significativo primero

                        if (i2c_clk == 0)
                            bit_counter <= bit_counter + 1;
                    end 

                    ACK_WR: begin
                        scl_out <= i2c_clk;
                        sda_enable <= 0; //Se espera hasta que el esclavo responda

                        if (i2c_clk == 1 && i2c_sda == 1)
                            ack_error <= 1;
                    end 

                    READ_DATA: begin
                        scl_out <= i2c_clk;
                        sda_enable <= 0; //El esclavo envía los datos, no tenemos el control

                        if (i2c_clk == 1) begin //Lee en el flanco alto, osea SCL (1)
                            data_rd[7 - bit_counter] <= i2c_sda;
                        end

                        if (i2c_clk == 0) //Se incrementa el contador en bajo
                        bit_counter <= bit_counter + 1;
                    end 

                    ACK_RD: begin
                        scl_out <= i2c_clk;
                        sda_enable <= 1; //Retomamos el control
                        sda_out <= 1; //Se indica que no se quieren más datos
                    end

                    STOP: begin //Se pone la condición de STOP, SCL sigue en (1) y SDA de 0 a 1
                        scl_enable <= 1; 
                        sda_enable <= 1;
                        scl_out <= 1;  //Sigue en 1
                        sda_out <= 1; //Sube a 1
                        done <= 1; //Indica que se terminó la tarea
                    end
                endcase
            end
        end 
    end 
endmodule
