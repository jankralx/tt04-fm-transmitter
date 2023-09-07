`default_nettype none

module cdc_slow2fast_bus
#(
    // parameter DEL = 1,         // number of src_clk cycles to delay input src_dv (data valid) signal
    //                            // it should be 1 (or >= 1) if no external delay is provided
    parameter DW  = 8             // data width
)(
    input wire src_clk,
    input wire [DW-1:0] src_data,
    input wire src_dv,

    input wire dst_clk,
    output reg [DW-1:0] dst_data
);

    // double FF to remove metastability on src_dv
    reg dv_ff1;
    reg dv_ff2;

    always @(posedge dst_clk) begin
        dv_ff1 <= src_dv;
        dv_ff2 <= dv_ff1;
    end

    // NOTE: normally there should be edge detector on dv signal
    // but for this specific application, it is not required,
    // dv signal is valid for one src_clk

    always @(posedge dst_clk) begin
        if (dv_ff2 == 1'b1) begin
            dst_data <= src_data;
        end
    end


endmodule
