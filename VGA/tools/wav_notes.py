"""Dominant-pitch tracker (autocorrelation-free: short-window FFT-less zero-crossing + peak picking via DFT bins) for a WAV.
python wav_notes.py file.wav [window_ms] [skip_s]  -> per window: RMS and strongest frequency (50..2000 Hz) from a brute-force DFT"""
import sys, wave, struct, math
path = sys.argv[1]
win = int(sys.argv[2]) if len(sys.argv) > 2 else 120
skip = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
w = wave.open(path, 'rb')
ch, fr, n = w.getnchannels(), w.getframerate(), w.getnframes()
raw = w.readframes(n)
v = struct.unpack('<%dh' % (len(raw) // 2), raw)
mono = [(v[i] + (v[i + 1] if ch > 1 else 0)) / ch for i in range(0, len(v) - ch + 1, ch)]
step = fr * win // 1000
dec = 4                      # decimate to 11 kHz for speed
for k in range(int(skip * fr), len(mono) - step, step):
    seg = mono[k:k + step:dec]
    m = sum(seg) / len(seg)
    seg = [s - m for s in seg]
    rms = math.sqrt(sum(s * s for s in seg) / len(seg))
    fs = fr / dec
    best, bf = 0, 0
    for f in range(100, 1500, 10):
        a = sum(seg[i] * math.cos(2 * math.pi * f * i / fs) for i in range(0, len(seg), 2))
        b = sum(seg[i] * math.sin(2 * math.pi * f * i / fs) for i in range(0, len(seg), 2))
        p = a * a + b * b
        if p > best:
            best, bf = p, f
    print('%6.2fs rms %7.1f  peak %4d Hz' % (k / fr, rms, bf))
