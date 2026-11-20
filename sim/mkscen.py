#!/usr/bin/env python3
"""Write lockstep scenarios: mkscen.py <name>  -> scen_<name>.txt"""
import re, sys
EMU = '/home/mike/claude/microtronic/emulator/'
def mic(path):
    a, out = 0, []
    for line in open(path):
        line = line.split('#')[0].strip()
        if not line: continue
        if line.startswith('@'): a = int(line[1:].split()[0], 16); continue
        for w in line.split():
            if re.fullmatch(r'[0-9A-Fa-f]{3}', w): out.append((a, w)); a += 1
    blocks, cur = [], None
    for a, w in out:
        if cur and cur[0] + len(cur[1]) == a: cur[1].append(w)
        else: cur = [a, [w]]; blocks.append(cur)
    return ''.join(f"load {a:02x} {' '.join(ws)}\n" for a, ws in blocks)
def keys(s, hold=12000, gap=12000):
    return ''.join(f"down {k}\nrun {hold} 2000\nup {k}\nrun {gap} 2000\n" for k in s.split())
S = {}
S['boot'] = "run 300000 1000\n"
S['keys'] = "run 60000 2000\n" + keys("HALT NEXT 0 0 F 1 0 NEXT 1 2 3 NEXT C 0 0 NEXT HALT NEXT 0 0 RUN") + "run 100000 2000\n" + keys("HALT REG 7 5 HALT CCE BKP 0 3 STEP STEP")
S['first'] = "run 60000 2000\n" + mic(EMU + 'programs/guide/G-FIRST.MIC') + keys("HALT NEXT 0 0 RUN") + "run 200000 2000\n"
S['inout'] = ("run 60000 2000\n" + mic(EMU + 'programs/guide/G-INOUT.MIC') + keys("HALT NEXT 0 0 RUN") +
              "run 50000 2000\ndin 5\nrun 50000 2000\ndin 10\nrun 50000 2000\nclock 4\nrun 250000 2000\npatch 0 1\nrun 100000 2000\nunpatch\nclock 0\ndin 0\nrun 30000 2000\n")
S['pgm'] = "run 60000 2000\n" + keys("HALT PGM 7") + "run 200000 2000\n" + keys("1 2 3 NEXT") + "run 300000 2000\nreset\nrun 100000 2000\n" + keys("HALT PGM 1") + "run 100000 2000\n"
S['games'] = ("run 60000 2000\n" + mic('/home/mike/git/Busch-2090/software/BLOCKADE.MIC') + keys("HALT NEXT 0 0 RUN") + "run 300000 2000\n"
              + keys("1 3 2 4 6 8") + "run 200000 2000\n" + keys("HALT") + mic(EMU + 'programs/sound/LUNAR-SOUND.MIC') + keys("NEXT 0 0 RUN") + "run 300000 2000\n" + keys("5 0 NEXT 9 9 NEXT") + "run 300000 2000\n")
for n in (sys.argv[1:] or S):
    open(f'scen_{n}.txt', 'w').write(S[n]); print(n, S[n].count('\n'), 'lines')
