// The whole-machine bench: hexion_core behind hexion_sdram and the behavioural SDRAM (sim/sdram_model.sv). The ROM image
// (+IMAGE=<file>, tools/hexion_rom.py) is downloaded first through hexion_loader, a byte a clock while the SDRAM's download FIFO takes
// them, with the machine held in reset, as Hexion.sv does it; then the machine runs. +DSW=<6 hex digits> sets DSW1, DSW2, DSW3
// (MAME's defaults FF4FFF). Driven by sim/tb_hexion.cpp.
//
// At every frame_tick (the start of the vertical blank, MAME's frame_done) with +DUMPDIR=<dir> and the frame in +DUMPFROM / +DUMPTO /
// +DUMPEVERY, <dir>/ram_<frame>.bin: the work RAM (8 KB), VRAM bank 0 and bank 1 (8 KB each), the board's registers (16 bytes:
// rombank, pmcbank, bankctrl, rambank, gfxsel, flip, int_time, then the CCU's 0..8), as tools/lua/dump.lua writes MAME's.
`default_nettype none
module tb_top (
    input  logic        clk,
    input  logic        reset_in,
    input  logic  [7:0] in_p1,
    input  logic  [7:0] in_p2,
    input  logic  [7:0] in_sys,
    output logic        ce_pix,
    output logic        hblank,
    output logic        vblank,
    output logic        hs,
    output logic        vs,
    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,
    output logic signed [15:0] audio,
    output logic        frame_tick,
    output logic        running,
    output logic [15:0] dbg_pc
);
    // ------------------------------------------------------------------ the image
    logic [7:0] img [1 << 21];
    int         img_len = 0;
    logic [23:0] dsw = 24'hFF4FFF;
    initial begin
        string f;
        int fd;
        if ($value$plusargs("IMAGE=%s", f)) begin
            fd = $fopen(f, "rb");
            if (fd == 0) begin $display("tb: cannot open %s", f); $finish; end
            img_len = $fread(img, fd);
            $fclose(fd);
            $display("tb: image %0d bytes from %s", img_len, f);
        end else begin
            $display("tb: no +IMAGE=<file>"); $finish;
        end
        void'($value$plusargs("DSW=%h", dsw));
    end

    // ------------------------------------------------------------------ the SDRAM
    logic        m_req [4], m_ack [4], m_valid [4];
    logic [23:0] m_addr [4];
    logic  [4:0] m_len [4];
    logic [15:0] m_rdata;
    logic        sd_ready, dl_busy;
    wire  [15:0] SDRAM_DQ;
    logic [12:0] SDRAM_A;
    logic  [1:0] SDRAM_BA;
    logic        SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_CKE;

    logic        ld_wr, ld_prog_wr, ld_prom_wr, ld_board_wr;
    logic [24:0] ld_addr;
    logic  [7:0] ld_data, ld_bdata;
    logic [16:0] ld_prog_addr;
    logic  [9:0] ld_prom_addr;

    hexion_sdram #(.P_SHORT_INIT(1'b1), .NC(4)) u_sdram (
        .clk(clk), .rst_n(!reset_in), .o_ready(sd_ready), .i_rd_late(1'b0),
        .i_dl_wr(ld_wr), .i_dl_addr(ld_addr), .i_dl_data(ld_data), .o_dl_busy(dl_busy),
        .c_req(m_req), .c_addr(m_addr), .c_len(m_len), .c_ack(m_ack), .c_valid(m_valid), .o_rdata(m_rdata),
        .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_CKE(SDRAM_CKE)
    );
    sdram_model u_sdr (
        .clk(clk), .A(SDRAM_A), .BA(SDRAM_BA), .DQ(SDRAM_DQ), .DQML(SDRAM_DQML), .DQMH(SDRAM_DQMH),
        .nCS(SDRAM_nCS), .nRAS(SDRAM_nRAS), .nCAS(SDRAM_nCAS), .nWE(SDRAM_nWE), .CKE(SDRAM_CKE)
    );

    // ------------------------------------------------------------------ the download
    int          dl_i = 0;
    logic        dl_wr;
    logic [20:0] dl_addr;
    logic  [7:0] dl_data;
    wire         dl_on = (dl_i < img_len);
    always_ff @(posedge clk) begin
        dl_wr <= 1'b0;
        if (!reset_in && sd_ready && dl_on && !dl_busy && !dl_wr) begin
            dl_wr <= 1'b1; dl_addr <= 21'(dl_i); dl_data <= img[dl_i];
            dl_i <= dl_i + 1;
        end
    end

    hexion_loader u_loader (
        .clk(clk), .dl_wr(dl_wr), .dl_addr(dl_addr), .dl_data(dl_data),
        .o_wr(ld_wr), .o_addr(ld_addr), .o_data(ld_data),
        .prog_wr(ld_prog_wr), .prog_addr(ld_prog_addr), .prom_wr(ld_prom_wr), .prom_addr(ld_prom_addr), .b_data(ld_bdata),
        .board_wr(ld_board_wr)
    );
    logic bootleg = 1'b0;
    always_ff @(posedge clk) if (ld_board_wr) bootleg <= ld_bdata[0];

    // ------------------------------------------------------------------ the machine
    logic mc_reset;
    logic [3:0] tail;           // a few clocks after the last byte, for the loader's and the FIFO's last writes
    always_ff @(posedge clk) begin
        if (reset_in || dl_on || dl_wr || dl_busy) tail <= 4'd0;
        else if (tail != 4'hf) tail <= tail + 4'd1;
        mc_reset <= reset_in || !sd_ready || (tail != 4'hf);
    end
    assign running = !mc_reset;

    logic vblank_next_unused;
    int   vmode_i = 0;      // +VMODE=n: the picture's raster (OSD Video Timing: 0 288 lines (Native), 1 263 lines (RT4K 54Hz), 2 263 lines (CRT+RT4K))
    initial void'($value$plusargs("VMODE=%d", vmode_i));
    wire  [1:0] vmode = 2'(vmode_i);
    hexion_core u_core (
        .clk(clk), .reset(mc_reset), .bootleg(bootleg), .vmode(vmode),
        .ld_prog_wr(ld_prog_wr), .ld_prog_addr(ld_prog_addr), .ld_prom_wr(ld_prom_wr), .ld_prom_addr(ld_prom_addr), .ld_data(ld_bdata),
        .m_req(m_req), .m_addr(m_addr), .m_len(m_len), .m_ack(m_ack), .m_valid(m_valid), .m_rdata(m_rdata),
        .dsw1(dsw[23:16]), .dsw2(dsw[15:8]), .dsw3(dsw[7:0]), .in_p1(in_p1), .in_p2(in_p2), .in_sys(in_sys),
        .ce_pix(ce_pix), .hs(hs), .vs(vs), .hblank(hblank), .vblank(vblank), .vblank_next(vblank_next_unused), .r(r), .g(g), .b(b),
        .audio(audio), .frame_tick(frame_tick), .dbg_pc(dbg_pc)
    );

    // ------------------------------------------------------------------ the instruction trace: +ITRACE=<cycles> prints "I <cycle> <pc>"
    // at each opcode fetch (M1) for the Z80's first <cycles> cycles, <cycle> = the Z80 cycles before it, as MAME's debugger trace with
    // {tracelog "%d ",totalcycles} logs them (a prefixed instruction logs each of its M1 fetches here, once in MAME)
    // (+ITRACEFROM=<cycle> starts it later; the count starts at -1: tv80's step after reset, before its first fetch, is not a cycle)
    longint itrace = 0, itfrom = 0, zcyc = -1;
    logic   m1_d = 1'b1;
    initial begin void'($value$plusargs("ITRACE=%d", itrace)); void'($value$plusargs("ITRACEFROM=%d", itfrom)); end
    wire    it_on = (zcyc >= itfrom) && (zcyc < itrace);
    always_ff @(posedge clk) begin
        if (mc_reset) begin zcyc <= -1; m1_d <= 1'b1; end
        else begin
            if (u_core.cpu_ce) zcyc <= zcyc + 1;
            m1_d <= u_core.m1_n;
            if (!u_core.m1_n && m1_d && it_on) $display("I %0d %04x", zcyc, u_core.A);
            if (u_core.mem_wr && it_on) $display("W %0d %04x %02x", zcyc, u_core.A, u_core.cpu_do);
            if (u_core.cpu_ce && it_on && $test$plusargs("ITRACECE"))
                $display("C %0d m1 %b mreq %b rd %b wr %b iorq %b A %04x", zcyc, u_core.m1_n, u_core.mreq_n, u_core.rd_n, u_core.wr_n, u_core.iorq_n, u_core.A);
        end
    end

    // ------------------------------------------------------------------ +VWLOG: "V <frame> <line> <dot> <bank> <word>" at each of the
    // Z80's VRAM writes and "F <frame> <line> <dot> <bank> <whole bank>" at the start of each PMC fill: where in the game's raster
    // (vpos 0..287, dot 0..767) the game writes the tilemaps
    bit vwlog = 1'b0;
    initial vwlog = $test$plusargs("VWLOG");
    logic fill_d = 1'b0;
    always_ff @(posedge clk) if (vwlog && !mc_reset) begin
        fill_d <= u_core.fill_busy;
        if (u_core.fill_busy && !fill_d)
            $display("F %0d %0d %0d %0d %0d", frame, u_core.vpos, u_core.u_video.hpos, u_core.fill_bank, u_core.fill_mode);
        for (int k = 0; k < 2; k++)
            if (!u_core.fill_busy && u_core.va_we[k] != 4'd0)
                $display("V %0d %0d %0d %0d %0d", frame, u_core.vpos, u_core.u_video.hpos, k, u_core.va_addr);
    end

    // ------------------------------------------------------------------ +OWEDLOG: "O <frame> <line> <irq|nmi> <cycles>" for each
    // interrupt the CCU raises while the Z80 is behind (owed cycles after a wait), which the core then holds back that many steps
    bit owedlog = 1'b0;
    initial owedlog = $test$plusargs("OWEDLOG");
    always_ff @(posedge clk) if (owedlog && !mc_reset && u_core.owed_next != 8'd0) begin
        if (u_core.irq_ev) $display("O %0d %0d irq %0d", frame, u_core.vpos, u_core.owed_next);
        if (u_core.nmi_ev) $display("O %0d %0d nmi %0d", frame, u_core.vpos, u_core.owed_next);
    end

    // ------------------------------------------------------------------ the dumps
    string dumpdir = "";
    int    dfrom = 0, dto = -1, devery = 1;
    initial begin
        void'($value$plusargs("DUMPDIR=%s", dumpdir));
        void'($value$plusargs("DUMPFROM=%d", dfrom));
        void'($value$plusargs("DUMPTO=%d", dto));
        void'($value$plusargs("DUMPEVERY=%d", devery));
    end
    int frame = 0;
    always_ff @(posedge clk) begin
        if (frame_tick) begin
            if (dumpdir != "" && frame >= dfrom && (dto < 0 || frame <= dto) && ((frame - dfrom) % devery) == 0) dump(frame);
            frame <= frame + 1;
        end
    end

    task automatic dump(input int f);
        int fd;
        string fn;
        fn = $sformatf("%s/ram_%0d.bin", dumpdir, f);
        fd = $fopen(fn, "wb");
        for (int i = 0; i < 8192; i++) $fwrite(fd, "%c", u_core.u_wram.mem[i]);
        for (int i = 0; i < 8192; i++) $fwrite(fd, "%c", vbyte(0, i));
        for (int i = 0; i < 8192; i++) $fwrite(fd, "%c", vbyte(1, i));
        $fwrite(fd, "%c%c%c%c%c%c%c", {4'd0, u_core.rombank}, {7'd0, u_core.pmcbank}, u_core.bankctrl, {7'd0, u_core.rambank},
                u_core.gfxsel, {7'd0, u_core.flip}, u_core.int_time);
        for (int i = 0; i < 9; i++) $fwrite(fd, "%c", u_core.ccu[i]);
        $fclose(fd);
    endtask

    function automatic logic [7:0] vbyte(input int bank, input int a);
        logic [10:0] w;
        w = 11'(a >> 2);
        case ({bank[0], a[1:0]})
            3'd0: vbyte = u_core.g_vbank[0].g_lane[0].u_v.mem[w];
            3'd1: vbyte = u_core.g_vbank[0].g_lane[1].u_v.mem[w];
            3'd2: vbyte = u_core.g_vbank[0].g_lane[2].u_v.mem[w];
            3'd3: vbyte = u_core.g_vbank[0].g_lane[3].u_v.mem[w];
            3'd4: vbyte = u_core.g_vbank[1].g_lane[0].u_v.mem[w];
            3'd5: vbyte = u_core.g_vbank[1].g_lane[1].u_v.mem[w];
            3'd6: vbyte = u_core.g_vbank[1].g_lane[2].u_v.mem[w];
            default: vbyte = u_core.g_vbank[1].g_lane[3].u_v.mem[w];
        endcase
    endfunction
endmodule
`default_nettype wire
