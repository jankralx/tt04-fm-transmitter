`default_nettype none

module arst_sync #(
    parameter LEN = 3
)(
    input wire arstn,
    input wire clk,
    output wire srst
);

    reg [LEN-1:0] shreg;

    always @(posedge clk or negedge arstn) begin
        if (~arstn) begin
            shreg <= {LEN{1'b1}};
        end else begin
            shreg <= {shreg[LEN-2:0],1'b0};
        end
    end

    assign srst = shreg[LEN-1];

endmodule