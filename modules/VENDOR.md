# Vendored modules

Third-party HDL copied into the tree (no submodules, so the build is self-contained and reproducible). Each keeps its own licence
alongside.

| module | upstream | licence |
|---|---|---|
| cpu-tv80 | https://github.com/hoglet67/tv80 (Guy Hutchison's tv80), with the `tv80s_cen.v` clock-enable wrapper from plasticbugs/punchout; copied from the owner's Mystic Warriors core | MIT |
| crt-adjust | https://github.com/rmonic79/MiSTer-CRT-Adjust @ c682de9f4acc61d8f4c7779efb48149d3baa3a8e (upstream's `rtl/crt_adjust.sv`; one local fix, below), by rmonic79 (Umberto Parisi) with Andrea Bogazzi (asturur); copied from the owner's Rabbit core | GPL-3.0 or later |

To update one: re-copy from upstream at the new commit and record it here.

tv80 is built with its `TV80_REFRESH` option (files.qip, the benches' scripts): the R register, which Hexion reads for its random
numbers (`LD A,R`) and MAME counts as a Z80 does (every opcode fetch, every interrupt taken); without it tv80 reads R as 0.

Local change to `cpu-tv80` (`tv80_core.v`, `tv80_reg.v`, marked "Hexion core"): the registers' power-on values are MAME 0.289's
(`z80_device::device_start`: AF = 0 with the zero flag set, SP = 0, IX = IY = FFFF, the alternate set 0) instead of tv80's (A, F, A',
F' = FF, SP = FFFF, the register file 0). Hexion never sets IY and AF', but its interrupt handlers push them, so with tv80's values
the stack's bytes differ from MAME's; nothing else depends on them (a real Z80's are undefined).

Local change to `cpu-tv80` (`tv80_core.v` `Auto_Wait`, `tv80_mcode.v` the NMI's M-cycles 2 and 3, marked "Hexion core"): the NMI's
acknowledge takes 11 T-states (an M1 of 5 and two writes of 3), as a Z80's and MAME's do; tv80 gave its M1 the interrupt acknowledge's
two wait states and its writes 4 T-states each, 15 in all. Hexion's NMI comes 2.3 times a frame, so the 4 cycles moved the game off
MAME's timeline (measured: the core's and MAME's instruction traces with their cycle counts, sim/tb_top.sv +ITRACE and MAME's debugger
`trace` with `totalcycles`).

Local change to `crt-adjust/crt_adjust.sv` (marked "Hexion core"): the line buffer's size `AW` is a parameter (upstream a localparam,
10: 512 samples a ping-pong bank). The module writes every dot of the line into its bank, and Hexion's line is 768 dots: with 512 the
line's blanking (dots 691..767 after the hsync pulse) wrapped onto the picture's first 77 dots, which then showed black. Hexion.sv sets
AW 11 (1,024 a bank); the default keeps upstream's behaviour.

Local change to `crt-adjust/crt_adjust.sv` (one line, `hoff_s`): the conditional mixes `$signed(hoffset)` with an unsigned
replication, so by the Verilog rules (and in Verilator) the result is unsigned and a negative H-Position is zero-extended
(-1 becomes 511), which moves the picture window out of the line and blanks the picture. The line sign-extends `hoffset`
explicitly, which is what the module is meant to do and gives the same result in every tool. Nothing else differs from
upstream.
