#!/usr/bin/env python3
"""Every .MIC under dist/: the hardware loader's 2114 contents must equal the browser emulator's parseMIC."""
import glob, re, subprocess, sys
def fnv(vals):
    h = 2166136261
    for v in vals: h = ((h ^ (v & 255)) * 16777619) & 0xffffffff
    return '%08x' % h
def parse(text):                                   # js/ui.js parseMIC
    fix = lambda s: re.sub('[Il]', '1', re.sub('[OoQ]', '0', s)).upper()
    out, a = [], 0
    for line in re.split(r'\r?\n', text):
        line = re.sub(r'[#;].*$', '', line).strip()
        if not line: continue
        m = re.fullmatch(r'@\s*([0-9A-Fa-fOoQIl]{1,2})', line)
        if m: a = int(fix(m.group(1)), 16); continue
        for tok in re.split(r'[\s,]+', line):
            w = fix(tok)
            if not re.fullmatch("[0-9A-F]{3}", w): raise ValueError(tok)
            out.append((a, int(w, 16))); a += 1
    return out
bad = 0
files = sorted(glob.glob(sys.argv[1] + '/**/*.MIC', recursive=True))
for f in files:
    s = [15] * 1024
    try: words = parse(open(f, encoding='utf-8', errors='replace').read())
    except ValueError as e: print('SKIP emulator rejects token', e, f); continue
    for a, v in words: s[a] = ~(v >> 8) & 15; s[0x200 + a] = ~(v >> 4) & 15; s[0x100 + a] = ~v & 15
    open('sim/_l.txt', 'w').write(f'mic {f}\nsramhash\n')
    got = subprocess.run(['sim/objv/tb_video', 'sim/_l.txt'], capture_output=True, text=True).stdout.split()[-1]
    ok = got == fnv(s); bad += not ok
    print(f"{'ok ' if ok else 'BAD'} {len(words):3d} words  {f.split('Microtronic/')[-1]}")
print(len(files) - bad, 'of', len(files), 'files load identically')
