module fm_modulator
(
    input clk,
    input signed [A-1:0] audio,  // audio signal in 2's complement
    output [D-1:0] rf
);

    parameter A = 8;    // number of bits in audio signal
    parameter N = 18;   // number of bits in phase accumulator
    parameter M = 14;   // number of bits in sine generator
    parameter D = 5;    // number of bits in FM modulator and DAC

    parameter F_S = 50000000;  // sampling frequency
    parameter F_C = 10000000;  // carrier frequency
    parameter DF =     75000;  // frequency deviation

    // constants
    localparam R = M-2; // number of bits of phase divided by 4
    localparam ACC_INC = 2**N / (F_S / F_C);      // phase accumulator increment
    localparam DF_INC = 2**N / (F_S / DF);        // frequency deviation increment

    
    // debug print of constants and actual frequencies
    // real F_C_ACTUAL = F_S * ACC_INC / 2**N;
    // real DF_ACTUAL = F_S * DF_INC / 2**N;
    initial begin
        $display("Current parameters:");
        $display("F_S = %d", F_S);
        $display("F_C = %d", F_C);
        $display("DF = %d", DF);
        $display("ACC_INC = %d", ACC_INC);
        $display("DF_INC = %d", DF_INC);
        //$display("F_C_ACTUAL = %f", F_C_ACTUAL);
        //$display("DF_ACTUAL = %f", DF_ACTUAL);
    end

    reg [N-1:0] phase_acc = 0;
    wire [N-1:0] mod_inc = audio * DF_INC / 2**(A-1);

    ///////////////////////////////////////////////////////////////////////////
    // audio signal to FM modulated phase
    ///////////////////////////////////////////////////////////////////////////
    always @(posedge clk) begin
        phase_acc <= phase_acc + ACC_INC + mod_inc;
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
            $display("WARNING: R=%d and D=%d should comply D=R+1 for maximum efficiency", R, D);
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

