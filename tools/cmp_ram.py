#!/usr/bin/env python3
"""cmp_ram.py <mame dir> <core dir> [frames: a,b,c | a-b]: compares the state dumps (ram_<f>.bin: work RAM, VRAM bank 0, VRAM bank 1)
of tools/lua/dump.lua (MAME) and sim/tb_top.sv (the core), frame by frame: the differing bytes per region, the first few listed."""
import sys, os, re

REG = [('wram', 0xa000, 0, 0x2000), ('vram0', 0, 0x2000, 0x2000), ('vram1', 0, 0x4000, 0x2000)]


def frames_of(d):
    return sorted(int(m.group(1)) for f in os.listdir(d) for m in [re.match(r'ram_(\d+)\.bin$', f)] if m)


def main():
    a, b = sys.argv[1], sys.argv[2]
    if len(sys.argv) > 3:
        s = sys.argv[3]
        if '-' in s:
            lo, hi = map(int, s.split('-'))
            fr = [f for f in frames_of(a) if lo <= f <= hi]
        else:
            fr = [int(x) for x in s.split(',')]
    else:
        fr = [f for f in frames_of(a) if os.path.exists(os.path.join(b, f'ram_{f}.bin'))]
    same = 0
    for f in fr:
        pa, pb = os.path.join(a, f'ram_{f}.bin'), os.path.join(b, f'ram_{f}.bin')
        if not (os.path.exists(pa) and os.path.exists(pb)):
            print(f'{f}: missing'); continue
        da, db = open(pa, 'rb').read(), open(pb, 'rb').read()
        out = []
        for name, base, off, n in REG:
            diff = [i for i in range(n) if da[off + i] != db[off + i]]
            if diff:
                ex = ' '.join(f'{base + i:04x}:{da[off + i]:02x}/{db[off + i]:02x}' for i in diff[:6])
                out.append(f'{name} {len(diff)} ({ex})')
        if out:
            print(f'{f}: ' + '; '.join(out))
        else:
            same += 1
    print(f'{same} of {len(fr)} frames identical')


if __name__ == '__main__':
    main()
