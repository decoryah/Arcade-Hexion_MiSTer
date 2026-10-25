#!/usr/bin/env python3
"""The Hexion core's ROM image by MAME 0.289's loading rules (src/mame/konami/hexion.cpp), independent of the MRAs: the image the
simulations run, and what tools/make_mra.py checks every MRA's image against.

    python3 tools/hexion_rom.py <hexion.zip> <hexion|hexionb> <out.rom>

The romset is MAME 0.289's merged hexion.zip (the bootleg's own files in hexionb/) or the split sets; files are found by CRC. The
layout is rtl/hexion_loader.sv's:
    0x000000  maincpu  0x20000   the program
    0x020000  tiles    0x80000   122a07.1h, 122a06.1g
    0x0A0000  oki      0x40000   122a05.2f
    0x0E0000  proms    0x300     122a04.10b, 122a03.11b, 122a02.13b
    0x0E0300  board    1         0 the Konami board, 1 the bootleg
    0x100000  oki2     0x40000   hexionb.u18 (the bootleg; the Konami set's image ends at the board byte)
"""
import sys, zipfile, zlib, os

# (region, offset in the image, size, [(name, crc)])
SETS = {
    'hexion': [
        ('maincpu', 0x000000, 0x20000, [('122__j_a__b01.16f', 0xeabc6dd1)]),
        ('tiles',   0x020000, 0x80000, [('122a07.1h', 0x22ae55e3), ('122a06.1g', 0x438f4388)]),
        ('oki',     0x0A0000, 0x40000, [('122a05.2f', 0xbcc831bf)]),
        ('proms',   0x0E0000, 0x00300, [('122a04.10b', 0x506eb8c6), ('122a03.11b', 0x590c4f64), ('122a02.13b', 0x5734305c)]),
    ],
    'hexionb': [
        ('maincpu', 0x000000, 0x20000, [('hexionb.u2', 0x93edc5d4)]),
        ('tiles',   0x020000, 0x80000, [('hexionb.u30', 0x22ae55e3), ('hexionb.u29', 0x438f4388)]),
        ('oki',     0x0A0000, 0x40000, [('hexionb.u16', 0xbcc831bf)]),
        ('proms',   0x0E0000, 0x00300, [('82s129.u36', 0x506eb8c6), ('82s129.u37', 0x590c4f64), ('82s129.u38', 0x5734305c)]),
        ('oki2',    0x100000, 0x40000, [('hexionb.u18', 0xc179d315)]),
    ],
}
BOARD = 0x0E0300


def files(path):
    """Every file of a zip (or of several, 'a.zip|b.zip'), by CRC."""
    out = {}
    for one in path.split('|'):
        with zipfile.ZipFile(one) as zf:
            for info in zf.infolist():
                if not info.is_dir():
                    d = zf.read(info)
                    out.setdefault(zlib.crc32(d) & 0xffffffff, d)
    return out


def build(zpath, setname):
    by_crc = files(zpath)
    regions = SETS[setname]
    end = BOARD + 1 if setname == 'hexion' else 0x140000
    img = bytearray(end)
    for region, off, size, roms in regions:
        data = b''
        for name, crc in roms:
            if crc not in by_crc:
                sys.exit(f'{setname}: {name} (crc {crc:08x}) is missing from {zpath}')
            data += by_crc[crc]
        if len(data) != size:
            sys.exit(f'{setname}: region {region} is {len(data):#x} bytes, expected {size:#x}')
        img[off:off + size] = data
    img[BOARD] = 0 if setname == 'hexion' else 1
    return img


def main():
    if len(sys.argv) != 4 or sys.argv[2] not in SETS:
        sys.exit(__doc__)
    img = build(sys.argv[1], sys.argv[2])
    with open(sys.argv[3], 'wb') as f:
        f.write(img)
    print(f'wrote {sys.argv[3]}: {len(img):#x} bytes')


if __name__ == '__main__':
    main()
