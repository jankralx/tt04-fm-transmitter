`default_nettype none

module tt_um_fm_transmitter #( 
) (
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
    localparam L   = 12;        // number of bits of frequency deviation increment
    localparam N   = 18;        // number of bits in phase accumulator
    localparam M   = 5;         // number of bits in going to sine generator
    localparam D   = 4;         // number of bits in FM modulator and DAC
    localparam F_S = 50000000;  // default clock frequency
    localparam F_C = 10000000;  // default carrier frequency
    localparam DF  = 75000;     // default frequency deviation

    // interconnect signals
    wire spi_miso;

    wire [N-1:0] acc_inc;
    wire [L-1:0] df_inc;
    wire [D-1:0] dac_ena;
    wire [2:0] dith_fact;       // TODO connect to destination
    wire usb_i2sn;              // TODO connect to destination
    wire audio_chan_sel;
    wire i2s_ws_align;          // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)

    wire usb_dp_pull;
    wire usb_connected = 1'b0;

    wire usb_dp_in;     // USB D+ input
    wire usb_dp_out;    // USB D+ output
    wire usb_dp_oe;     // USB D+ output enable - active high: 0 input, 1 output
    wire usb_dn_in;     // USB D- input
    wire usb_dn_out;    // USB D- output
    wire usb_dn_oe;     // USB D- output enable - active high: 0 input, 1 output

    // inputs
    wire i2s_clk = ui_in[0];
    wire i2s_din = ui_in[1];
    wire i2s_ws  = ui_in[2];
    wire i2s_ws_align_pin = ui_in[3];       // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)
    wire audio_chan_sel_pin = ui_in[4];
    wire usb_i2sn_pin = ui_in[5];
    wire dith_disable_pin = ui_in[6];
    // TODO ui_in[7] is free
    
    // outputs
    wire [D-1:0] dac;
    assign uo_out[3:0] = dac;
    assign uo_out[6:4] = 3'b000;       // TODO uo_out[7:4] is free
    assign uo_out[7] = usb_connected;

    // inouts
    assign usb_dp_in = uio_in[0];
    assign usb_dn_in = uio_in[1];
    wire spi_clk = uio_in[4];
    wire spi_csn = uio_in[5];
    wire spi_mosi = uio_in[6];

    assign uio_out[0] = usb_dp_out;          // TODO - USB DP
    assign uio_out[1] = usb_dn_out;          // TODO - USB DN
    assign uio_out[2] = 1'b0;          // TODO - USB DP
    assign uio_out[3] = 1'b0;          // TODO - this is free
    assign uio_out[6:4] = 3'b000;      // SPI input pins (CLK, CSn, MOSI)
    assign uio_out[7] = spi_miso;
    
    // inouts direction
    assign uio_oe[0] = usb_dp_oe;    // TODO - USB DP
    assign uio_oe[1] = usb_dn_oe;    // TODO - USB DN
    assign uio_oe[2] = 1'b1;         // USB DP
    assign uio_oe[3] = 1'b0;         // TODO - this is free
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
        .df_inc(df_inc),
        .rf(rf)
    );

    // selected output bits of DAC are enabled only if ena == 1
    assign dac = rf & dac_ena & {D{ena}};

    ///////////////////////////////////////////////////////////////////////////
    // SPI configuration core
    ///////////////////////////////////////////////////////////////////////////
    spi_config #(
        .A(A),      // number of bits in audio signal
        .L(L),      // number of bits of frequency deviation increment
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
        .usb_i2sn_pin(usb_i2sn_pin),
        .audio_chan_sel_pin(audio_chan_sel_pin),
        .i2s_ws_align_pin(i2s_ws_align_pin),            // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)
        .dith_disable_pin(dith_disable_pin),
        .acc_inc(acc_inc),
        .df_inc(df_inc),
        .dac_ena(dac_ena),
        .dith_fact(dith_fact),
        .usb_i2sn(usb_i2sn),
        .audio_chan_sel(audio_chan_sel),
        .i2s_ws_align(i2s_ws_align)                 // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)    
    );

    ///////////////////////////////////////////////////////////////////////////
    // USB audio device
    ///////////////////////////////////////////////////////////////////////////
    wire [15:0] audio_l, audio_r;

    usb_audio_top #(
        .DEBUG           ( "FALSE"             )    // If you want to see the debug info of USB device core, set this parameter to "TRUE"
    ) u_usb_audio (
        .rstn            ( 1'b1 ),   // we need synchronous release of reset for this - TODO !
        .clk             ( clk            ),   // clk for USB needs to be 60MHz!
        // USB signals
        .usb_dp_pull     ( usb_dp_pull      ),
        .usb_dp_in       ( usb_dp_in        ),
        .usb_dp_out      ( usb_dp_out       ),
        .usb_dp_oe       ( usb_dp_oe        ),
        .usb_dn_in       ( usb_dn_in        ),
        .usb_dn_out      ( usb_dn_out       ),
        .usb_dn_oe       ( usb_dn_oe        ),

        // USB reset output
        .usb_rstn        ( usb_connected       ),   // 1: connected , 0: disconnected (when USB cable unplug, or when system reset (rstn=0))
        // user data : audio output (host-to-device, such as a speaker), and audio input (device-to-host, such as a microphone).
        .audio_en        (                     ),
        .audio_lo        ( audio_l             ),   // left-channel output : 16-bit signed integer, which will be valid when audio_en=1
        .audio_ro        ( audio_r             ),   // right-channel output: 16-bit signed integer, which will be valid when audio_en=1
        .audio_li        ( audio_l             ),   // left-channel input  : 16-bit signed integer, which will be sampled when audio_en=1
        .audio_ri        ( audio_r             ),   // right-channel input : 16-bit signed integer, which will be sampled when audio_en=1
        // debug output info, only for USB developers, can be ignored for normally use
        .debug_en        (                     ),
        .debug_data      (                     ),
        .debug_uart_tx   (                     )
    );

endmodule
