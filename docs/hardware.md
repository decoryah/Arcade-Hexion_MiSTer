# Hexion: the hardware as the core implements it

Everything here is MAME 0.289's (`src/mame/konami/hexion.cpp`, `src/devices/machine/k053252.cpp`, `src/devices/sound/k051649.cpp`,
`okim6295.cpp`, `src/emu/emupal.cpp`, `src/emu/tilemap.cpp`) unless it says otherwise; where a value was measured in MAME with Lua, it
says so.

## The board (Konami GX122, 1992)

| | |
|---|---|
| CPU | Z80B at 6 MHz (24 MHz / 4) |
| CCU | K053252 at 12 MHz (24 MHz / 2): the raster and the interrupts |
| PMC | 052591, used only to fill the VRAM (MAME emulates its fills, not the chip) |
| Video | two 64 x 32 tilemaps of 8 x 8 tiles, 4 bits a pixel, 16 colours of 16; 512 KB of tile ROM; three 256 x 4 colour PROMs |
| Sound | K051649 (SCC) at 3 MHz (24 MHz / 8); MSM6295 at 1.056 MHz, pin 7 high (8 kHz) with a 256 KB ROM |
| The bootleg (Impeuropex) | the SCC's code is still there but the chip is not; a second MSM6295 at f5c0 (pin 7 low: 6.4 kHz) with its own ROM |

## Memory map

| address | read | write |
|---|---|---|
| 0000-7fff | program ROM (the first 32 KB) | |
| 8000-9fff | program ROM bank: 16 x 8 KB of the 128 KB, f480 bits 3:0 | |
| a000-bfff | work RAM | work RAM |
| c000-dffe | banked (below) | banked (below) |
| dfff | 0 | bank control |
| e800-e8ff | K051649 (the bootleg: 0) | K051649 |
| f000-f00f | K053252: its registers, 0e / 0f the line counter | K053252 |
| f200 | 0 | MSM6295 |
| f400 / f401 | DSW1 / DSW2 | |
| f402 / f403 | P1 / P2 | |
| f440 / f441 | DSW3 / SYSTEM | |
| f480 | 0 | bits 3:0 ROM bank, 6 start the PMC, 7 PMC-BK |
| f4c0 | 0 | bits 0 / 1 coin counters, 5 flip screen |
| f500 | 0 | the tile ROM window |
| f540 | 0 (the watchdog; MAME configures no timeout) | |
| f5c0 | 0 | the bootleg's second MSM6295 |

Anything else reads 0 (MAME's unmapped value for this machine).

c000-dffe (offset 0000-1ffe): a read gives the tile ROM at `((window & 0x7f) << 12) + offset` when the window (f500) is non-zero and the
offset is below 0x1000; else VRAM bank `rambank` when the bank control is 0; else the PMC's RAM (2 KB) when it is 2; else 0. A write
with the bank control at 3, at offset 0, of 0 or 1 selects `rambank`; with the bank control at 0 it writes the VRAM bank, at 2 the PMC
RAM, both only while PMC-BK is set.

Writing f480 with bit 6 set starts the PMC on its RAM's command (byte 0): 0 or 1 fills that VRAM bank (8 KB) with byte 1; anything
else clears 16 bytes of VRAM bank (byte 4 & 1) from offset (bytes 2-3). The game waits for SYSTEM bit 3 (the PMC busy) to read 0;
MAME's fill is instant and the bit always 0, as here (the core's fill takes 2,048 clocks of 96 MHz with the Z80 held, and the Z80 is
given the cycles back afterwards).

## The raster and the interrupts

The game programs the CCU with `02 FF 00 4D 00 73 00 00 01 1F 05 0E B7 7C` at 0.72 ms after reset. MAME's `k053252_device::res_change`
turns it into a 768 x 288 raster at 12 MHz (15.625 kHz, 54.25 Hz) with the visible area 512 x 256 at dot 0 / line 0; the front porch,
sync and back porch are 77 / 64 / 115 dots and 5 / 12 / 15 lines. Measured in MAME with Lua: the frame period is 18.432 ms and frame
N's vblank begins at (N + 1) x 18.432 ms, so at time 0 the raster is at the start of line 256.

