//============================================================================
//
//  Hexion (Konami GX122, 1992; and the Impeuropex bootleg) for MiSTer.
//
//  Written for MiSTer from MAME 0.289's driver (src/mame/konami/hexion.cpp, with src/devices/machine/k053252.cpp,
//  src/devices/sound/k051649.cpp and okim6295.cpp). The Z80 is Guy Hutchison's tv80 (modules/cpu-tv80); the platform layer (the
//  SDRAM controller, the fast load, the standby raster, CRT Adjust, the video path) follows the owner's Rabbit and Mystic Warriors cores.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;       // signed samples
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////

wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire         direct_video;
wire  [21:0] gamma_bus;

wire  [1:0] ar = status[122:121];

`include "build_id.v"
localparam CONF_STR = {
	"Hexion;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[34:32],Scale,Normal,V-Integer,HV-Integer,Narrower HV-Integer,HV-Integer+;",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O[54:53],Video Timing,288 lines (Native),263 lines (RT4K 54Hz),263 lines (CRT+RT4K);",
	"P1,CRT Adjust;",
	"D2P1O[35],CRT Adjust,Off,On;",
	"H1P1O[40:36],CRT H-Size,0,+1,+2,+3,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[47:41],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[52:48],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"DIP;",
	"-;",
	"O[9:8],Volume,Normal,-6 dB,-12 dB,+6 dB;",
	"-;",
	"R0,Reset;",
	"J1,Rotate Left,Rotate Right,Start,Coin;",
	"jn,A,B,Start,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;           // 96 MHz: the machine
wire clk_sdram;         // 96 MHz, shifted: the SDRAM chip's clock pin
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.locked(pll_locked)
);

assign SDRAM_CLK = clk_sdram;

///////////////////////////////////////////////////

wire         ioctl_download;
wire         ioctl_wr;
wire  [15:0] ioctl_index;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire         dl_busy;

wire  [31:0] joystick_0, joystick_1;
wire  [10:0] ps2_key;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask({13'd0, |status[54:53], ~(status[35] & ~|status[54:53]), direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),
	.gamma_bus(gamma_bus),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(dl_busy),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

///////////////////////   CONTROLS   ///////////////////////

// keyboard: 1 / 2 start, 5 / 6 coin, 9 service, F2 the service mode (MAME's defaults; F2 holds the DIP's "On" while pressed)
reg key_start1, key_start2, key_coin1, key_coin2, key_service, key_test;
always @(posedge clk_sys) begin
	reg old_stb;
	old_stb <= ps2_key[10];
	if (old_stb != ps2_key[10]) begin
		case (ps2_key[8:0])
			9'h016: key_start1  <= ps2_key[9];
			9'h01E: key_start2  <= ps2_key[9];
			9'h02E: key_coin1   <= ps2_key[9];
			9'h036: key_coin2   <= ps2_key[9];
			9'h046: key_service <= ps2_key[9];
			9'h006: key_test    <= ps2_key[9];      // F2
			default: ;
		endcase
	end
end

// joystick bits: 0 right, 1 left, 2 down, 3 up, 4 / 5 buttons 1 / 2, 6 start, 7 coin (the J1 line above)
wire start1 = joystick_0[6] | key_start1, coin1 = joystick_0[7] | key_coin1;
wire start2 = joystick_1[6] | key_start2, coin2 = joystick_1[7] | key_coin2;

// MAME's P1 / P2 (f402 / f403, KONAMI8_B12_START), active low: 0 left, 1 right, 2 up, 3 down, 4 / 5 buttons 1 / 2, 6 unused, 7 start
wire [7:0] in_p1 = ~{start1, 1'b0, joystick_0[5], joystick_0[4], joystick_0[2], joystick_0[3], joystick_0[0], joystick_0[1]};
wire [7:0] in_p2 = ~{start2, 1'b0, joystick_1[5], joystick_1[4], joystick_1[2], joystick_1[3], joystick_1[0], joystick_1[1]};
// SYSTEM (f441): 0 / 1 coin 1 / 2, 2 service 1 (active low), 3 the PMC's busy flag (active high, MAME: 0), 7:4 unused (1)
wire [7:0] in_sys = {4'hF, 1'b0, ~key_service, ~coin2, ~coin1};

// the DIP switches (the MRA's <switches>, ioctl index 254): DSW1, DSW2, DSW3 as MAME reads them; MAME's defaults until they come
reg [7:0] sw[3];
initial begin sw[0] = 8'hFF; sw[1] = 8'h4F; sw[2] = 8'hFF; end
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index[7:0] == 8'd254) && !ioctl_addr[24:2] && ioctl_addr[1:0] != 2'd3) sw[ioctl_addr[1:0]] <= ioctl_dout;
wire [7:0] dsw3 = sw[2] & ~{5'd0, key_test, 2'd0};     // bit 2: the service mode (active low)

///////////////////////   MEMORY   ///////////////////////

// the ROM image: MRA index 0
wire        rom_dl = ioctl_download && (ioctl_index[7:0] == 8'd0);

// Fast load (the MRA's address= attribute): Main_MiSTer copies the image into the DDR3 (byte 0x32000000) and ends a download that
// carries only a start address, the image's length; hexion_fastload reads it back and plays it into the loader. An older Main_MiSTer
// streams the bytes as before. (The owner's Rabbit core, from the Metro core.)
reg         rom_dl_d;
always @(posedge clk_sys) rom_dl_d <= rom_dl;
wire        dl_start = rom_dl && !rom_dl_d;
wire        dl_done  = !rom_dl && rom_dl_d;
reg         fast_dl = 1'b0;
reg  [26:0] fast_len;
wire        fl_go    = fast_dl && dl_done;
wire        fl_done, fl_busy_unused;
always @(posedge clk_sys) begin
	if (dl_start) begin fast_dl <= (ioctl_addr != 27'd0); fast_len <= ioctl_addr; end
	else if (fl_done || !pll_locked) fast_dl <= 1'b0;
end
wire        fl_wr;
wire [25:0] fl_addr;
wire  [7:0] fl_data;
wire        fl_ddr_rd;
wire [24:0] fl_ddr_addr;
wire  [7:0] fl_ddr_burst;

hexion_fastload u_fastload
(
	.clk(clk_sys), .rst(~pll_locked), .go(fl_go), .len(fast_len), .busy(fl_busy_unused), .done(fl_done),
	.ddr_rd(fl_ddr_rd), .ddr_addr(fl_ddr_addr), .ddr_burst(fl_ddr_burst), .ddr_busy(DDRAM_BUSY), .ddr_dout(DDRAM_DOUT), .ddr_dready(DDRAM_DOUT_READY),
	.o_wr(fl_wr), .o_addr(fl_addr), .o_data(fl_data), .hold(dl_busy)
);
assign DDRAM_CLK      = clk_sys;
assign DDRAM_ADDR     = {4'd3, fl_ddr_addr};
assign DDRAM_BURSTCNT = fl_ddr_burst;
assign DDRAM_RD       = fl_ddr_rd;
assign DDRAM_WE       = 1'b0;
assign DDRAM_DIN      = 64'd0;
assign DDRAM_BE       = 8'hFF;

wire        ld_wr, ld_prog_wr, ld_prom_wr, ld_board_wr;
wire [24:0] ld_addr;
wire  [7:0] ld_data, ld_bdata;
wire [16:0] ld_prog_addr;
wire  [9:0] ld_prom_addr;

hexion_loader u_loader
(
	.clk(clk_sys),
	.dl_wr(fl_wr || (ioctl_wr && rom_dl)), .dl_addr(fl_wr ? fl_addr[20:0] : ioctl_addr[20:0]), .dl_data(fl_wr ? fl_data : ioctl_dout),
	.o_wr(ld_wr), .o_addr(ld_addr), .o_data(ld_data),
	.prog_wr(ld_prog_wr), .prog_addr(ld_prog_addr), .prom_wr(ld_prom_wr), .prom_addr(ld_prom_addr), .b_data(ld_bdata),
	.board_wr(ld_board_wr)
);

// the board byte of the image: 0 the Konami board, 1 the bootleg
reg bootleg = 1'b0;
always @(posedge clk_sys) if (ld_board_wr) bootleg <= ld_bdata[0];

// the SDRAM and its four read clients (rtl/hexion_core.sv)
wire        m_req [4], m_ack [4], m_valid [4];
wire [23:0] m_addr [4];
wire  [4:0] m_len [4];
wire [15:0] m_rdata;
wire        mem_ready;

hexion_sdram #(.NC(4)) u_sdram
(
	.clk(clk_sys), .rst_n(pll_locked), .o_ready(mem_ready), .i_rd_late(1'b0),
	.i_dl_wr(ld_wr), .i_dl_addr(ld_addr), .i_dl_data(ld_data), .o_dl_busy(dl_busy),
	.c_req(m_req), .c_addr(m_addr), .c_len(m_len), .c_ack(m_ack), .c_valid(m_valid), .o_rdata(m_rdata),
	.SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_CKE(SDRAM_CKE)
);

///////////////////////   THE MACHINE   ///////////////////////

wire        reset_sw = RESET | status[0] | buttons[1];
// the SDRAM's download queue is busy only above 12 of its 16 words: after the image's last byte the machine waits 1,024 clocks more,
// for the queue's last writes (at most 16 words of about 10 clocks each, a refresh between) to land
reg   [9:0] dl_tail = 10'd0;
always @(posedge clk_sys) dl_tail <= ld_wr ? 10'h3ff : (dl_tail != 10'd0) ? dl_tail - 10'd1 : 10'd0;
// held while a ROM loads and until the memory is up; registered, it fans out to the whole core
reg         mc_rst = 1'b1;
always @(posedge clk_sys) mc_rst <= reset_sw | rom_dl | fast_dl | dl_busy | (dl_tail != 10'd0) | ~mem_ready | ~pll_locked;

wire        ce_pix, hs, vs, hblank, vblank, vblank_next;
wire  [7:0] r, g, b;
wire signed [15:0] snd;
wire        frame_tick;

// Video Timing (rtl/hexion_video.sv): 288 lines (Native), the board's raster (15.625 kHz, 54.25 Hz), for a CRT and the framework's
// HDMI scaler; 263 lines (RT4K 54Hz), the board's frame time on 263 lines (14.27 kHz, 8.73 MHz dots, in step with the game) for a
// RetroTINK 4K in direct video, which takes the board's 288 lines as "MiSTer Gen." and drops out now and then; 263 lines (CRT+RT4K),
// the board's 15.625 kHz line on 263 lines (59.41 Hz, free of the game's 54.25 Hz frame) for a CRT and the RT4K both. The game runs
// on the board's raster in every mode
reg   [1:0] vmode = 2'd0;
always @(posedge clk_sys) vmode <= (status[54:53] == 2'd3) ? 2'd0 : status[54:53];

hexion_core u_core
(
	.clk(clk_sys), .reset(mc_rst), .bootleg(bootleg),
	.ld_prog_wr(ld_prog_wr), .ld_prog_addr(ld_prog_addr), .ld_prom_wr(ld_prom_wr), .ld_prom_addr(ld_prom_addr), .ld_data(ld_bdata),
	.m_req(m_req), .m_addr(m_addr), .m_len(m_len), .m_ack(m_ack), .m_valid(m_valid), .m_rdata(m_rdata),
	.dsw1(sw[0]), .dsw2(sw[1]), .dsw3(dsw3), .in_p1(in_p1), .in_p2(in_p2), .in_sys(in_sys),
	.vmode(vmode), .ce_pix(ce_pix), .hs(hs), .vs(vs), .hblank(hblank), .vblank(vblank), .vblank_next(vblank_next), .r(r), .g(g), .b(b),
	.audio(snd), .frame_tick(frame_tick), .dbg_pc()
);

///////////////////////   AUDIO   ///////////////////////

// the OSD's volume steps on MAME's own level
function automatic signed [15:0] f_vol(input signed [15:0] v, input [1:0] st);
	reg signed [16:0] gv;
	begin
		gv = (st == 2'd0) ? {v[15], v} : (st == 2'd1) ? {{2{v[15]}}, v[15:1]} : (st == 2'd2) ? {{3{v[15]}}, v[15:2]} : {v, 1'b0};
		f_vol = (gv > 17'sd32767) ? 16'sd32767 : (gv < -17'sd32768) ? $signed(16'h8000) : gv[15:0];
	end
endfunction
assign AUDIO_L = f_vol(snd, status[9:8]);
assign AUDIO_R = f_vol(snd, status[9:8]);

///////////////////////   VIDEO   ///////////////////////

// while the machine is held in reset the core's raster does not run: a blank one of the same timing keeps the OSD's "Loading" pop-up alive
wire        sb_ce, sb_hblank, sb_vblank, sb_vblank_next, sb_hs, sb_vs;
hexion_standby u_standby (.clk(clk_sys), .vmode(vmode), .o_ce(sb_ce), .o_hblank(sb_hblank), .o_vblank(sb_vblank),
	.o_vblank_next(sb_vblank_next), .o_hs(sb_hs), .o_vs(sb_vs));
reg         sb_on = 1'b1;
always @(posedge clk_sys) sb_on <= mc_rst;

// the picture (or the standby raster), one clock later, before the CRT Adjust select. HBlank is the horizontal blank alone,
// toggling on every line, vertical blank lines included, with the vertical blank on VBlank: the framework's scandoubler
// (Scandoubler Fx, MiSTer.ini's forced_scandoubler) takes its line timing from the horizontal blank's edges and without them
// loses the vertical sync
reg  [23:0] vq_rgb;
reg         vq_hb, vq_vb, vq_vbn, vq_hs, vq_vs, vq_ce;
always @(posedge clk_sys) begin
	vq_rgb <= sb_on ? 24'd0 : {r, g, b};
	vq_hb  <= sb_on ? sb_hblank : hblank;
	vq_vb  <= sb_on ? sb_vblank : vblank;
	vq_vbn <= sb_on ? sb_vblank_next : vblank_next;
	vq_hs  <= sb_on ? sb_hs : hs;
	vq_vs  <= sb_on ? sb_vs : vs;
	vq_ce  <= sb_on ? sb_ce : ce_pix;
end

// CRT Adjust: the size, horizontal position and vertical position of the picture on a 15 kHz analog output (rmonic79's
// MiSTer-CRT-Adjust, modules/crt-adjust). The picture goes through a line buffer and is read out at a different pixel rate
// (H-Size) or a different place in the line (H-Position), and the vertical sync is delayed by whole lines (V-Shift); the sync
// pulses keep their rate, so the monitor stays locked. Off, the picture takes the path it always had. It does nothing while
// the scandoubler is in use (31 kHz) or with any Video Timing but the board's (the module is built for its 288 lines; the menu
// greys CRT Adjust out).
wire crt_sd = (|status[5:3]) | forced_scandoubler;

// the OSD values, as the menu counts them: H-Size 0..+3 then -16..-1, H-Position 0..+16 then -48..-1, V-Shift signed 5-bit.
// The picture is 512 dots in a line of 768, from 179 to 691 dots after the hsync pulse starts; the module reads its line at the
// slower rate from the pulse on, so a size step (1/32 of a dot) moves the picture's end to 691 * (32 + H-Size) / 32 dots, which
// must stay inside the line: +3 (756) is the most that fits (+4 cuts the last 9 columns at the next hsync)
localparam signed [8:0] CRT_HBIAS = -9'sd1;     // cancels the module's own one-dot delay of the picture
wire        [4:0] crt_hs_i = status[40:36];
wire signed [5:0] crt_hsz = (crt_hs_i <= 5'd3) ? $signed({1'b0, crt_hs_i}) : $signed({1'b0, crt_hs_i}) - 6'sd20;
wire        [6:0] crt_hp = status[47:41];
wire signed [8:0] crt_hpos = (crt_hp <= 7'd16) ? $signed({2'b00, crt_hp}) : $signed({2'b00, crt_hp}) - 9'sd65;
// the picture is read a line after it is written, so the sync is delayed one line to keep its place; a positive V-Shift moves
// the picture down, which is the sync coming earlier. Negative delays count from the frame length the module is built for, 288
wire signed [6:0] crt_vs_t = 7'sd1 - $signed({status[52], status[52], status[52:48]});
reg               crt_on = 1'b0;
reg signed  [4:0] crt_hsize;
reg signed  [8:0] crt_hoff;
reg signed  [5:0] crt_voff;
always @(posedge clk_sys) if (vq_ce) begin
	crt_on    <= status[35] & ~crt_sd & (vmode == 2'd0);    // the module is built for the board's 288 lines
	crt_hsize <= crt_hsz[4:0];
	crt_hoff  <= crt_hpos + CRT_HBIAS;
	crt_voff  <= crt_vs_t[5:0];
end

// the pixel read enable: one every (32 + H-Size) quarters of a clock (eight clocks a dot at 12 MHz), counted from the
// module's own line reference
wire       crt_hs_ref;
reg        crt_hs_ref_d;
wire [7:0] crt_period = 8'd32 + {{3{crt_hsize[4]}}, crt_hsize};
reg  [7:0] crt_acc;
wire       crt_tick = (crt_acc + 8'd4) >= crt_period;
always @(posedge clk_sys) begin
	crt_hs_ref_d <= crt_hs_ref;
	if      (crt_hs_ref & ~crt_hs_ref_d) crt_acc <= 8'd0;
	else if (crt_tick)                   crt_acc <= crt_acc + 8'd4 - crt_period;
	else                                 crt_acc <= crt_acc + 8'd4;
end
wire crt_rd_en = crt_on ? crt_tick : vq_ce;

wire [7:0] crt_r, crt_g, crt_b;
wire       crt_hs, crt_vs, crt_hb, crt_vb_unused;
// AW 11: a line buffer bank of 1,024 samples for the 768-dot line (the module's own 512 would let the line's blanking overwrite the
// picture's first 77 dots; modules/VENDOR.md)
crt_adjust #(.VTOTAL(288), .HTOTAL(768), .HPOS_MODE(1), .AW(11)) u_crt
(
	.clk(clk_sys), .pxl_cen(vq_ce), .pxl2_cen(crt_rd_en), .active(crt_on),
	.hsize(crt_hsize), .hoffset(crt_hoff), .voffset(crt_voff),
	.r_in(vq_rgb[23:16]), .g_in(vq_rgb[15:8]), .b_in(vq_rgb[7:0]),
	.hs_in(vq_hs), .vs_in(vq_vs), .hb_in(vq_hb), .vb_in(vq_vbn),
	.r_out(crt_r), .g_out(crt_g), .b_out(crt_b),
	.hs_out(crt_hs), .vs_out(crt_vs), .hb_out(crt_hb), .vb_out(crt_vb_unused),
	.hs_ref_out(crt_hs_ref)
);

wire        vga_de_i;
arcade_video #(.WIDTH(512), .DW(24)) arcade_video
(
	.*,
	.VGA_DE(vga_de_i),
	.clk_video(clk_sys),
	.ce_pix(crt_on ? crt_rd_en : vq_ce),
	.RGB_in(crt_on ? {crt_r, crt_g, crt_b} : vq_rgb),
	.HBlank(crt_on ? (crt_hb | crt_hs) : vq_hb),   // CRT Adjust: nothing of the picture inside the hsync pulse; off: the horizontal blank alone
	.VBlank(crt_on ? 1'b0 : vq_vb),               // CRT Adjust: the module's blank already includes the vertical one
	.HSync(crt_on ? crt_hs : vq_hs),
	.VSync(crt_on ? crt_vs : vq_vs),
	.fx(status[5:3])
);

// Scale: the framework's video_freak; its SCALE input counts 0 Normal, 1 V-Integer, 2 Narrower HV-Integer, 3 HV-Integer+, 4 HV-Integer
reg   [2:0] scale_sel;
always @* begin
	case (status[34:32])
		3'd1:    scale_sel = 3'd1;
		3'd2:    scale_sel = 3'd4;
		3'd3:    scale_sel = 3'd2;
		3'd4:    scale_sel = 3'd3;
		default: scale_sel = 3'd0;
	endcase
end
wire fs_int = (ar == 2'd1) && (scale_sel != 3'd0) && (HDMI_WIDTH != 12'd0) && (HDMI_HEIGHT != 12'd0);

video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(vga_de_i),
	.ARX(fs_int ? HDMI_WIDTH  : (ar == 2'd0) ? 12'd4 : {10'd0, ar - 2'd1}),
	.ARY(fs_int ? HDMI_HEIGHT : (ar == 2'd0) ? 12'd3 : 12'd0),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE(scale_sel)
);

///////////////////////   LEDs   ///////////////////////

// user LED: on while a load / reset holds the machine, then a blink every frame
reg led_frame = 1'b0;
always @(posedge clk_sys) if (frame_tick) led_frame <= ~led_frame;
assign LED_USER = mc_rst ? 1'b1 : led_frame;

endmodule
