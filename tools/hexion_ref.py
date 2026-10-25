#!/usr/bin/env python3
"""The Hexion picture by MAME 0.289's rules (hexion.cpp's tilemaps and gfx layout, the RGB_444 PROMs, tilemap.cpp's scroll and flip),
from a state dump: a check of how the core reads MAME, independent of the RTL.

    python3 tools/hexion_ref.py <hexion.rom> <ram_<f>.bin> <out.png> [flip]

The image is tools/hexion_rom.py's (its tiles and PROMs regions); the dump is tools/lua/dump.lua's or sim/tb_top.sv's (work RAM,
VRAM bank 0, VRAM bank 1).
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio

TILES, PROMS = 0x020000, 0x0E0000


def dac(v):
    """MAME's palette_init_rgb_444_proms: the PROM's four bits through the weights 0x0e, 0x1f, 0x43, 0x8f"""
    return 0x0e * (v & 1) + 0x1f * ((v >> 1) & 1) + 0x43 * ((v >> 2) & 1) + 0x8f * ((v >> 3) & 1)


def palette(img):
    return [(dac(img[PROMS + i]), dac(img[PROMS + 0x100 + i]), dac(img[PROMS + 0x200 + i])) for i in range(256)]


def tile_row(img, code, row):
    """the 8 pens of a tile's row: MAME's charlayout (planes 0-3 a nibble, x from the second half's byte 0 high, low, the first
    half's byte 0 high, low, then the same for byte 1)"""
    a = TILES + code * 16 + row * 2
    b = a + 0x40000
    A0, A1, B0, B1 = img[a], img[a + 1], img[b], img[b + 1]
    return [B0 >> 4, B0 & 15, A0 >> 4, A0 & 15, B1 >> 4, B1 & 15, A1 >> 4, A1 & 15]


def layer(img, vram):
    """the 512 x 256 tilemap as (colour << 4 | pen)"""
    out = [[0] * 512 for _ in range(256)]
    for ty in range(32):
        for tx in range(64):
            e = (ty * 64 + tx) * 4
            code = vram[e] | ((vram[e + 1] & 0x3f) << 8)
            col = vram[e + 2] & 15
            for r in range(8):
                pens = tile_row(img, code, r)
                row = out[ty * 8 + r]
                for x in range(8):
                    row[tx * 8 + x] = (col << 4) | pens[x]
    return out


def render(img, dump, flip=False):
    pal = palette(img)
    l0 = layer(img, dump[0x2000:0x4000])
    l1 = layer(img, dump[0x4000:0x6000])
    px = bytearray(512 * 256 * 3)
    for y in range(256):
        for x in range(512):
            # flip: the screen is the unflipped picture mirrored (tilemap.cpp's effective_rowscroll / colscroll with the scroll of
            # layer 1, set_scrollx(-4) / set_scrolly(4), turn into the same mirror)
            ux, uy = (511 - x, 255 - y) if flip else (x, y)
            c = l0[uy][ux]
            if c & 15 == 0:
                c = l1[(uy + 4) & 255][(ux - 4) & 511]
            o = (y * 512 + x) * 3
            px[o:o + 3] = bytes(pal[c])
    return px


def main():
    img = open(sys.argv[1], 'rb').read()
    dump = open(sys.argv[2], 'rb').read()
    flip = len(sys.argv) > 4 and sys.argv[4] == 'flip'
    pngio.write(sys.argv[3], 512, 256, render(img, dump, flip))


if __name__ == '__main__':
    main()
