"""Summarise a DOSBox WAV capture: RMS level and a rough dominant pitch per window.  python wav_report.py file.wav [window_ms]"""
import sys, wave, struct, math

path = sys.argv[1]
win_ms = int(sys.argv[2]) if len(sys.argv) > 2 else 500
w = wave.open(path, 'rb')
ch, sw, fr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
raw = w.readframes(n)
assert sw == 2
vals = struct.unpack('<%dh' % (len(raw) // 2), raw)
mono = [vals[i] for i in range(0, len(vals), ch)]
step = fr * win_ms // 1000
print('%s: %d Hz, %d ch, %.1f s' % (path, fr, ch, len(mono) / fr))
for k in range(0, len(mono) - step, step):
    seg = mono[k:k + step]
    rms = math.sqrt(sum(s * s for s in seg) / len(seg))
    zc = sum(1 for i in range(1, len(seg)) if (seg[i - 1] < 0) != (seg[i] < 0))
    f0 = zc / 2.0 / (len(seg) / fr)
    print('%6.1fs  rms %7.1f  zero-cross pitch ~%6.0f Hz  %s' % (k / fr, rms, f0, '#' * int(min(60, rms / 100))))
