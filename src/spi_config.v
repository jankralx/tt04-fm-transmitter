`default_nettype none

module spi_config #(
    parameter A   = 8,         // number of bits in audio signal
    parameter L   = 12,        // number of bits of frequency deviation increment
    parameter N   = 18,        // number of bits in phase accumulator
    parameter M   = 14,        // number of bits in sine generator
    parameter D   = 5,         // number of bits in FM modulator and DAC
    parameter F_S = 50000000,  // default clock frequency
    parameter F_C = 10000000,  // default carrier frequency
    parameter DF  = 75000      // default frequency deviation

)(
    input wire rst,

    input wire spi_clk,
    input wire spi_csn,
    input wire spi_mosi,
    output reg spi_miso,

    // pin configuration inputs
    input wire usb_i2sn_pin,
    input wire audio_chan_sel_pin,
    input wire i2s_ws_align_pin,            // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)
    input wire dith_disable_pin,

    // configuration values
    output wire [N-1:0] acc_inc,
    output wire [L-1:0] df_inc,
    output wire [D-1:0] dac_ena,
    output reg [2:0] dith_fact,

    // configuration flags
    output wire usb_i2sn,
    output wire audio_chan_sel,
    output wire i2s_ws_align                // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)   
);
    ///////////////////////////////////////////////////////////////////////////
    // default values
    ///////////////////////////////////////////////////////////////////////////
    
    // default values for acc_inc and df_inc are expecting F_S, F_C, and DF given as module parameters
    // if different F_S, F_C, and DF are required for real operation one would need to set
    // these parameters by SPI

    localparam ACC_INC_DEF = 2**N / (F_S / F_C);      // phase accumulator increment
    localparam DF_INC_DEF = 2**N / (F_S / DF);        // frequency deviation increment
    
    // debug print of constants and actual frequencies
    // real F_C_ACTUAL = F_S * ACC_INC / 2**N;
    // real DF_ACTUAL = F_S * DF_INC / 2**N;
    initial begin
        $display("Current parameters:");
        $display("F_S = %d", F_S);
        $display("F_C = %d", F_C);
        $display("DF = %d", DF);
        $display("ACC_INC = %d", ACC_INC_DEF);
        $display("DF_INC = %d", DF_INC_DEF);
        //$display("F_C_ACTUAL = %f", F_C_ACTUAL);
        //$display("DF_ACTUAL = %f", DF_ACTUAL);
    end

    localparam DITH_FACT_DEF = 2;
    localparam DAC_ENA_DEF = {D{1'b1}};     // all bits enabled by default

    // if not specified here, default value is 0

    ///////////////////////////////////////////////////////////////////////////
    // config vector space definition
    ///////////////////////////////////////////////////////////////////////////

    // configuration vector space
    localparam ACC_INC_POS = 0;
    localparam DF_INC_POS = ACC_INC_POS + N;
    localparam DAC_ENA_POS = DF_INC_POS + L;
    localparam DITH_FACT_POS = DAC_ENA_POS + D;
    
    // single bit flags
    localparam USB_I2SN_POS = DITH_FACT_POS + 3;
    localparam AUDIO_CHAN_SEL_POS = USB_I2SN_POS + 1;
    localparam I2S_WS_ALIGN = AUDIO_CHAN_SEL_POS + 1;

    // TODO: last bit is SPI override
    localparam SPI_OVERRIDE_POS = I2S_WS_ALIGN + 1;

    // configuration vector width
    localparam DW = SPI_OVERRIDE_POS + 1;

    ///////////////////////////////////////////////////////////////////////////
    // SPI shift register and latch
    ///////////////////////////////////////////////////////////////////////////

    // shift register
    reg [DW-1:0] shift_reg = {DW{1'b0}};

    always @(posedge spi_clk or posedge rst) begin
        if (rst) begin
            shift_reg <= {DW{1'b0}};
            shift_reg[N-1+ACC_INC_POS:ACC_INC_POS]   <= ACC_INC_DEF;
            shift_reg[L-1+DF_INC_POS:DF_INC_POS]     <= DF_INC_DEF;
            shift_reg[D-1+DAC_ENA_POS:DAC_ENA_POS]   <= DAC_ENA_DEF;
            shift_reg[2+DITH_FACT_POS:DITH_FACT_POS] <= DITH_FACT_DEF;

        end else if (~spi_csn) begin
            shift_reg <= {shift_reg[DW-2:0], spi_mosi};
        end
    end

    // originally there was a latch register activated with CSn,
    // but it complicated the reset, so we stay for now without any
    // protection during config
    // during loading via SPI configuration bits will randomly toggle
    // as data will be shifted in

    // output latch
    // reg [DW-1:0] latch_reg = {DW{1'b0}};
    // always @(spi_csn or shift_reg) begin
    //     if (spi_csn == 1'b0)
    //         latch_reg <= shift_reg;
    // end

    wire [DW-1:0] latch_reg = shift_reg;

    ///////////////////////////////////////////////////////////////////////////
    // MISO signal needs to be registered with negative clock edge
    ///////////////////////////////////////////////////////////////////////////
    // negative edge senstive flip-flop with asynchronous reset
    wire spi_clk_n = ~spi_clk;
    always @(posedge spi_clk_n or posedge spi_csn) begin
        // CSn works as asynchronous reset, when not selected, MOSI is assigned the highest bit
        // also with any negative edge of clock, MOSI is assigned highest bit (which is shifted during rising edges)
        spi_miso <= shift_reg[DW-1];
    end

    ///////////////////////////////////////////////////////////////////////////
    // output assignments
    ///////////////////////////////////////////////////////////////////////////

    // assign bits from latch register
    wire spi_override = latch_reg[SPI_OVERRIDE_POS];

    assign acc_inc = latch_reg[N-1+ACC_INC_POS:ACC_INC_POS];
    assign df_inc = latch_reg[L-1+DF_INC_POS:DF_INC_POS];
    assign dac_ena = latch_reg[D-1+DAC_ENA_POS:DAC_ENA_POS];

    // ** dith_fact **
    // disable dithering when disable pin is high and SPI override is not set
    // otherwise value from latch register (default if not set by SPI)
    always @(dith_disable_pin or latch_reg or spi_override) begin
        if (spi_override == 1'b0 && dith_disable_pin == 1'b1) begin
            dith_fact <= 3'b0;
        end else begin
            dith_fact <= latch_reg[2+DITH_FACT_POS:DITH_FACT_POS];
        end
    end

    // if spi_override is not set, pin value is taken
    assign usb_i2sn = spi_override == 1'b1 ? latch_reg[USB_I2SN_POS] : usb_i2sn_pin;
    assign audio_chan_sel = spi_override == 1'b1 ? latch_reg[AUDIO_CHAN_SEL_POS] : audio_chan_sel_pin;
    assign i2s_ws_align = spi_override == 1'b1 ? latch_reg[I2S_WS_ALIGN] : i2s_ws_align_pin;

endmodule
