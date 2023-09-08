`default_nettype none

module tt_um_fm_transmitter #(
    parameter FPGA_DEBUG = 0
)
(
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    localparam A   = 8;         // number of bits in audio signal
    localparam K   = 4;         // number of bits of frequency deviation increment coefficient
    localparam L   = 2;         // number of bits of frequency deviation increment factor
    localparam N   = 18;        // number of bits in phase accumulator
    localparam M   = 5;         // number of bits in going to sine generator
    localparam D   = 4;         // number of bits in FM modulator and DAC
    localparam F_S = 50000000;  // default clock frequency
    localparam F_C = 10000000;  // default carrier frequency
    localparam DF  = 75000;     // default frequency deviation

    // interconnect signals
    wire spi_miso;

    wire [N-1:0] acc_inc;
    wire [K-1:0] df_inc_coef;
    wire [L-1:0] df_inc_fact;
    wire [D-1:0] dac_ena;
    wire [2:0] dith_fact;       // TODO connect to destination
    wire multiply_sel;
    wire audio_chan_sel;
    wire i2s_ws_align;          // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)

    // inputs
    wire i2s_clk = ui_in[0];
    wire i2s_din = ui_in[1];
    wire i2s_ws  = ui_in[2];
    wire i2s_ws_align_pin = ui_in[3];       // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)
    wire audio_chan_sel_pin = ui_in[4];
    wire multiply_sel_pin = ui_in[5];
    wire dith_disable_pin = ui_in[6];
    // TODO ui_in[7] is free
    
    // outputs
    wire [D-1:0] dac;
    assign uo_out[3:0] = dac;
    assign uo_out[6:4] = 3'b000;       // TODO uo_out[7:4] is free
    assign uo_out[7] = 1'b0;           // TODO connect usb_connected signal

    // inouts
    wire spi_clk = uio_in[4];
    wire spi_csn = uio_in[5];
    wire spi_mosi = uio_in[6];

    assign uio_out[0] = 1'b0;          // TODO - USB DP
    assign uio_out[1] = 1'b0;          // TODO - USB DN
    assign uio_out[2] = 1'b0;          // TODO - USB DP
    assign uio_out[3] = 1'b0;          // TODO - this is free
    assign uio_out[6:4] = 3'b000;      // SPI input pins (CLK, CSn, MOSI)
    assign uio_out[7] = spi_miso;
    
    // inouts direction
    assign uio_oe[0] = 1'b0;         // unused
    assign uio_oe[1] = 1'b0;         // unused
    assign uio_oe[2] = 1'b0;         // unused
    assign uio_oe[3] = 1'b0;         // unused
    assign uio_oe[6:4] = 3'b000;     // SPI input pins (CLK, CSn, MOSI)
    assign uio_oe[7] = ~spi_csn;     // MISO is driven only when spi_csn == 0, otherwise as input (Hi-Z)

    ///////////////////////////////////////////////////////////////////////////
    // Invertor for reset
    ///////////////////////////////////////////////////////////////////////////
    wire rst = ~rst_n;
        
    ///////////////////////////////////////////////////////////////////////////
    // I2S receiver
    ///////////////////////////////////////////////////////////////////////////
    localparam DW = 16;
    wire [A-1:0] audio_src;
    wire [DW-1:0] i2s_audio;
    wire i2s_dvalid;

    i2s_rx #(
        .DW(DW)
    ) i2s_rx_inst (
        .i2s_clk(i2s_clk),
        .i2s_din(i2s_din),
        .i2s_ws(i2s_ws),
        .chan_sel(audio_chan_sel),
        .ws_align(i2s_ws_align),
        .dout(i2s_audio),
        .dvalid(i2s_dvalid)
    );

    assign audio_src = i2s_audio[DW-1:DW-A];        // select highest bits from received audio signal for FM modulator


    // fpga ILA is instantiated only when FPGA_DEBUG
    generate
        if (FPGA_DEBUG)
            ila_0 ila_i2c_src (
                .clk(i2s_clk), // input wire clk
                .probe0(i2s_audio), // input wire [15:0]  probe0  
                .probe1(i2s_dvalid), // input wire [0:0]  probe1 
                .probe2(audio_chan_sel), // input wire [0:0]  probe2 
                .probe3(i2s_din), // input wire [0:0]  probe3 
                .probe4(i2s_ws) // input wire [0:0]  probe4
            );
    endgenerate

    ///////////////////////////////////////////////////////////////////////////
    // Synchronize into clk_50 domain
    ///////////////////////////////////////////////////////////////////////////
    
    wire [A-1:0] audio;

    cdc_slow2fast_bus #(
        .DW(A)
    ) cdc_audio_data (
        .src_data(audio_src),
        .src_dv(i2s_dvalid),
        .dst_clk(clk),
        .dst_data(audio)
    );

    generate
        if (FPGA_DEBUG)
            ila_1 ila_i2s_clk50 (
                .clk(clk), // input wire clk
                .probe0(i2s_audio), // input wire [15:0]  probe0  
                .probe1(audio), // input wire [15:0]  probe1 
                .probe2(audio_chan_sel), // input wire [0:0]  probe2 
                .probe3(i2s_clk), // input wire [0:0]  probe3 
                .probe4(i2s_dvalid), // input wire [0:0]  probe4 
                .probe5(i2s_ws), // input wire [0:0]  probe5 
                .probe6(i2s_din) // input wire [0:0]  probe6
            );
    endgenerate

    ///////////////////////////////////////////////////////////////////////////
    // FM modulator
    ///////////////////////////////////////////////////////////////////////////
    wire [D-1:0] rf;

    fm_modulator #(
        .A(A),      // number of bits in audio signal
        .L(L),      // number of bits of frequency deviation increment
        .N(N),      // number of bits in phase accumulator
        .M(M),      // number of bits in sine generator
        .D(D)       // number of bits in FM modulator and DAC
    ) fm_modulator_inst (
        .clk(clk),
        .audio(audio),
        .acc_inc(acc_inc),
        .df_inc_coef(df_inc_coef),
        .df_inc_fact(df_inc_fact),
        .multiply_sel(multiply_sel),
        .rf(rf)
    );

    // selected output bits of DAC are enabled only if ena == 1
    assign dac = rf & dac_ena & {D{ena}};

    ///////////////////////////////////////////////////////////////////////////
    // SPI configuration core
    ///////////////////////////////////////////////////////////////////////////
    spi_config #(
        .A(A),      // number of bits in audio signal
        .K(K),      // number of bits of frequency deviation increment coefficient
        .L(L),      // number of bits of frequency deviation increment factor
        .N(N),      // number of bits in phase accumulator
        .M(M),      // number of bits in sine generator
        .D(D),      // number of bits in FM modulator and DAC
        .F_S(F_S),  // default clock frequency
        .F_C(F_C),  // default carrier frequency
        .DF(DF)     // default frequency deviation
    ) spi_config_inst (
        .rst(rst),
        .spi_clk(spi_clk),
        .spi_csn(spi_csn),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .multiply_sel_pin(multiply_sel_pin),
        .audio_chan_sel_pin(audio_chan_sel_pin),
        .i2s_ws_align_pin(i2s_ws_align_pin),            // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)
        .dith_disable_pin(dith_disable_pin),
        .acc_inc(acc_inc),
        .df_inc_coef(df_inc_coef),
        .df_inc_fact(df_inc_fact),
        .dac_ena(dac_ena),
        .dith_fact(dith_fact),
        .multiply_sel(multiply_sel),
        .audio_chan_sel(audio_chan_sel),
        .i2s_ws_align(i2s_ws_align)                 // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)    
    );

    generate
        if (FPGA_DEBUG)
            ila_2 ila_fmmod_inst (
                .clk(clk), // input wire clk
                .probe0(dac), // input wire [3:0]  probe0  
                .probe1(acc_inc), // input wire [17:0]  probe1 
                .probe2(df_inc_coef), // input wire [3:0]  probe2 
                .probe3(df_inc_fact), // input wire [1:0]  probe3 
                .probe4(dac_ena), // input wire [3:0]  probe4 
                .probe5(dith_fact), // input wire [2:0]  probe5 
                .probe6(spi_clk), // input wire [0:0]  probe6 
                .probe7(spi_csn), // input wire [0:0]  probe7 
                .probe8(spi_mosi), // input wire [0:0]  probe8 
                .probe9(spi_miso), // input wire [0:0]  probe9 
                .probe10(audio_chan_sel_pin), // input wire [0:0]  probe10 
                .probe11(i2s_ws_align_pin), // input wire [0:0]  probe11 
                .probe12(dith_disable_pin), // input wire [0:0]  probe12 
                .probe13(audio_chan_sel), // input wire [0:0]  probe13 
                .probe14(i2s_ws_align), // input wire [0:0]  probe14 
                .probe15(rst) // input wire [0:0]  probe15
            );        
    endgenerate

endmodule
