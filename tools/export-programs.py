#!/usr/bin/env python3
"""Export the browser emulator's program library as .MIC files for the MiSTer core:
dist/games/Microtronic/{Busch,Guide,Rathje}/NAME.MIC, each with a line naming the menu
settings (wiring) it needs.  Programs that need the tone circuit or PicoRAM sound are left out."""
import json, os
EMU = os.path.expanduser('~/claude/microtronic/emulator/js/programs.js')
s = open(EMU).read(); lib = json.loads(s[s.index('['):s.rindex(']') + 1])
FOLDER = {'From the Busch manuals': 'Busch', 'Examples from the guide': 'Guide', 'Games by Björn Rathje': 'Rathje'}
out = 'dist/games/Microtronic'
n = 0
for e in lib:
    su = e.get('setup') or {}
    if e['group'] not in FOLDER or su.get('vib'): continue
    w = []
    if 'piezo' in su: w.append(f"Piezo buzzer on = Output {su['piezo'] + 1}")
    if 'clock' in su: w.append(f"1 Hz clock cable to = Input {su['clock'] + 1}")
    if 'patch' in su: w.append(f"Patch cable from = Output {su['patch'][0] + 1}, to = Input {su['patch'][1] + 1}")
    if 'G' in su: w.append(f"Red key G wired to = Input {su['G'] + 1}")
    if 'H' in su: w.append(f"Red key H wired to = Input {su['H'] + 1}")
    head = f"# MiSTer menu: {'; '.join(w)}\n" if w else ''
    text = e['text']
    if not text.lstrip().startswith('#'): text = f"# {e['title']}\n\n" + text
    lines = text.split('\n', 1)                  # wiring line after the title line
    text = lines[0] + '\n' + head + (lines[1] if len(lines) > 1 else '')
    d = os.path.join(out, FOLDER[e['group']]); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, e['name'] + '.MIC'), 'w', newline='\r\n').write(text)
    n += 1
print(n, 'programs ->', out)
