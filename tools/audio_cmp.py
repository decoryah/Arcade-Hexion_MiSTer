#!/usr/bin/env python3
"""audio_cmp.py <bench.wav> <mame.wav> [--from F] [--to F]: the core's sound (the system bench's AUDIO=1 output: 46,875 Hz, 16-bit mono,
from the machine's reset) against MAME's -wavwrite recording of the same scripted run (after the owner's Rabbit core's tool).

Per frame of the game (768 x 288 dots at 12 MHz: 18.432 ms) the RMS of both is computed (MAME's stereo mixed to mono); the two envelopes
are aligned by the lag (in frames, -30 .. +30) that correlates best, and their ratio and correlation reported over frames F .. T."""
import sys, struct, math, argparse

FRAME = 768 * 288 / 12e6

ap = argparse.ArgumentParser()
ap.add_argument('ours'); ap.add_argument('wav')
ap.add_argument('--from', dest='f0', type=int, default=60); ap.add_argument('--to', dest='f1', type=int, default=0)
a = ap.parse_args()


def read_wav(p):
    d = open(p, 'rb').read()
    i = 12
    rate = ch = None
    while i < len(d):
        cid, ln = d[i:i + 4], struct.unpack('<I', d[i + 4:i + 8])[0]
        if cid == b'fmt ':
            _, ch, rate = struct.unpack('<HHI', d[i + 8:i + 16])
        elif cid == b'data':
            s = struct.unpack('<%dh' % (len(d[i + 8:i + 8 + ln]) // 2), d[i + 8:i + 8 + ln])
            if ch == 2:
                s = [(s[k] + s[k + 1]) / 2 for k in range(0, len(s) - 1, 2)]
            return rate, s
        i += 8 + ln
    sys.exit('no data chunk')


def env(s, rate):
    per = rate * FRAME
    out, f = [], 0
    while int((f + 1) * per) <= len(s):
        s0, s1 = int(f * per), int((f + 1) * per)
        out.append(math.sqrt(sum(v * v for v in s[s0:s1]) / (s1 - s0)))
        f += 1
    return out


def corr(x, y):
    n = len(x)
    if n == 0: return 0
    mx, my = sum(x) / n, sum(y) / n
    sxy = sum((p - mx) * (q - my) for p, q in zip(x, y))
    sxx = sum((p - mx) ** 2 for p in x); syy = sum((q - my) ** 2 for q in y)
    return sxy / math.sqrt(sxx * syy) if sxx > 0 and syy > 0 else 0


ro, so = read_wav(a.ours)
rm, sm = read_wav(a.wav)
o, m = env(so, ro), env(sm, rm)
f1 = a.f1 or min(len(o), len(m))
best = None
for lag in range(-30, 31):
    xs = [o[f] for f in range(a.f0, f1) if 0 <= f + lag < len(m) and f < len(o)]
    ys = [m[f + lag] for f in range(a.f0, f1) if 0 <= f + lag < len(m) and f < len(o)]
    c = corr(xs, ys)
    if best is None or c > best[0]: best = (c, lag, xs, ys)
c, lag, xs, ys = best
ratio = (sum(xs) / sum(ys)) if sum(ys) > 0 else float('nan')
print(f'frames {a.f0}-{f1}: best lag {lag:+d} frames (MAME later when +), envelope correlation {c:.4f}, '
      f'level ours/MAME {ratio:.3f}, mean RMS ours {sum(xs)/max(1,len(xs)):.0f} MAME {sum(ys)/max(1,len(ys)):.0f}')
