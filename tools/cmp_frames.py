#!/usr/bin/env python3
"""cmp_frames.py <mame dir> <bench prefix> [frames a,b,c]: the system bench's pictures (<prefix>.f<n>.ppm) against MAME's snapshots of the
same frames (<mame dir>/snap_<n>.png, tools/lua/dump.lua): the differing pixels of each, by default for every picture the bench wrote
that MAME has."""
import sys, os, re, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cmp_frame import load


def main():
    mdir, pre = sys.argv[1], sys.argv[2]
    if len(sys.argv) > 3:
        fr = [int(x) for x in sys.argv[3].split(',')]
    else:
        fr = sorted(int(re.search(r'\.f(\d+)\.ppm$', p).group(1)) for p in glob.glob(pre + '.f*.ppm'))
        fr = [f for f in fr if os.path.exists(os.path.join(mdir, f'snap_{f}.png'))]
    same = 0
    for f in fr:
        _, _, a = load(os.path.join(mdir, f'snap_{f}.png'))
        _, _, b = load(f'{pre}.f{f}.ppm')
        n = sum(1 for i in range(0, len(a), 3) if a[i:i + 3] != b[i:i + 3])
        print(f'{f}: {n} pixels differ')
        same += (n == 0)
    print(f'{same} of {len(fr)} pictures identical')


if __name__ == '__main__':
    main()
