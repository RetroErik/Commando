import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'adlib_verify.py')).read().split('# decode channel-0')[0]
src = src.replace('sys.argv[1]', "'16000000'")
exec(src)
cur = None
cnt = collections.Counter()
first = {}
for t, p, v in g.io_log:
    if p == 0x388:
        cur = v
    elif p == 0x389:
        key = cur
        if cur == 0xB3 and v & 0x20:
            cnt['gun body key-on'] += 1
            first.setdefault('gun body key-on', t)
        if cur == 0xBD and v & 0x08:
            cnt['rhythm snare noise on'] += 1
            first.setdefault('snare', t)
        if cur == 0xB0 and v & 0x20:
            cnt['melody key-on'] += 1
        if cur == 0xA3:
            cnt['gun pitch writes'] += 1
print(dict(cnt), first)
print('speaker-port writes after ADLIB selected:', sum(1 for t, p, v in g.io_log if p in (0x42, 0x61) and t > 400_000))