The Z80's IRQ (IM 1) is raised at line 256 and cleared by writing CCU register 0x0e; the NMI is the CCU's INT-TIME, emulated by MAME
as a counter of the scanline timer's calls that raises it every INT-TIME (0x7c) calls, cleared by writing register 0x0f. The scanline
timer calls at dot 0 of every line, but its first call is at 1/540 s (32 lines of the 60 Hz, 288-line raster the screen has until the
game programs the CCU): measured in MAME with Lua, the Z80 fetches 0066 at 1,854.167 us, 9,730.333 us, 17,666.167 us, ... (124
lines apart, the first 2.3 us after the call).

## Video

Tile entry (VRAM, 4 bytes, rows of 64): code = byte 0 | (byte 1 & 0x3f) << 8; colour = byte 2 & 0x0f. Layer 1 (VRAM bank 1) is drawn
opaque, scrolled -4 / +4 (screen x shows the layer's x - 4, screen y its y + 4), layer 0 over it with pen 0 transparent. Flip screen
mirrors the whole picture (MAME's tilemap flip and its scroll rules come to exactly that).

A tile's row is 2 bytes in each half of the tile ROMs (16 bytes a tile): pixels 0 / 1 are the second half's byte 0 high / low nibble,
2 / 3 the first half's byte 0, 4 / 5 the second half's byte 1, 6 / 7 the first half's byte 1.

The colours: the PROMs' 4 bits through MAME's resistor weights 0x0e, 0x1f, 0x43, 0x8f (so 11 is 188, not 187).

## Sound

MAME mixes both chips into one speaker at 0.5 each: as 16 bits, 8 x the OKI's sum (each voice `trunc(signal * volume / 32)`, signal
-2048..2047) plus 16 x the SCC's (the sum of its five voices' `table byte * volume >> 4`); the bootleg 8 x each OKI.

## Controls

P1 / P2 (active low): 0 left, 1 right, 2 up, 3 down, 4 button 1, 5 button 2, 7 start. Measured in MAME: button 1 turns the falling
piece counter-clockwise, button 2 clockwise. SYSTEM: 0 / 1 coin 1 / 2, 2 service, 3 the PMC busy (0).

