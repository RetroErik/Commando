"""Build a function/call index of the original code (linear sweep from objdump listing)."""
import os, re, collections
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lines = open(os.path.join(HERE, 'analysis', 'code_disasm.txt')).read().splitlines()
ins = []
for l in lines:
    m = re.match(r'\s*([0-9a-f]+):\t([0-9a-f ]+?)\s*\t(.*)', l)
    if m:
        ins.append((int(m.group(1), 16), m.group(3).strip()))
callers = collections.defaultdict(list)
for a, t in ins:
    m = re.match(r'call\s+0x([0-9a-f]+)', t)
    if m:
        callers[int(m.group(1), 16)].append(a)
starts = []
for i in range(len(ins) - 1):
    if ins[i][1].startswith('push   bp') and ins[i + 1][1].startswith('mov    bp,sp'):
        starts.append(ins[i][0])
out = []
for s in starts:
    out.append('%04X  callers=%d  %s' % (s, len(callers.get(s, [])), ' '.join('%04X' % c for c in callers.get(s, [])[:8])))
open(os.path.join(HERE, 'analysis', 'functions.txt'), 'w').write('\n'.join(out))
print(len(starts), 'functions;', len(callers), 'call targets')
