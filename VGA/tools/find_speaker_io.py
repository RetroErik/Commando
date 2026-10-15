"""List the speaker-port instructions (OUT 61h / OUT 42h / IN 61h) in the original game code."""
import os, sys
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lines = open(os.path.join(HERE, 'analysis', 'code_clean.txt')).read().splitlines()
for pat in ('out    0x61,al', 'out    0x42,al', 'out    0x43,al', 'in     al,0x61', 'in     al,0x42'):
    sites = [l.split()[0] for l in lines if l.rstrip().endswith(pat)]
    print(pat, len(sites), sites)
