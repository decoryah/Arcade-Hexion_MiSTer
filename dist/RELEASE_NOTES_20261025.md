## Hexion for MiSTer - 20261025

Konami's **Hexion** (1992, GX122), the falling-hexagon puzzle game: a Z80B, the K053252, two tilemaps, the K051649 (SCC) and an
MSM6295. Two MRAs: Hexion (Japan ver JAB) and the Impeuropex bootleg, Hexion (Asia ver AAA, bootleg), which has a second MSM6295
instead of the SCC.

**First release. Tested on a real MiSTer by the repository owner, with a RetroTINK 4K and a Sony PVM: the three Video Timing
settings work as intended.** It was also checked in simulation against MAME 0.289 (below).

### Install

1. Unzip `Hexion_MiSTer_20261025.zip` over the root of the SD card. It adds `Hexion (Japan ver JAB).mra` to `_Arcade/`,
   `Hexion (Asia ver AAA, bootleg).mra` to `_Arcade/_alternatives/_Hexion/` and `_Arcade/cores/hexion_20261025.rbf`. Delete any
   older `hexion_*.rbf` from `_Arcade/cores/`.
2. Put your own MAME 0.289 romset `hexion.zip` (the merged set holds both versions) in `games/mame/`. No ROMs are included.
3. Start the game from the Arcade menu. With a recent Main_MiSTer the ROM image is copied to the DDR3 in one go (the MRAs'
   `address=` attribute); with an older one it is streamed, with the same RBF and MRAs.

The OSD's version line reads `v261025`.

### Video Timing: pick the one for your display

| Your display | Video Timing | The signal |
|---|---|---|
| CRT (PVM / BVM / arcade monitor / TV) | **288 lines (Native)**, the default | the board's own: 15.625 kHz, 54.25 Hz, 768 x 288 with the 512 x 256 picture; CRT Adjust |
| HDMI through MiSTer's scaler | **288 lines (Native)** | the scaler takes any line count; with `vsync_adjust` it outputs the game's 54.25 Hz |
| RetroTINK 4K in direct video (DV1) | **263 lines (RT4K 54Hz)** | the board's exact frame time (54.25 Hz) on 263 lines, in step with the game: no torn or repeated frames; the RT4K's "MiSTer 240p" class with a 4:3 picture. 14.27 kHz: not for a CRT |
| A CRT and the RT4K with one setting | **263 lines (CRT+RT4K)** | 15.625 kHz on 263 lines, 59.41 Hz; the game keeps its 54.25 Hz underneath, so about 5 pictures a second repeat a game frame and a picture change can tear; a slightly narrow picture |

The game runs at the board's speed in every setting. The RT4K takes the board's 288 lines as "MiSTer Gen.": a stretched picture
that drops out every 13 s or so, hence the 263-line settings.

### Controls

A joystick and two buttons, **Rotate Left** and **Rotate Right** (MAME's buttons 1 and 2: they turn the falling piece counter-
clockwise and clockwise, measured in MAME), Start and Coin, for two players. Keyboard: 1 / 2 start, 5 / 6 coin, 9 service, F2 the
service mode (while held).

### OSD

Aspect ratio, Scale (Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+), Scandoubler Fx (None, HQ2x, CRT 25 / 50 /
75 %), Video Timing, CRT Adjust (rmonic79's module, with 288 lines (Native): H-Size, H-Position, V-Shift for a 15 kHz analog
output), the DIP switches (MAME's: Coin A / B, Difficulty, Demo Sounds, Flip Screen, Service Mode), Volume, Reset.

### Checked

- **On a real MiSTer:** by the repository owner, with a RetroTINK 4K and a Sony PVM: the game and the three Video Timing settings
  (288 lines (Native) on the PVM, 263 lines (RT4K 54Hz) as "MiSTer 240p" on the RT4K, 263 lines (CRT+RT4K) on both).
- **Against MAME 0.289, in simulation** (Verilator, the whole machine with the game's program and the ROM image loaded through the
  core's loader):
  - the Z80 starts every traced instruction on MAME's cycle (the power-on frame, frames 60-70 and 100-101);
  - the work RAM and both VRAM banks are byte for byte MAME's at all 121 dumps of 1,200 frames of scripted play, at all 121 of the
    bootleg's and at all 51 of the test mode, in the native and the 263-line timings;
  - the pictures (native timing) are MAME's snapshots pixel for pixel, but for the animated arrows the game redraws while the beam is below them,
    which the core shows a frame later (as a board drawing line by line does), MAME at once;
  - the sound's loudness follows MAME's recording (correlation 0.998).
- **The MiSTer top level, in simulation:** the fast and the streamed load (the SDRAM byte-identical to the expected layout), every
  frame of every Video Timing its exact length, the framework's direct-video picture area holding every picture line, HQ2x and
  `forced_scandoubler` (every frame whole), CRT Adjust.
- **Quartus 17.0.2:** timing met on every clock.

### Known differences from MAME

- The tilemaps are read as the beam runs, as on the board; MAME draws the whole frame at the start of the vertical blank, so a
  picture change the game makes mid-frame (the arrows) shows a frame later here.
- The sound is resampled differently (the SCC averaged to 46.875 kHz); the mix levels are MAME's.
