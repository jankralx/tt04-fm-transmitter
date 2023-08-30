`default_nettype none

module tt_fm_transmitter #( 
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

    // inputs
    wire i2s_clk = ui_in[0];
    wire i2s_din = ui_in[1];
    wire i2s_ws  = ui_in[2];
    wire chan_sel = ui_in[3];
    
    // for tests only - dac_bits enable
    wire [7:0] dac_bits = uio_in;

    // outputs
    wire [7:0] dac;
    assign uo_out = dac;

    // unused outputs
    assign uio_oe = 0;
    assign uio_out = 0;

    ///////////////////////////////////////////////////////////////////////////
    // I2S receiver
    ///////////////////////////////////////////////////////////////////////////
    localparam A = 8;   // audio signal width
    localparam DW = 16;
    wire [A-1:0] audio_src;
    wire [DW-1:0] i2s_audio;
    wire i2s_dvalid;

    // connect I2S signals to output for debugging
    assign i2s_clk_o = i2s_clk;
    assign i2s_din_o = i2s_din;
    assign i2s_ws_o = i2s_ws;

    
    i2s_rx #(
        .DW(DW)
    ) i2s_rx_inst (
        .i2s_clk(i2s_clk),
        .i2s_din(i2s_din),
        .i2s_ws(i2s_ws),
        .chan_sel(chan_sel),
        .ws_align(0),
        .dout(i2s_audio),
        .dvalid(i2s_dvalid)
    );

    assign audio_src = i2s_audio[DW-1:DW-A];        // select highest bits from received audio signal for FM modulator

    ///////////////////////////////////////////////////////////////////////////
    // Synchronize into clk_50 domain - TODO
    ///////////////////////////////////////////////////////////////////////////
    
    wire [A-1:0] audio;


    // TODO !!!!!!!!!!
    assign audio = audio_src;


    ///////////////////////////////////////////////////////////////////////////
    // FM modulator
    ///////////////////////////////////////////////////////////////////////////
    localparam D = 8;
    wire [D-1:0] rf;

    fm_modulator #(
        .A(A),
        .D(D)
    ) fm_modulator_inst (
        .clk(clk_50),
        .audio(audio),
        .rf(rf)
    );

    assign dac = rf & dac_bits;

endmodule
