#!/bin/sh
# The whole-machine bench: hexion_core behind hexion_sdram and a behavioural SDRAM, the image downloaded through hexion_loader.
#   sim/run_sys.sh <hexion.rom> <frames> <out prefix> [+plusargs: +DSW=.. +DUMPDIR=.. etc., sim/tb_top.sv]
# (tools/hexion_rom.py <hexion.zip> hexion x.rom makes the image.)
# Environment: see sim/tb_hexion.cpp (SNAPEVERY, SNAPFRAMES, SCHED, AUDIO, TRACE); REBUILD=1 rebuilds the model; THREADS=n.
set -e
cd "$(dirname "$0")"
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
IMG="$1"
[ -f "$IMG" ] && [ -n "$2" ] && [ -n "$3" ] || { echo "usage: $0 <hexion.rom> <frames> <prefix>" >&2; exit 2; }
OBJ=${OBJ:-obj_sys}
if [ ! -x $OBJ/Vtb_top ] || [ -n "$REBUILD" ]; then
verilator --cc --exe --build -j ${JOBS:-16} -O3 ${THREADS:+--threads $THREADS} -CFLAGS "-O2 -march=native" -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME \
    -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-IMPLICIT -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE \
    -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSINIT -Wno-SYNCASYNCNET -Wno-BLKSEQ \
    waivers.vlt $VFLAGS -I../rtl --top-module tb_top --prefix Vtb_top -Mdir $OBJ \
    ../rtl/hexion_core.sv ../rtl/hexion_ram.sv ../rtl/hexion_video.sv ../rtl/hexion_scc.sv ../rtl/hexion_oki.sv \
    ../rtl/hexion_sdram.sv ../rtl/hexion_loader.sv \
    +define+TV80_REFRESH ../modules/cpu-tv80/tv80s_cen.v ../modules/cpu-tv80/tv80_core.v ../modules/cpu-tv80/tv80_alu.v ../modules/cpu-tv80/tv80_mcode.v \
    ../modules/cpu-tv80/tv80_reg.v sdram_model.sv tb_top.sv tb_hexion.cpp > $OBJ.log 2>&1 || { tail -30 $OBJ.log; exit 1; }
fi
mkdir -p "$(dirname "$3")"
PRE="$3"; FR="$2"; shift 3
./$OBJ/Vtb_top +IMAGE="$IMG" "$@" "$FR" "$PRE"