DIP switches (MAME's): DSW1 coin A (bits 3:0) and B (7:4), Konami's coinage table, 0 Free Play; DSW2 bits 6:4 difficulty (0 hardest,
7 easiest, default 4 Medium), bit 7 demo sounds (0 on); DSW3 bit 0 flip screen (0 on), bit 2 the service mode (0 on).

## The core's timing

One 96 MHz clock (the Rabbit core's PLL and SDRAM controller). The dot is one clock in 8 (12 MHz), the SCC's sample one in 32 (3 MHz),
the OKI's sample one in 12,000 (8 kHz; the bootleg's second, one in 15,000). The raster leaves reset at dot 0 of line 256, MAME's
position at time 0.

The Z80 (tv80) steps once per 16 clocks, in phase with the raster: its first instruction ends its first cycle at clock 16, as MAME's
Z80 starts at time 0 (tv80 spends a step after reset before its first fetch: the core gives it that step at the first clock). Where
the Z80 has to wait for something MAME does instantly (the tile ROM window, an SDRAM read; the PMC's VRAM fill, 2,048 clocks), its clock
enable is held and the cycles are owed: it then steps every 8 clocks until it has caught up, so its program stays on MAME's timeline.
An interrupt the CCU raises while the Z80 still owes cycles is held back by that many of its steps, so that it reaches the Z80 at the
point of its program where MAME's would see it (`sim/tb_top.sv +OWEDLOG` lists them). On the board's raster no interrupt needed it
in any run (the window reads wait for the video's tile fetch at the start of the game's line and are caught up long before the line's
call at dot 764); with the 263-line Video Timing the fetch drifts along the game's line: the test mode's 1,000 frames hold 122
interrupts back by 1 to 48 cycles, and without the hold some were taken a few instructions early (the stack bytes in work RAM
differed from MAME's at 5 of 51 dumps).

MAME takes an interrupt after the instruction during which (or at whose end) the line was raised. tv80 samples its interrupt inputs at
every step and decides at an instruction's last step on the sample of the step before, so a line raised during an instruction's last
cycle would be taken an instruction later. The core raises the lines 25 clocks (a cycle and a half) before MAME's time (the line's
call at the last clock of dot 764 of the line before; the first call at clock 177,766), which gives MAME's choice for any instruction:
checked against MAME's debugger trace instruction by instruction (`tools/cmp_trace.py`).

tv80's own NMI took 15 T-states (its M1 had the interrupt acknowledge's two wait states, its two writes 4 T-states each); a Z80's and
MAME's take 11: the vendored tv80 is changed (`modules/VENDOR.md`).

## The 263-line Video Timings (RetroTINK 4K)

A RetroTINK 4K sorts a MiSTer direct-video (DV1) signal into a class by its lines per frame, and judges a picture's width, as a CRT
does, by its time in the line. Measured on the owner's RT4K (firmware 1.87.3) and Sony PVM with test builds:

| raster | RT4K | PVM |
|---|---|---|
| the board's 288 lines, 15.625 kHz | "MiSTer Gen.": square pixels (stretched), and every ~13.4 s the picture collapses into vertical stripes for half a second while its input stats stay locked | locks |
| 263 lines of 70.1 us (14.27 kHz, the board's frame time) | "MiSTer 240p", steady | rolling lines, no lock |
| 263 lines of the board's 64 us | "MiSTer 240p", steady | locks, the top intact |
| 266, 270, 276, 282 lines of 64 us | "MiSTer Gen.", steady | locks |

(The owner's Seta 2 core had found 256 and 259 lines "MiSTer Gen." and 262 "MiSTer 240p".) With the board's 512-dot picture in 42.7
us of the line both 263-line rasters came out narrow on the RT4K. So the OSD's Video Timing has, besides the board's raster:

* **263 lines (RT4K 54Hz)**: the board's frame time exactly (1,769,472 clocks, 54.2535 Hz), so the picture keeps step with the game:
  263 lines of 6,728 clocks and the last of 6,736 (14.27 kHz; every hsync-to-hsync time the same but that one, the scheme the
  owner's Jackie Chan core found steady on the RT4K). Dots are 11 clocks apart (8.73 MHz) after a gap of 7 clocks at the line's start
  (15 on the last line, so the picture is always 997 clocks after the hsync starts): 611 dots a line, the picture's 512 filling
  58.7 us of the 70.1 us (84 %); 9 / 41 / 49 dots of front porch, sync and back porch (1.0 / 4.7 / 5.6 us); vertically 2 / 2 / 3
  lines. The framework's direct-video DE (`sys_top.v`: from the third line after the vsync to the third before the next) is then
  exactly the picture's 256 lines (a 3-line sync would cut line 255). Not for a CRT.
* **263 lines (CRT+RT4K)**: the board's line (768 dots of 8 clocks, 15.625 kHz, its hsync) on 263 lines (2 / 2 / 3): 59.41 Hz, free
  of the game's 54.25 Hz frame. One setting for both screens, at the cost of game frames shown in one or two pictures (about 5 a
  second repeat) and a picture change that can tear. Running the game at 59.41 Hz would remove both, but the game would play 9.5 %
  faster than the board; a frame buffer would remove the tearing only, with up to a frame more lag.

The game's own raster runs on unchanged: the interrupts, the CCU's line read-back and the frame tick come from the 288-line
counters, so the machine's timeline is the same in every setting. 263 lines (RT4K 54Hz) keeps a fixed phase to it: its line 0
begins with the game's line 272, 98,304 clocks (16 of the board's lines) after the game's line 256 (the IRQ) begins, set there at
every frame.

The phase was chosen from where the game writes VRAM (`sim/tb_top.sv +VWLOG`, 900 frames of the scripted attract mode, mode select
and play): all through the frame, with a burst 8 to 29 lines after the IRQ that rewrites the bottom rows. A write shows in a different
frame than on the board's raster when it falls between the two rasters' fetches of a line it changes; scored over the logged writes,
that is fewest with line 0 about 18 lines after the IRQ and climbs steeply after it, where line 255 is fetched after the burst
begins and shows it a frame early. 16 lines leaves two lines of margin (line 255 is fetched 6 lines after the IRQ).
