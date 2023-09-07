`default_nettype none

module i2s_rx
#(
    parameter DW = 16
)(
    input wire i2s_clk,
    input wire i2s_din,
    input wire i2s_ws,
    input wire chan_sel,
    input wire ws_align,             // 0: typical I2S with one bit delay, 1: left-justified (WS is aligned with data)
    output reg [DW-1:0] dout,
    output reg dvalid
);
    reg i2s_ws_del;

    wire ws_act = (ws_align == 0) ? i2s_ws_del : i2s_ws;

    always @(posedge i2s_clk) begin
        // receive only channel selected by chan_sel switch
        if (ws_act == chan_sel) begin
            // feed left-shift register with new data on every rising edge of i2s_clk
            dout[0] <= i2s_din;
            dout[DW-1:1] <= dout[DW-2:0];
        end

        // dvalid goes active for one cycle after the whole word is received
        if (i2s_ws_del == chan_sel && i2s_ws != chan_sel) begin
            dvalid <= 1'b1;
        end else begin
            dvalid <= 1'b0;
        end

        // delay i2s_ws by one clock cycle
        i2s_ws_del <= i2s_ws;
    end


endmodule
