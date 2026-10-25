#!/bin/sh
# Verilator lint of the machine, the loader and the SDRAM controller: sim/lint.sh [max lines]
cd "$(dirname "$0")"
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM -Wno-SYNCASYNCNET \
    waivers.vlt -I../rtl --top-module hexion_core \
    ../rtl/hexion_core.sv ../rtl/hexion_ram.sv ../rtl/hexion_video.sv ../rtl/hexion_scc.sv ../rtl/hexion_oki.sv \
    +define+TV80_REFRESH ../modules/cpu-tv80/tv80s_cen.v ../modules/cpu-tv80/tv80_core.v ../modules/cpu-tv80/tv80_alu.v ../modules/cpu-tv80/tv80_mcode.v \
    ../modules/cpu-tv80/tv80_reg.v 2>&1 | grep -E "^%(Error|Warning)" | head -${1:-80}
echo "--- loader, sdram, standby, fastload"
for m in hexion_loader hexion_sdram hexion_standby hexion_fastload; do
    verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME --top-module $m ../rtl/$m.sv 2>&1 | grep -E "^%(Error|Warning)" | head -${1:-40}
done
