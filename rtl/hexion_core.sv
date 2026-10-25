//------------------------------------------------------------------------------
// Hexion (Konami GX122, 1992) and its Impeuropex bootleg: the machine, written from MAME 0.289's src/mame/konami/hexion.cpp.
//
//   Z80B at 6 MHz (24 MHz / 4); K053252 CCU (the raster at 12 MHz, the interrupts); 052591 PMC (only its RAM fills, as in MAME);
//   two 64 x 32 tilemaps; K051649 SCC at 3 MHz and an MSM6295 at 1.056 MHz (pin 7 high); the bootleg has a second MSM6295 (pin 7
//   low) at f5c0 in place of the SCC.
//
// Memory map (MAME's base_map):
//   0000-7fff ROM                   8000-9fff ROM bank (bankswitch bits 3:0, 16 x 8 KB of the 128 KB program)
//   a000-bfff RAM                   c000-dffe banked: the tile ROM window, VRAM bank 0 / 1, the PMC's RAM (below)
//   dfff      bank control          e800-e8ff K051649 (the bootleg: nothing)
//   f000-f00f K053252               f200 OKI         f400 / f401 DSW1 / DSW2   f402 / f403 P1 / P2
//   f440      DSW3                  f441 SYSTEM      f480 bankswitch           f4c0 coin counters, flip (bit 5)
//   f500      tile ROM window       f540 watchdog    f5c0 OKI 2 (the bootleg)
// Unmapped reads are 0 (MAME's unmapped value for this machine).
//
// c000-dffe (MAME's bankedram_r / _w): reads give the tile ROM at ((window & 0x7f) << 12) + offset when the window register is
// non-zero and the offset is below 0x1000, else VRAM bank <rambank> when the bank control is 0, else the PMC RAM (2 KB) when it is 2,
// else 0. Writes: bank control 3 at offset 0 with a value 0 or 1 selects <rambank>; bank control 0 writes the VRAM bank and 2 the
// PMC RAM, both only while PMC-BK (bankswitch bit 7) is set. Bankswitch bit 6 starts the PMC: command (PMC RAM byte 0) 0 or 1
// fills that VRAM bank with PMC RAM byte 1; any other command clears 16 bytes of bank (byte 4 & 1) from offset (bytes 2-3).
//
// Interrupts (MAME's scanline timer and the CCU's callbacks): the timer calls once a line, at dot 0, after its first call at 1/540 s
// (MAME's screen is 60 Hz until the game programs the CCU at 0.72 ms, and the timer's first call is set by that raster); at line
// 256 it raises the Z80's IRQ (IM 1), and at every call it counts down a counter that raises the NMI at 0 and reloads it from
// INT-TIME (CCU register 0x0d). Writes to CCU registers 0x0e / 0x0f clear the IRQ / NMI. MAME's Z80 takes an interrupt after the
// instruction during which (or at whose end) it was raised; tv80 decides at an instruction's last step on what it sampled at the
// step before, so it would take one raised during an instruction's last cycle an instruction later: the calls are made 25 clocks
// (a cycle and a half) early here, which gives MAME's choice for every time inside the instruction.
//
// Clocking and MAME's timeline: the Z80 steps once per 16 clocks of 96 MHz, in phase with the raster as in MAME (the CPU and the
// screen both start at time 0). MAME's memory is instant; here two things make the Z80 wait: a read of the tile ROM window (an
// SDRAM read) and the PMC's fill (2,048 clocks). The Z80's clock enable is held for those, and the cycles it missed are given back
// right after at one per 8 clocks, so the program stays on MAME's timeline.
//------------------------------------------------------------------------------
`default_nettype none

module hexion_core (
    input  logic        clk,            // 96 MHz
    input  logic        reset,
    input  logic        bootleg,        // the board: 0 Konami (the SCC), 1 the bootleg (OKI 2)

    // the ROM image's BRAM parts (loaded with the machine held in reset)
    input  logic        ld_prog_wr,
    input  logic [16:0] ld_prog_addr,
    input  logic        ld_prom_wr,
    input  logic  [9:0] ld_prom_addr,
    input  logic  [7:0] ld_data,

    // SDRAM read clients: 0 the video's tiles, 1 the CPU's tile ROM window, 2 OKI, 3 OKI 2
    output logic        m_req   [4],
    output logic [23:0] m_addr  [4],
    output logic  [4:0] m_len   [4],
    input  logic        m_ack   [4],
    input  logic        m_valid [4],
    input  logic [15:0] m_rdata,

    // MAME's input ports (active low as read)
    input  logic  [7:0] dsw1,
    input  logic  [7:0] dsw2,
    input  logic  [7:0] dsw3,
    input  logic  [7:0] in_p1,
    input  logic  [7:0] in_p2,
    input  logic  [7:0] in_sys,

    // video
    input  logic  [1:0] vmode,          // the picture's raster (Video Timing): 0 the board's, 1 and 2 the 263-line ones (rtl/hexion_video.sv)
    output logic        ce_pix,
    output logic        hs,
    output logic        vs,
    output logic        hblank,
    output logic        vblank,
    output logic        vblank_next,
    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,

    // audio: MAME's mix (OKI 0.5, SCC 0.5) as 16 bits, 46.875 kHz
    output logic signed [15:0] audio,

    output logic        frame_tick,     // one clock at the start of the game's vertical blank (line 256 of the board's raster)
    output logic [15:0] dbg_pc
);
    // ------------------------------------------------------------------ clock enables
    logic [4:0] div;
    always_ff @(posedge clk) div <= reset ? 5'd0 : div + 5'd1;
    wire  tick6   = (div[3:0] == 4'd15);        // the Z80's nominal cycle
    wire  ce_12   = (div[2:0] == 3'd7);
    wire  ce_scc  = (div == 5'd31);

    // the OKIs' sample ticks: 1.056 MHz / 132 = 8 kHz (every 12,000 clocks), / 165 = 6.4 kHz (every 15,000)
    logic [13:0] oki1_div, oki2_div;
    logic        oki1_tick, oki2_tick;
    always_ff @(posedge clk) begin
        oki1_tick <= 1'b0; oki2_tick <= 1'b0;
        if (reset) begin
            oki1_div <= 14'd0; oki2_div <= 14'd0;
        end else begin
            if (oki1_div == 14'd11999) begin oki1_div <= 14'd0; oki1_tick <= 1'b1; end else oki1_div <= oki1_div + 14'd1;
            if (oki2_div == 14'd14999) begin oki2_div <= 14'd0; oki2_tick <= 1'b1; end else oki2_div <= oki2_div + 14'd1;
        end
    end

    // ------------------------------------------------------------------ the Z80
    logic        cpu_ce;
    logic        stall;
    logic  [7:0] owed;                  // nominal cycles the Z80 has not had yet
    logic  [2:0] gap;                   // clocks since its last step (saturating at 7)
    always_comb cpu_ce = !reset && !stall && (gap == 3'd7) && ((owed != 8'd0) || tick6);
    always_ff @(posedge clk) begin
        if (reset) begin
            // one step at the first clock: tv80 spends a step after reset before its first fetch, which then ends with the first
            // nominal cycle, as MAME's Z80 starts executing at time 0
            owed <= 8'd1; gap <= 3'd7;
        end else begin
            gap <= cpu_ce ? 3'd0 : (gap == 3'd7) ? 3'd7 : gap + 3'd1;
            case ({tick6, cpu_ce})
                2'b10:   owed <= (owed == 8'hff) ? owed : owed + 8'd1;
                2'b01:   owed <= owed - 8'd1;
                default: ;
            endcase
        end
    end

    logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
    logic [15:0] A;
    logic  [7:0] cpu_di, cpu_do;
    logic        irq_line, nmi_line;

    tv80s_cen u_cpu (
        .reset_n(~reset), .clk(clk), .cen(cpu_ce), .wait_n(1'b1),
        .int_n(~irq_line), .nmi_n(~nmi_line), .busrq_n(1'b1),
        .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n),
        .rfsh_n(rfsh_n), .halt_n(), .busak_n(), .A(A), .di(cpu_di), .dout(cpu_do)
    );
    assign dbg_pc = A;

    // The Z80 steps on a clock enable at least 8 clocks apart, so its outputs are multicycle paths (Hexion.sdc): the board sees the
    // strobes four clocks after the CPU raises them. RD is low for one step (T2), the data is taken at its end; a write becomes one
    // pulse per bus cycle.
    wire  mem_rd_raw = !mreq_n && !rd_n;
    wire  mem_wr_raw = !mreq_n && !wr_n;
    logic [4:0] rd_dl, wr_dl;
    always_ff @(posedge clk) begin
        rd_dl <= {rd_dl[3:0], mem_rd_raw};
        wr_dl <= {wr_dl[3:0], mem_wr_raw};
    end
    wire  mem_rd   = rd_dl[3];
    wire  rd_start = rd_dl[3] && !rd_dl[4];
    wire  mem_wr   = wr_dl[3] && !wr_dl[4];

    // ------------------------------------------------------------------ decode
    wire sel_rom0  = (A[15] == 1'b0);
    wire sel_bank  = (A[15:13] == 3'b100);
    wire sel_wram  = (A[15:13] == 3'b101);
    wire sel_bkram = (A[15:13] == 3'b110) && (A != 16'hdfff);
    wire sel_bctl  = (A == 16'hdfff);
    wire sel_scc   = (A[15:8] == 8'he8) && !bootleg;
    wire sel_ccu   = (A[15:4] == 12'hf00);
    wire sel_oki1  = (A == 16'hf200);
    wire sel_bsw   = (A == 16'hf480);
    wire sel_coin  = (A == 16'hf4c0);
    wire sel_gsel  = (A == 16'hf500);
    wire sel_oki2  = (A == 16'hf5c0) && bootleg;

    // ------------------------------------------------------------------ the board's registers
    logic  [3:0] rombank;
    logic        pmcbank;
    logic  [7:0] bankctrl;
    logic        rambank;
    logic  [7:0] gfxsel;
    logic        flip;
    logic  [7:0] pmc0, pmc1, pmc2, pmc3, pmc4;      // the PMC RAM's first bytes, for the fill commands

    // ------------------------------------------------------------------ program ROM, work RAM
    wire  [16:0] prog_a = sel_rom0 ? {2'b00, A[14:0]} : {rombank, A[12:0]};
    logic  [7:0] prog_q, wram_q;
    hexion_spram #(.AW(17), .DW(8)) u_prog (.clk(clk), .addr(reset ? ld_prog_addr : prog_a), .wdata(ld_data),
                                            .we(reset && ld_prog_wr), .q(prog_q));
    hexion_spram #(.AW(13), .DW(8)) u_wram (.clk(clk), .addr(A[12:0]), .wdata(cpu_do), .we(mem_wr && sel_wram), .q(wram_q));

    // ------------------------------------------------------------------ VRAM (two banks of 2048 x 4 bytes) and the PMC RAM
    logic        fill_busy;
    logic        fill_bank;
    logic [12:0] fill_addr;             // byte (clear) or word (fill) address
    logic        fill_mode;             // 1 the whole bank, 0 sixteen bytes
    logic  [7:0] fill_val;
    logic  [4:0] fill_n;

    logic [10:0] va_addr;
    logic [31:0] va_wdata;
    logic  [3:0] va_we [2];
    logic [31:0] va_q [2];
    logic [10:0] vb_addr;
    logic [31:0] vb_q [2];

    wire  [12:0] boff = A[12:0];
    always_comb begin
        va_we[0] = 4'd0; va_we[1] = 4'd0;
        if (fill_busy) begin
            va_addr  = fill_mode ? fill_addr[10:0] : fill_addr[12:2];
            va_wdata = {4{fill_val}};
            va_we[fill_bank] = fill_mode ? 4'hf : (4'd1 << fill_addr[1:0]);
        end else begin
            va_addr  = boff[12:2];
            va_wdata = {4{cpu_do}};
            if (mem_wr && sel_bkram && bankctrl == 8'd0 && pmcbank) va_we[rambank] = 4'd1 << boff[1:0];
        end
    end

    genvar gb, gl;
    generate
        for (gb = 0; gb < 2; gb++) begin : g_vbank
            for (gl = 0; gl < 4; gl++) begin : g_lane
                hexion_dpram #(.AW(11), .DW(8)) u_v (.clk(clk), .a_addr(va_addr), .a_wdata(va_wdata[gl*8 +: 8]), .a_we(va_we[gb][gl]),
                                                     .a_q(va_q[gb][gl*8 +: 8]), .b_addr(vb_addr), .b_q(vb_q[gb][gl*8 +: 8]));
            end
        end
    endgenerate

    logic  [7:0] pmc_q;
    wire         pmc_we = mem_wr && sel_bkram && bankctrl == 8'd2 && boff < 13'h800 && pmcbank;
    hexion_spram #(.AW(11), .DW(8)) u_pmc (.clk(clk), .addr(boff[10:0]), .wdata(cpu_do), .we(pmc_we), .q(pmc_q));

    // ------------------------------------------------------------------ the tile ROM window (an SDRAM read; the Z80 waits)
    wire         sel_win = sel_bkram && (gfxsel != 8'd0) && (boff < 13'h1000);
    wire  [18:0] win_b   = {gfxsel[6:0], boff[11:0]};     // the byte in MAME's "tiles" region
    logic  [7:0] win_data;
    logic        win_ready, win_wait;
    always_ff @(posedge clk) begin
        if (reset) begin
            m_req[1] <= 1'b0; win_ready <= 1'b0; win_wait <= 1'b0;
        end else begin
            if (rd_start && sel_win) begin
                // the SDRAM keeps the halves' byte pairs side by side: word {b[17:1], b[18]}, the even byte in bits 15:8
                m_req[1]  <= 1'b1;
                m_addr[1] <= {6'd0, win_b[17:1], win_b[18]};
                m_len[1]  <= 5'd1;
                win_ready <= 1'b0;
                win_wait  <= 1'b1;
            end
            if (m_ack[1]) m_req[1] <= 1'b0;
            if (m_valid[1] && win_wait) begin
                win_data <= win_b[0] ? m_rdata[7:0] : m_rdata[15:8];
                win_wait <= 1'b0;
            end
            if (!win_wait && !win_ready && !(rd_start && sel_win) && m_req[1] == 1'b0 && mem_rd && sel_win) win_ready <= 1'b1;
        end
    end

    // ------------------------------------------------------------------ the CCU (K053252) registers and the interrupts
    logic  [7:0] ccu [16];
    logic  [7:0] int_time;
    logic signed [15:0] int_cnt;
    logic  [8:0] vpos;
    logic        line_start;
    wire  [9:0] vct = {1'b0, vpos} - 10'd288;             // MAME's read-back: vpos - VC (VC = 288)
    wire  [7:0] ccu_q = (A[3:0] == 4'he) ? {7'd0, vct[8]} : (A[3:0] == 4'hf) ? vct[7:0] : ccu[A[3:0]];

    // MAME's scanline timer: the first call 1/540 s after reset (177,777.8 clocks), then at dot 0 of every line; both 25 clocks early
    // (above): the line's call at dot 764 of the line before (cb_tick), the first at clock 177,766 (a Z80 instruction ending at
    // cycle 11,112 or later takes it, as in MAME, whose call at cycle 11,111.1 is taken after the instruction it falls in)
    //
    // The lines are raised on the Z80's own timeline: if it is behind (owed cycles, after a wait) when a call raises one, the line
    // goes up only once it has taken those cycles, so it sees the line on the step MAME's Z80 would (without this, a call that
    // comes while the Z80 is catching up is taken some instructions early; the 263-line Video Timing moves the video's tile
    // fetches, which delay the tile ROM window's reads, to any point of the game's line).
    logic [17:0] first_cnt;
    logic        cb_on;
    logic        cb_tick;
    wire         cb = cb_on ? cb_tick : (first_cnt == 18'd177766);
    wire   [7:0] owed_next = (tick6 && !cpu_ce) ? owed + 8'd1 : (cpu_ce && !tick6) ? owed - 8'd1 : owed;   // after this clock
    wire         irq_ev = cb && vpos == 9'd255;                  // the line about to begin is 256 (the first call's is 284)
    wire         nmi_ev = cb && (int_cnt - 16'sd1 <= 16'sd0);
    logic        irq_pend, nmi_pend;
    logic  [7:0] irq_wait, nmi_wait;                            // the Z80's steps still to come before the line goes up
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < 16; i++) ccu[i] <= 8'd0;
            ccu[8] <= 8'd1;
            int_time <= 8'd0; int_cnt <= 16'sd0;
            irq_line <= 1'b0; nmi_line <= 1'b0;
            irq_pend <= 1'b0; nmi_pend <= 1'b0;
            first_cnt <= 18'd0; cb_on <= 1'b0;
        end else begin
            if (!cb_on) first_cnt <= first_cnt + 18'd1;
            if (cb) begin
                cb_on <= 1'b1;
                if (nmi_ev) int_cnt <= {8'd0, int_time};
                else        int_cnt <= int_cnt - 16'sd1;
            end
            if (irq_ev) begin
                if (owed_next == 8'd0) irq_line <= 1'b1;
                else begin irq_pend <= 1'b1; irq_wait <= owed_next; end
            end else if (irq_pend && cpu_ce) begin
                irq_wait <= irq_wait - 8'd1;
                if (irq_wait == 8'd1) begin irq_line <= 1'b1; irq_pend <= 1'b0; end
            end
            if (nmi_ev) begin
                if (owed_next == 8'd0) nmi_line <= 1'b1;
                else begin nmi_pend <= 1'b1; nmi_wait <= owed_next; end
            end else if (nmi_pend && cpu_ce) begin
                nmi_wait <= nmi_wait - 8'd1;
                if (nmi_wait == 8'd1) begin nmi_line <= 1'b1; nmi_pend <= 1'b0; end
            end
            if (mem_wr && sel_ccu) begin
                ccu[A[3:0]] <= cpu_do;
                if (A[3:0] == 4'hd) int_time <= cpu_do;
                if (A[3:0] == 4'he) irq_line <= 1'b0;
                if (A[3:0] == 4'hf) nmi_line <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------ the board's register writes and the PMC's fills
    always_ff @(posedge clk) begin
        if (reset) begin
            rombank <= 4'd0; pmcbank <= 1'b0; bankctrl <= 8'd0; rambank <= 1'b0; gfxsel <= 8'd0; flip <= 1'b0;
            fill_busy <= 1'b0;
            pmc0 <= 8'd0; pmc1 <= 8'd0; pmc2 <= 8'd0; pmc3 <= 8'd0; pmc4 <= 8'd0;
        end else begin
            if (mem_wr) begin
                if (sel_bctl) bankctrl <= cpu_do;
                if (sel_gsel) gfxsel <= cpu_do;
                if (sel_coin) flip <= cpu_do[5];
                if (sel_bkram && bankctrl == 8'd3 && boff == 13'd0 && cpu_do[7:1] == 7'd0) rambank <= cpu_do[0];
                if (pmc_we) begin
                    case (boff)
                        13'd0: pmc0 <= cpu_do;
                        13'd1: pmc1 <= cpu_do;
                        13'd2: pmc2 <= cpu_do;
                        13'd3: pmc3 <= cpu_do;
                        13'd4: pmc4 <= cpu_do;
                        default: ;
                    endcase
                end
                if (sel_bsw) begin
                    rombank <= cpu_do[3:0];
                    pmcbank <= cpu_do[7];
                    if (cpu_do[6]) begin
                        fill_busy <= 1'b1;
                        if (pmc0 <= 8'd1) begin
                            fill_mode <= 1'b1; fill_bank <= pmc0[0]; fill_val <= pmc1; fill_addr <= 13'd0;
                        end else begin
                            fill_mode <= 1'b0; fill_bank <= pmc4[0]; fill_val <= 8'd0; fill_addr <= {pmc3[4:0], pmc2}; fill_n <= 5'd0;
                        end
                    end
                end
            end
            if (fill_busy) begin
                if (fill_mode) begin
                    fill_addr <= fill_addr + 13'd1;
                    if (fill_addr[10:0] == 11'h7ff) fill_busy <= 1'b0;
                end else begin
                    fill_addr <= fill_addr + 13'd1;
                    fill_n <= fill_n + 5'd1;
                    if (fill_n == 5'd15) fill_busy <= 1'b0;
                end
            end
        end
    end

    // the Z80 waits for the window's data and for a fill
    always_comb stall = fill_busy || (mem_rd && sel_win && !win_ready);

    // ------------------------------------------------------------------ the read data
    logic  [7:0] scc_q;
    logic  [7:0] bk_q;
    always_comb begin
        if (sel_win)                                  bk_q = win_data;
        else if (bankctrl == 8'd0)                    bk_q = va_q[rambank][boff[1:0]*8 +: 8];
        else if (bankctrl == 8'd2 && boff < 13'h800)  bk_q = pmc_q;
        else                                          bk_q = 8'd0;
    end
    always_ff @(posedge clk) begin
        if      (sel_rom0 || sel_bank) cpu_di <= prog_q;
        else if (sel_wram)             cpu_di <= wram_q;
        else if (sel_bkram)            cpu_di <= bk_q;
        else if (sel_scc)              cpu_di <= (A[7] == 1'b0) ? scc_q : 8'd0;
        else if (sel_ccu)              cpu_di <= ccu_q;
        else if (A == 16'hf400)        cpu_di <= dsw1;
        else if (A == 16'hf401)        cpu_di <= dsw2;
        else if (A == 16'hf402)        cpu_di <= in_p1;
        else if (A == 16'hf403)        cpu_di <= in_p2;
        else if (A == 16'hf440)        cpu_di <= dsw3;
        else if (A == 16'hf441)        cpu_di <= in_sys;
        else                           cpu_di <= 8'd0;
    end

    // ------------------------------------------------------------------ video
    logic [3:0] vr, vg, vb;
    hexion_video u_video (
        .clk(clk), .reset(reset), .ce_pix(ce_12), .flip(flip), .vmode(vmode),
        .vram_addr(vb_addr), .vram_q0(vb_q[0]), .vram_q1(vb_q[1]),
        .t_req(m_req[0]), .t_addr(m_addr[0]), .t_len(m_len[0]), .t_ack(m_ack[0]), .t_valid(m_valid[0]), .t_rdata(m_rdata),
        .prom_wr(reset && ld_prom_wr), .prom_addr(ld_prom_addr), .prom_data(ld_data),
        .vpos(vpos), .line_start(line_start), .cb_tick(cb_tick),
        .o_ce(ce_pix), .o_hs(hs), .o_vs(vs), .o_hblank(hblank), .o_vblank(vblank), .o_vblank_next(vblank_next),
        .o_r(vr), .o_g(vg), .o_b(vb)
    );
    // the PROMs' 4 bits through the board's resistor network, as MAME's palette_init_rgb_444_proms weighs them
    function automatic logic [7:0] dac(input logic [3:0] v);
        dac = (v[0] ? 8'h0e : 8'h00) + (v[1] ? 8'h1f : 8'h00) + (v[2] ? 8'h43 : 8'h00) + (v[3] ? 8'h8f : 8'h00);
    endfunction
    assign r = dac(vr);
    assign g = dac(vg);
    assign b = dac(vb);
    always_ff @(posedge clk) frame_tick <= line_start && vpos == 9'd256;

    // ------------------------------------------------------------------ sound
    logic signed [10:0] scc_s;
    logic signed [13:0] oki1_s, oki2_s;
    hexion_scc u_scc (
        .clk(clk), .reset(reset), .ce(ce_scc),
        .wr(mem_wr && sel_scc), .rd(rd_start && sel_scc), .addr(A[7:0]), .din(cpu_do), .dout(scc_q), .sample(scc_s)
    );
    hexion_oki #(.ROM_W(24'h040000)) u_oki1 (
        .clk(clk), .reset(reset), .tick(oki1_tick), .wr(mem_wr && sel_oki1), .din(cpu_do),
        .r_req(m_req[2]), .r_addr(m_addr[2]), .r_len(m_len[2]), .r_ack(m_ack[2]), .r_valid(m_valid[2]), .r_rdata(m_rdata),
        .sample(oki1_s)
    );
    hexion_oki #(.ROM_W(24'h060000)) u_oki2 (
        .clk(clk), .reset(reset || !bootleg), .tick(oki2_tick), .wr(mem_wr && sel_oki2), .din(cpu_do),
        .r_req(m_req[3]), .r_addr(m_addr[3]), .r_len(m_len[3]), .r_ack(m_ack[3]), .r_valid(m_valid[3]), .r_rdata(m_rdata),
        .sample(oki2_s)
    );

    // MAME's mono mix, both routes 0.5, as 16 bits (x 32768): 8 * OKI + 16 * SCC; the SCC's 3 MHz samples are averaged over 64
    // (one output sample every 2,048 clocks), MAME resamples its stream to the output rate
    logic [5:0]  scc_n;
    logic signed [16:0] scc_acc;
    logic signed [16:0] scc_avg4;       // the sum of 64 samples / 4 = 16 * the mean
    always_ff @(posedge clk) begin
        if (reset) begin
            scc_n <= 6'd0; scc_acc <= 17'sd0; scc_avg4 <= 17'sd0;
        end else if (ce_scc) begin
            if (scc_n == 6'd63) begin
                scc_avg4 <= (scc_acc + 17'(scc_s)) >>> 2;
                scc_acc  <= 17'sd0;
            end else
                scc_acc <= scc_acc + 17'(scc_s);
            scc_n <= scc_n + 6'd1;
        end
    end
    wire signed [19:0] mix = bootleg ? ($signed({{6{oki1_s[13]}}, oki1_s}) <<< 3) + ($signed({{6{oki2_s[13]}}, oki2_s}) <<< 3)
                                     : ($signed({{6{oki1_s[13]}}, oki1_s}) <<< 3) + 20'(scc_avg4);
    always_ff @(posedge clk) audio <= (mix > 20'sd32767) ? 16'sd32767 : (mix < -20'sd32768) ? $signed(16'h8000) : mix[15:0];

    wire unused = &{1'b0, m1_n, iorq_n, rfsh_n, va_q[0], va_q[1], dsw3, cpu_ce};
endmodule
`default_nettype wire
