//------------------------------------------------------------------------------
// Hexion's video: the raster the K053252 (CCU) is programmed for, the two 64 x 32 tilemaps of 8 x 8 tiles, the colour PROMs.
//
// The raster (MAME 0.289 k053252.cpp with the game's register values 02 FF 00 4D 00 73 00 00 01 1F 05 0E B7 7C): a 12 MHz dot
// (24 MHz / 2), 768 dots a line (HC 0x2FF + 1), 288 lines (VC 0x11F + 1): 15.625 kHz, 54.25 Hz. The picture is 512 x 256 at dot 0 /
// line 0; after it the front porch, the sync and the back porch: 77 / 64 / 115 dots (HFP 0x4D, HSW 7+1 times 8, HBP 0x73) and 5 / 12
// / 15 lines (VFP 5, VSW 0xB+1, VBP 0x0E+1). MAME starts the machine at line 256 (its screen's first vblank begins at time 0): so
// does this raster, out of reset at dot 0 of line 256.
//
// The tilemaps (hexion.cpp): VRAM bank k is layer k, 4 bytes a tile in rows of 64 tiles: code = byte 0 | (byte 1 & 0x3f) << 8,
// colour = byte 2 & 0x0f, byte 3 unused; no tile flip. Layer 1 is drawn opaque, scrolled by MAME's set_scrollx(-4) / set_scrolly(4)
// (screen x shows layer x - 4, screen y layer y + 4); layer 0 over it with pen 0 transparent. Flip screen (the coin counter
// register's bit 5) mirrors the whole picture, MAME's tilemap flip with its scroll rule (tilemap.cpp effective_rowscroll):
// screen (x, y) is the unflipped picture's (511 - x, 255 - y).
//
// A tile's 8 x 8 x 4 bits are 16 bytes in each half of the tile ROMs (MAME's charlayout: x 0,1 from the second half's byte 0, x 2,3
// from the first half's byte 0, x 4,5 / 6,7 the same with byte 1; the high nibble first). The SDRAM holds the two halves'
// byte pairs side by side (rtl/hexion_loader.sv), so a tile row is one 2-word burst at word {code, row, 0}: word 0 the first half's
// two bytes, word 1 the second half's.
//
// Each line is fetched during the line before it into a ping-pong line buffer per layer (64 tiles a layer, 128 two-word bursts in
// about 1,500 of the line's 6,144 clocks), so a line shows the VRAM as it was one line earlier, as the board's tilemap chip reads it
// while the beam runs (MAME draws the whole frame at the start of vblank).
//
// The picture's raster (vmode, the OSD's Video Timing). The game's own raster (vpos, cb_tick, line_start: the interrupts and the
// CCU's read-back) runs on in every mode, so the machine's timeline stays MAME's; modes 1 and 2 draw the same picture on a raster of
// their own, for a RetroTINK 4K in direct video, which takes a MiSTer signal as "MiSTer 240p" only at about 262-264 lines a frame
// (the board's 288 are its "MiSTer Gen.", and its picture then drops out now and then) and judges the picture's width, as a CRT
// does, by its time in the line.
//   0  288 lines (Native): the board's raster, above.
//   1  263 lines (RT4K 54Hz): the board's frame time exactly (1,769,472 clocks), so the picture keeps step with the game: 263 lines
//      of 6,728 clocks but the last, of 6,736 (14.27 kHz); dots 11 clocks apart (8.73 MHz) after a 7-clock gap at the line's start (15
//      on the last line, so every hsync-to-hsync time is the same but one, and the picture always 997 clocks after the hsync starts):
//      611 dots, the 512 of the picture filling 58.7 us of the 70.1 us line; 9 / 41 / 49 dots of front porch, sync and back porch.
//      Its line 0 begins 16 of the board's lines after the game's line 256 (its IRQ) begins, put there at every frame (E_SYNC).
//   2  263 lines (CRT+RT4K): the board's line (768 dots of 8 clocks, 15.625 kHz, its horizontal sync), 263 lines: 59.41 Hz, running
//      free of the game's 54.25 Hz frame (a game frame can show in one or two pictures, and a change of the picture can tear).
// Both 263-line rasters have 2 lines of front porch, a 2-line vertical sync and 3 lines of back porch: the framework's direct-video
// DE (sys_top.v: the lines from the third after the vsync to the third before the next) is then exactly the 256 picture lines.
//------------------------------------------------------------------------------
`default_nettype none

module hexion_video (
    input  logic        clk,            // 96 MHz
    input  logic        reset,
    input  logic        ce_pix,         // 12 MHz
    input  logic        flip,
    input  logic  [1:0] vmode,          // the picture's raster: 0 the board's 768 x 288, 1 and 2 the 263-line ones (above)

    // the VRAM banks' read ports (a 32-bit word is a tile's 4 bytes)
    output logic [10:0] vram_addr,
    input  logic [31:0] vram_q0,
    input  logic [31:0] vram_q1,

    // the tile ROMs in the SDRAM (rtl/hexion_sdram.sv client protocol)
    output logic        t_req,
    output logic [23:0] t_addr,
    output logic  [4:0] t_len,
    input  logic        t_ack,
    input  logic        t_valid,
    input  logic [15:0] t_rdata,

    // the colour PROMs (MAME's "proms": 0x000 red, 0x100 green, 0x200 blue, 4 bits each)
    input  logic        prom_wr,
    input  logic  [9:0] prom_addr,
    input  logic  [7:0] prom_data,

    // the game's raster (the board's, whichever raster the picture has)
    output logic  [8:0] vpos,           // the line (0..287), as MAME's screen vpos()
    output logic        line_start,     // one clock: dot 0 of a line has begun (vpos is the new line)
    output logic        cb_tick,        // one clock, 25 clocks before a line begins (the last clock of dot 764; vpos the line before)
    // the picture
    output logic        o_ce,           // its dot: ce_pix, or with vmode 1 one in 11 clocks
    output logic        o_hs,
    output logic        o_vs,
    output logic        o_hblank,
    output logic        o_vblank,
    output logic        o_vblank_next,  // the next line is in the vertical blank
    output logic  [3:0] o_r,
    output logic  [3:0] o_g,
    output logic  [3:0] o_b
);
    localparam int HTOTAL = 768, VTOTAL = 288, HVIS = 512, VVIS = 256;
    localparam int HS_START = HVIS + 77, HS_END = HVIS + 77 + 64;
    localparam int VS_START = VVIS + 5,  VS_END = VVIS + 5 + 12;

    // ------------------------------------------------------------------ the raster counters
    logic [9:0] hpos;
    always_ff @(posedge clk) begin
        line_start <= 1'b0;
        if (reset) begin
            hpos <= 10'd0; vpos <= 9'd256;
        end else if (ce_pix) begin
            if (hpos == 10'(HTOTAL - 1)) begin
                hpos <= 10'd0;
                vpos <= (vpos == 9'(VTOTAL - 1)) ? 9'd0 : vpos + 9'd1;
                line_start <= 1'b1;
            end else
                hpos <= hpos + 10'd1;
        end
    end

    assign cb_tick = ce_pix && hpos == 10'd764;

    // ------------------------------------------------------------------ 263 lines (RT4K 54Hz), vmode 1
    // vmode 1's phase: line 0 begins 98,304 clocks (16 of the board's lines) after the game's line 256 (its IRQ) begins, i.e. with the
    // game's line 272. The game writes the tilemaps all through its frame; measured in the bench over 900 frames of attract and play
    // (sim/tb_top.sv +VWLOG), this phase gives the fewest lines that show a write a frame apart from the board's raster, with two lines
    // of margin: line 255 is fetched 6 lines after the IRQ, the game's first writes after it (the bottom rows) come 8 lines after it,
    // and a later phase lets the bottom lines show them a frame early
    localparam int E_DOTS = 611, E_HS0 = 521, E_HS1 = 562;
    logic [12:0] eclk;                  // the clock in the line
    logic  [3:0] esub;                  // clocks since the last dot
    logic  [9:0] eh;                    // the dot (0..610)
    logic  [8:0] ev;                    // the line (0..262)
    logic        e_ls;
    wire         e_last = (ev == 9'd262);
    wire  [12:0] e_len  = e_last ? 13'd6736 : 13'd6728;
    wire  [12:0] e_gap  = e_last ? 13'd15 : 13'd7;
    wire         e_ce   = (eclk >= e_gap) && (esub == 4'd0) && (vmode == 2'd1);
    wire         e_sync = ce_pix && hpos == 10'(HTOTAL - 1) && vpos == 9'd271;    // the game's line 272 begins
    always_ff @(posedge clk) begin
        e_ls <= 1'b0;
        if (reset) begin
            eclk <= 13'd0; esub <= 4'd0; eh <= 10'(E_DOTS - 1); ev <= 9'd248;
        end else begin
            if (eclk < e_gap) esub <= 4'd0;
            else              esub <= (esub == 4'd10) ? 4'd0 : esub + 4'd1;
            if (e_ce) eh <= (eclk == e_gap) ? 10'd0 : eh + 10'd1;
            if (e_sync || eclk == e_len - 13'd1) begin
                eclk <= 13'd0;
                ev   <= e_sync ? 9'd0 : e_last ? 9'd0 : ev + 9'd1;
                e_ls <= 1'b1;
            end else
                eclk <= eclk + 13'd1;
        end
    end

    // ------------------------------------------------------------------ 263 lines (CRT+RT4K), vmode 2: free-running, the board's line
    logic [9:0] dh;
    logic [8:0] dv;
    logic       d_ls;
    always_ff @(posedge clk) begin
        d_ls <= 1'b0;
        if (reset) begin
            dh <= 10'd0; dv <= 9'd256;
        end else if (ce_pix) begin
            if (dh == 10'(HTOTAL - 1)) begin
                dh <= 10'd0;
                dv <= (dv == 9'd262) ? 9'd0 : dv + 9'd1;
                d_ls <= 1'b1;
            end else
                dh <= dh + 10'd1;
        end
    end

    // the raster the picture is drawn on
    wire        m1      = (vmode == 2'd1);
    wire        m2      = (vmode == 2'd2);
    wire        pce     = m1 ? e_ce : ce_pix;
    wire  [9:0] rh      = m1 ? eh : m2 ? dh : hpos;
    wire  [8:0] rv      = m1 ? ev : m2 ? dv : vpos;
    wire        rls     = m1 ? e_ls : m2 ? d_ls : line_start;
    wire  [8:0] rv_last = (m1 || m2) ? 9'd262 : 9'(VTOTAL - 1);
    wire  [9:0] r_hs0   = m1 ? 10'(E_HS0) : 10'(HS_START);
    wire  [9:0] r_hs1   = m1 ? 10'(E_HS1) : 10'(HS_END);
    wire  [8:0] r_vs0   = (m1 || m2) ? 9'(VVIS + 2) : 9'(VS_START);
    wire  [8:0] r_vs1   = (m1 || m2) ? 9'(VVIS + 4) : 9'(VS_END);
    assign o_ce = pce;

    // ------------------------------------------------------------------ the line buffers
    // per layer, two banks of 64 words: {colour[3:0], 8 pens (pixel 0 in bits 3:0)}
    logic        lb_we;
    logic        lb_layer;
    logic  [6:0] lb_waddr;
    logic [35:0] lb_wdata;
    logic  [6:0] lb_raddr0, lb_raddr1;
    logic [35:0] lb_q0, lb_q1;
    logic [35:0] lb_unused0, lb_unused1;

    hexion_dpram #(.AW(7), .DW(36)) u_lb0 (.clk(clk), .a_addr(lb_waddr), .a_wdata(lb_wdata), .a_we(lb_we && !lb_layer), .a_q(lb_unused0),
                                           .b_addr(lb_raddr0), .b_q(lb_q0));
    hexion_dpram #(.AW(7), .DW(36)) u_lb1 (.clk(clk), .a_addr(lb_waddr), .a_wdata(lb_wdata), .a_we(lb_we && lb_layer), .a_q(lb_unused1),
                                           .b_addr(lb_raddr1), .b_q(lb_q1));

    // ------------------------------------------------------------------ the fetch of the next line
    // order: column 0 layer 0, column 0 layer 1, column 1 layer 0, ...
    typedef enum logic [1:0] { F_IDLE, F_VADDR, F_VQ, F_REQ } fst_e;
    fst_e        fst;
    logic  [7:0] fy;            // the line being fetched (0..255)
    logic        fbank;
    logic  [5:0] fcol;
    logic        flayer;
    logic  [7:0] frow0, frow1;  // the tilemap rows of the two layers
    wire   [7:0] frow = flayer ? frow1 : frow0;
    wire  [31:0] vq = flayer ? vram_q1 : vram_q0;

    // the requests in flight, in order: {layer, column}; the colour waits with them
    logic [10:0] mq [4];        // {colour[3:0], layer, column[5:0]}
    logic  [1:0] mq_wp, mq_rp;
    logic  [2:0] mq_cnt;
    logic        mq_push, mq_pop;
    logic [10:0] mq_in;

    wire  [8:0] vnext = (rv == rv_last) ? 9'd0 : rv + 9'd1;
    wire  [7:0] sy    = flip ? ~vnext[7:0] : vnext[7:0];

    always_ff @(posedge clk) begin
        mq_push <= 1'b0;
        if (reset) begin
            fst <= F_IDLE; t_req <= 1'b0;
        end else begin
            case (fst)
                F_IDLE:
                    if (rls && vnext < 9'(VVIS)) begin
                        fy    <= vnext[7:0];
                        fbank <= vnext[0];
                        frow0 <= sy;
                        frow1 <= sy + 8'd4;
                        fcol  <= 6'd0; flayer <= 1'b0;
                        fst   <= F_VADDR;
                    end
                F_VADDR: begin
                    vram_addr <= {frow[7:3], fcol};
                    fst <= F_VQ;
                end
                F_VQ: fst <= F_REQ;             // the RAM takes the address at this edge; its word is there in the next clock
                F_REQ:
                    if (!t_req) begin
                        t_req  <= 1'b1;
                        t_addr <= {6'd0, vq[13:8], vq[7:0], frow[2:0], 1'b0};   // {code, row, 0}
                        t_len  <= 5'd2;
                        mq_in  <= {vq[19:16], flayer, fcol};
                        mq_push <= 1'b1;
                    end else if (t_ack) begin
                        t_req <= 1'b0;
                        if (flayer) begin
                            flayer <= 1'b0;
                            fcol   <= fcol + 6'd1;
                            fst    <= (fcol == 6'd63) ? F_IDLE : F_VADDR;
                        end else begin
                            flayer <= 1'b1;
                            fst    <= F_VADDR;
                        end
                    end
                default: fst <= F_IDLE;
            endcase
        end
    end

    // the words coming back: the first half's pair, then the second half's; then the 8 pens go to the line buffer
    logic        rx_second;
    logic [15:0] rx_a;
    wire  [10:0] mq_head = mq[mq_rp];
    always_ff @(posedge clk) begin
        lb_we  <= 1'b0;
        mq_pop <= 1'b0;
        if (reset) begin
            rx_second <= 1'b0;
        end else if (t_valid) begin
            if (!rx_second) begin
                rx_a <= t_rdata;
                rx_second <= 1'b1;
            end else begin
                rx_second <= 1'b0;
                // A = {A0, A1} (the first half), B = {B0, B1}: pens B0h B0l A0h A0l B1h B1l A1h A1l
                lb_wdata <= {mq_head[10:7], rx_a[3:0], rx_a[7:4], t_rdata[3:0], t_rdata[7:4],
                                            rx_a[11:8], rx_a[15:12], t_rdata[11:8], t_rdata[15:12]};
                lb_waddr <= {fbank, mq_head[5:0]};
                lb_layer <= mq_head[6];
                lb_we    <= 1'b1;
                mq_pop   <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            mq_wp <= 2'd0; mq_rp <= 2'd0; mq_cnt <= 3'd0;
        end else begin
            if (mq_push) begin mq[mq_wp] <= mq_in; mq_wp <= mq_wp + 2'd1; end
            if (mq_pop) mq_rp <= mq_rp + 2'd1;
            case ({mq_push, mq_pop})
                2'b10:   mq_cnt <= mq_cnt + 3'd1;
                2'b01:   mq_cnt <= mq_cnt - 3'd1;
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------ the colour PROMs
    logic [3:0] pal_r [256], pal_g [256], pal_b [256];
    always_ff @(posedge clk) if (prom_wr) begin
        case (prom_addr[9:8])
            2'd0:    pal_r[prom_addr[7:0]] <= prom_data[3:0];
            2'd1:    pal_g[prom_addr[7:0]] <= prom_data[3:0];
            2'd2:    pal_b[prom_addr[7:0]] <= prom_data[3:0];
            default: ;
        endcase
    end

    // ------------------------------------------------------------------ the dot
    // within a dot's 8 (or 11) clocks: the line buffer address from the dot counter, its word, the pen (registered), the colour
    // (registered); latched with the raster's signals at the next dot, so the outputs are one dot behind the counters, all together
    wire  [8:0] sx  = flip ? ~rh[8:0] : rh[8:0];
    wire  [8:0] tx1 = sx - 9'd4;
    logic [2:0] px0, px1;
    always_ff @(posedge clk) begin
        lb_raddr0 <= {rv[0], sx[8:3]};
        lb_raddr1 <= {rv[0], tx1[8:3]};
        px0 <= sx[2:0];
        px1 <= tx1[2:0];
    end
    wire  [3:0] pen0 = lb_q0[{px0, 2'b00} +: 4];
    wire  [3:0] pen1 = lb_q1[{px1, 2'b00} +: 4];
    logic [7:0] cidx;
    logic [3:0] cr, cg, cb;
    always_ff @(posedge clk) begin
        cidx <= (pen0 != 4'd0) ? {lb_q0[35:32], pen0} : {lb_q1[35:32], pen1};
        cr <= pal_r[cidx];
        cg <= pal_g[cidx];
        cb <= pal_b[cidx];
    end

    wire visible = (rh < 10'(HVIS)) && (rv < 9'(VVIS));
    always_ff @(posedge clk) begin
        if (pce) begin
            o_r <= visible ? cr : 4'd0;
            o_g <= visible ? cg : 4'd0;
            o_b <= visible ? cb : 4'd0;
            o_hblank <= (rh >= 10'(HVIS));
            o_hs     <= (rh >= r_hs0) && (rh < r_hs1);
            o_vblank <= (rv >= 9'(VVIS));
            o_vs     <= (rv >= r_vs0) && (rv < r_vs1);
            o_vblank_next <= (rv >= 9'(VVIS - 1)) && (rv != rv_last);
        end
    end

    wire unused = &{1'b0, fy, mq_cnt, vq[31:20], vq[15:14], lb_unused0, lb_unused1};
endmodule
`default_nettype wire
