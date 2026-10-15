import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'adlib_verify.py')).read().split('# decode channel-0')[0].replace('sys.argv[1]', "'6000000'"))
cur = None
n = 0
for t, p, v in g.io_log:
    if p == 0x388:
        cur = v
    elif p == 0x389:
        if cur in (0xA0, 0xB0, 0xA3, 0xB3):
            print('%9d reg %02X = %02X' % (t, cur, v))
            n += 1
            if n > 24:
                break
print(notes[:6])
