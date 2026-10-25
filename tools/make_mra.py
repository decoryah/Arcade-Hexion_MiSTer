#!/usr/bin/env python3
"""Writes the Hexion MRAs (mra/*.mra) from MAME 0.289's ROM lists and input ports (src/mame/konami/hexion.cpp).

    python3 tools/make_mra.py [<hexion.zip>]

With the romset given, every MRA is assembled by tools/mra_build.py and compared with the image tools/hexion_rom.py builds by MAME's
loading rules (the image the simulations run); they must be identical. The layout is rtl/hexion_loader.sv's.
"""
import os, sys, subprocess, tempfile, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)

# MAME's KONAMI_COINAGE_LOC, by the value of the four switches (0..15); 0 is Free Play for both
COIN = 'Free Play,4C/3C,4C/1C,3C/4C,3C/2C,3C/1C,2C/5C,2C/3C,2C/1C,1C/7C,1C/6C,1C/5C,1C/4C,1C/3C,1C/2C,1C/1C'

SWITCHES = f'''    <!--
      DIP switches (ioctl index 254): byte 0 is DSW1 (f400), byte 1 DSW2 (f401), byte 2 DSW3 (f440), bit for bit as MAME reads them;
      a 1 is "off". MAME's defaults: FF, 4F, FF.
    -->
    <switches default="FF,4F,FF" base="16">
        <dip bits="0,3" name="Coin A" ids="{COIN}"/>
        <dip bits="4,7" name="Coin B" ids="{COIN}"/>
        <dip bits="12,14" name="Difficulty" ids="8 (Hardest),7 (Very Hard),6 (Hard),5 (Medium Hard),4 (Medium),3 (Easy),2 (Very Easy),1 (Easiest)"/>
        <dip bits="15" name="Demo Sounds" ids="On,Off"/>
        <dip bits="16" name="Flip Screen" ids="On,Off"/>
        <dip bits="18" name="Service Mode" ids="On,Off"/>
    </switches>'''

TEMPLATE = '''<misterromdescription>
    <name>{name}</name>
    <setname>{setname}</setname>
    <mameversion>0289</mameversion>
    <year>1992</year>
    <manufacturer>{manufacturer}</manufacturer>
    <players>2</players>
    <joystick>8</joystick>
    <rotation>horizontal</rotation>
    <rbf>hexion</rbf>
    <platform>Hexion</platform>

    <!--
      The image of the Hexion core (rtl/hexion_loader.sv, tools/hexion_rom.py), the same layout for both sets:
        0x000000  0x20000  maincpu  the Z80 program
        0x020000  0x80000  tiles    the two tile ROMs (MAME's "tiles": the first half, then the second)
        0x0A0000  0x40000  oki      the MSM6295's samples
        0x0E0000  0x00300  proms    red, green, blue
        0x0E0300  0x00001  board    0 the Konami board (K051649), 1 the bootleg (a second MSM6295)
        0x100000  0x40000  oki2     the bootleg's second MSM6295 (the bootleg only)
      Expects the MAME 0.289 merged romset or the split sets: parts are found by name and CRC.
      address= is the fast load: a recent Main_MiSTer copies the image into the DDR3 at that byte and the core reads it from there
      (rtl/hexion_fastload.sv); an older one streams it.
    -->

{switches}

    <buttons names="Rotate Left,Rotate Right,Start,Coin" default="A,B,Start,Select"/>

    <rom index="0" zip="{zips}" md5="None" address="0x32000000">
{parts}
    </rom>
</misterromdescription>
'''

SETS = [
    dict(setname='hexion', name='Hexion (Japan ver JAB)', manufacturer='Konami', zips='hexion.zip',
         parts=[('maincpu', [('122__j_a__b01.16f', 'eabc6dd1')]),
                ('tiles', [('122a07.1h', '22ae55e3'), ('122a06.1g', '438f4388')]),
                ('oki', [('122a05.2f', 'bcc831bf')]),
                ('proms: red, green, blue', [('122a04.10b', '506eb8c6'), ('122a03.11b', '590c4f64'), ('122a02.13b', '5734305c')]),
                ('board: Konami', ['00'])]),
    dict(setname='hexionb', name='Hexion (Asia ver AAA, bootleg)', manufacturer='bootleg (Impeuropex Corp.)', zips='hexionb.zip|hexion.zip',
         parts=[('maincpu', [('hexionb.u2', '93edc5d4')]),
                ('tiles', [('hexionb.u30', '22ae55e3'), ('hexionb.u29', '438f4388')]),
                ('oki', [('hexionb.u16', 'bcc831bf')]),
                ('proms: red, green, blue', [('82s129.u36', '506eb8c6'), ('82s129.u37', '590c4f64'), ('82s129.u38', '5734305c')]),
                ('board: the bootleg', ['01']),
                ('to 0x100000', [('repeat', 0x100000 - 0x0E0301)]),
                ('oki2', [('hexionb.u18', 'c179d315')])]),
]


def parts_text(parts):
    out = []
    for label, items in parts:
        out.append(f'        <!-- {label} -->')
        for it in items:
            if isinstance(it, str):
                out.append(f'        <part>{it}</part>')
            elif it[0] == 'repeat':
                out.append(f'        <part repeat="0x{it[1]:X}">00</part>')
            else:
                out.append(f'        <part name="{it[0]}" crc="{it[1]}"/>')
    return '\n'.join(out)


def mra_text(s):
    return TEMPLATE.format(name=s['name'], setname=s['setname'], manufacturer=s['manufacturer'], zips=s['zips'],
                           switches=SWITCHES, parts=parts_text(s['parts']))


def path_of(s):
    if s['setname'] == 'hexion':
        return os.path.join(ROOT, 'mra', f"{s['name']}.mra")
    return os.path.join(ROOT, 'mra', '_alternatives', '_Hexion', f"{s['name']}.mra")


def main():
    for s in SETS:
        p = path_of(s)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'w', newline='\n').write(mra_text(s))
        print('wrote', os.path.relpath(p, ROOT))
    if len(sys.argv) > 1:
        import hexion_rom
        z = sys.argv[1]
        for s in SETS:
            with tempfile.TemporaryDirectory() as td:
                out = os.path.join(td, 'x.rom')
                r = subprocess.run([sys.executable, os.path.join(HERE, 'mra_build.py'), path_of(s), z, out], capture_output=True, text=True)
                if r.returncode != 0:
                    sys.exit(f"{s['setname']}: mra_build failed: {r.stdout}{r.stderr}")
                a = open(out, 'rb').read()
            b = bytes(hexion_rom.build(z, s['setname']))
            ok = (a == b)
            print(f"{s['setname']}: MRA image {len(a):#x} bytes, md5 {hashlib.md5(a).hexdigest()}: "
                  + ('identical to hexion_rom.py' if ok else 'DIFFERS from hexion_rom.py'))
            if not ok:
                sys.exit(f'{sum(1 for i in range(min(len(a), len(b))) if a[i] != b[i])} bytes differ, lengths {len(a)} / {len(b)}')


if __name__ == '__main__':
    main()
