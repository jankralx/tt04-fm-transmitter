`default_nettype none

module fm_modulator
#(
    parameter A   = 8,         // number of bits in audio signal
    parameter K   = 4,         // number of bits of frequency deviation increment coefficient
    parameter L   = 2,         // number of bits of frequency deviation increment factor
    parameter N   = 18,        // number of bits in phase accumulator
    parameter M   = 14,        // number of bits going to sine generator
    parameter D   = 5          // number of bits in FM modulator and DAC
)(
    input wire clk,
    input wire signed [A-1:0] audio,  // audio signal in 2's complement
    input wire [N-1:0] acc_inc,
    input wire [K-1:0] df_inc_coef,
    input wire [L-1:0] df_inc_fact,
    input wire multiply_sel,
    output wire [D-1:0] rf
);

    localparam R = M-2; // number of bits of phase divided by 4

    reg [N-1:0] phase_acc = 0;

    // allocate enough vector width for multiplication, because we are not sure about bit expansion during multiplication
    wire signed [N-1:0] audio_w = audio;       
    wire [N-1:0] df_inc_coef_w = df_inc_coef;

    wire signed [N-1:0] mod_inc_mult;
    assign mod_inc_mult = audio_w * df_inc_coef_w * 2; // before it was = ... * (256 / 2**(A-1));

    /*
    // this should be more universal but does not work well - not sure why now
    generate
        if (256 >= 2**(A-1))
            assign mod_inc_mult = audio_w * df_inc_coef_w * (256 / 2**(A-1));
        else
            assign mod_inc_mult = audio_w * df_inc_coef_w / (2**(A-1) / 256);
    endgenerate
    */

//    assign mod_inc_mult = 

    wire signed [N-1:0] mod_inc_safe = audio * 512 / 2**(A-1);

    reg signed [N-1:0] mod_inc;
    always @* begin
        if (multiply_sel) begin
            mod_inc = mod_inc_safe;
        end else begin
            if (df_inc_fact == 0)           // x 256 / 8
                mod_inc = mod_inc_mult / 8;
            else if (df_inc_fact == 1)      // x 256 / 4
                mod_inc = mod_inc_mult / 4;
            else if (df_inc_fact == 2)      // x 256 / 2
                mod_inc = mod_inc_mult / 2;
            else                            // x 256
                mod_inc = mod_inc_mult;
        end
    end

    //wire [N-1:0] mod_inc = audio * 384 / 2**(A-1);
        
    ///////////////////////////////////////////////////////////////////////////
    // audio signal to FM modulated phase
    ///////////////////////////////////////////////////////////////////////////
    always @(posedge clk) begin
        phase_acc <= phase_acc + acc_inc + mod_inc;
    end

    ///////////////////////////////////////////////////////////////////////////
    // super-approximated sinewave generator
    ///////////////////////////////////////////////////////////////////////////
    wire [1:0] quadrant = phase_acc[N-1:N-2];
    wire [R-1:0] phase_r = phase_acc[N-3:N-3-R+1];

    reg out_negative;
    reg [R-1:0] phase_ra = 0;

    // solve sign of output and phase_r orientation based on quadrant
    always @* begin
        if (quadrant == 0 || quadrant == 1) begin
            out_negative = 0;
        end else begin
            out_negative = 1;
        end
        
        if (quadrant == 1 || quadrant == 3) begin
            phase_ra = 2**R - 1 - phase_r;
        end else begin
            phase_ra = phase_r;
        end
    end

    // linear approximation of sinewave
    initial begin
        // check for R and D - they should be same for maximum efficiency
        if (D != R+1) begin
            $display("WARNING: R=%d, D=%d, M=%d should comply D=R+1=M-1 for maximum efficiency", R, D, M);
        end
    end

    wire [1:0] phase_int = phase_ra[R-1:R-2];
    reg [D-2:0] fm_fun;
    always @* begin
        if (phase_int == 0) begin
            fm_fun = 2*phase_ra[R-1:R-D+1];
        end else if (phase_int == 1 || phase_int == 2) begin
            fm_fun = (2**(D-1))/4 + phase_ra[R-1:R-D+1];
        end else begin
            fm_fun = (2**(D-1)) - 1;
        end
    end

    // output with FF
    reg signed [D-1:0] fm_out = 0;
    always @(posedge clk) begin
        if (out_negative)
            fm_out <= -fm_fun;
        else
            fm_out <= fm_fun;
    end


    assign rf = 2**(D-1) + fm_out;

endmodule

