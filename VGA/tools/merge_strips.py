import re, sys
runs = []
cur = None
for l in open(sys.argv[1]):
    m = re.match(r'fn (\w+) from (\w+) src DS:(\w+) count (\d+)\s+x(\d+)', l)
    if not m:
        continue
    fn, ret, src, cnt, k = m.group(1), m.group(2), int(m.group(3), 16), int(m.group(4)), int(m.group(5))
    runs.append((src, cnt, fn, ret))
runs.sort()
# merge consecutive sources with equal widths
merged = []
for src, cnt, fn, ret in runs:
    if merged and merged[-1][0] + merged[-1][1] * merged[-1][3] == src and merged[-1][1] == cnt:
        merged[-1][3] += 1
    elif merged and merged[-1][0] == src and merged[-1][1] == cnt:
        pass
    else:
        merged.append([src, cnt, fn, 1])
for src, w, fn, rows in merged:
    print('DS:%04X width %2d bytes rows %3d  (%s)' % (src, w, rows, fn))
