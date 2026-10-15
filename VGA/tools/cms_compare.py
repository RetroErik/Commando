"""Compare two CMS recordings (tolerates DOSBox WAVs whose header was never finalised).
python cms_compare.py REF.wav MINE.wav  -> aligns both at the first audible sample and prints pitch-track agreement"""
import sys, struct, math

def load(path):
    raw = open(path, 'rb').read()
    data = raw[44:]
    n = len(data) // 4
    vals = struct.unpack('<%dh' % (n * 2), data[:n * 4])
    return [(vals[2 * i] + vals[2 * i + 1]) / 2.0 for i in range(n)]

def onset(m, thr=300):
    for i in range(0, len(m) - 441, 441):
        seg = m[i:i + 441]
        if math.sqrt(sum(s * s for s in seg) / len(seg)) > thr:
            return i
    return 0

def peak(seg, fs):
    mean = sum(seg) / len(seg)
    seg = [s - mean for s in seg]
    best, bf = 0, 0
    for f in range(60, 1800, 10):
        a = sum(seg[i] * math.cos(2 * math.pi * f * i / fs) for i in range(0, len(seg), 2))
        b = sum(seg[i] * math.sin(2 * math.pi * f * i / fs) for i in range(0, len(seg), 2))
        p = a * a + b * b
        if p > best:
            best, bf = p, f
    return bf

def track(m, start, win_ms, count):
    step = 44100 * win_ms // 1000
    out = []
    for k in range(count):
        seg = m[start + k * step: start + k * step + step: 4]
        if len(seg) < 50: break
        rms = math.sqrt(sum(s * s for s in seg) / len(seg))
        out.append((int(rms), peak(seg, 44100 / 4)))
    return out

a, b = load(sys.argv[1]), load(sys.argv[2])
oa, ob = onset(a), onset(b)
print('onset ref %.2fs  mine %.2fs   lengths %.1fs / %.1fs' % (oa / 44100, ob / 44100, len(a) / 44100, len(b) / 44100))
cnt = int(sys.argv[3]) if len(sys.argv) > 3 else 40
ta, tb = track(a, oa, 200, cnt), track(b, ob, 200, cnt)
same = 0
for i, ((ra, fa), (rb, fb)) in enumerate(zip(ta, tb)):
    ok = abs(fa - fb) <= max(20, fa * 0.06)
    same += ok
    print('%5.1fs  ref rms %5d peak %4d Hz | mine rms %5d peak %4d Hz  %s' % (i * 0.2, ra, fa, rb, fb, '' if ok else '<-- differs'))
print('windows with matching dominant pitch: %d / %d' % (same, min(len(ta), len(tb))))
