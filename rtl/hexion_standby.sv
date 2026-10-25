// A blank raster of the core's own timing (the picture raster vmode selects in hexion_video: 0 the board's 768 x 288 with 8-clock
// dots; 1 263 lines of 6,728 clocks, the last of 6,736, with 11-clock dots after a 7-clock gap (15 on the last line); 2 263 lines of
// the board's 768-dot line; the 512 x 256 picture and the same syncs) for the time the machine is held in reset (the ROM image
// streaming in, the OSD's Reset): the framework draws its "Loading" pop-up on the OSD, which needs a video signal with sync to sit
// on, and a monitor or scaler keeps its lock. After the owner's Rabbit core (rabbit_standby.sv).
`default_nettype none
module hexion_standby (
    input  wire       clk,
    input  wire [1:0] vmode,
    output reg        o_ce,
    output reg        o_hblank,
    output reg        o_vblank,
    output reg        o_vblank_next,
    output reg        o_hs,
    output reg        o_vs
);
    reg [12:0] lc = 13'd0;          // the clock in the line
    reg  [3:0] sub = 4'd0;          // clocks since the last dot
    reg  [9:0] hc = 10'd0;          // the dot
    reg  [8:0] vc = 9'd0;           // the line
    wire       m1     = (vmode == 2'd1);
    wire [8:0] v_last = (vmode == 2'd0 || vmode == 2'd3) ? 9'd287 : 9'd262;
    wire [12:0] len   = m1 ? ((vc == 9'd262) ? 13'd6736 : 13'd6728) : 13'd6144;
    wire [12:0] gap   = m1 ? ((vc == 9'd262) ? 13'd15 : 13'd7) : 13'd0;
    wire [3:0] step   = m1 ? 4'd10 : 4'd7;
    wire       dot    = (lc >= gap) && (sub == 4'd0);
    wire [9:0] hs0    = m1 ? 10'd521 : 10'd589;
    wire [9:0] hs1    = m1 ? 10'd562 : 10'd653;
    wire [8:0] vs0    = (v_last == 9'd287) ? 9'd261 : 9'd258;
    wire [8:0] vs1    = (v_last == 9'd287) ? 9'd273 : 9'd260;
    initial begin o_ce = 1'b0; o_hblank = 1'b1; o_vblank = 1'b1; o_vblank_next = 1'b1; o_hs = 1'b0; o_vs = 1'b0; end
    always @(posedge clk) begin
        o_ce <= dot;
        if (lc < gap) sub <= 4'd0;
        else          sub <= (sub == step) ? 4'd0 : sub + 4'd1;
        if (lc >= len - 13'd1) begin
            lc <= 13'd0;
            vc <= (vc >= v_last) ? 9'd0 : vc + 9'd1;
        end else
            lc <= lc + 13'd1;
        if (dot) begin
            hc <= (lc == gap) ? 10'd0 : hc + 10'd1;
            o_hblank <= (hc >= 10'd512);
            o_hs     <= (hc >= hs0) && (hc < hs1);
            o_vblank <= (vc >= 9'd256);
            o_vblank_next <= (vc >= 9'd255) && (vc != v_last);
            o_vs     <= (vc >= vs0) && (vc < vs1);
        end
    end
endmodule
`default_nettype wire
