#!/usr/bin/env python3
"""Generate rtl/font.hex (8x16 Latin-1 glyphs) and rtl/text.hex (80x30 text layer, 12-bit {colour, char}).
The coordinates here match the shapes in rtl/video.v (text cell = 8x16 pixels)."""
import gzip, struct
# ---- font: misc-fixed 8x16 (public domain) from the Linux console fonts ----
d = gzip.open('/usr/share/consolefonts/Lat15-Fixed16.psf.gz').read()
if d[:2] == b'\x36\x04':                                   # PSF1
    mode, h = d[2], d[3]; n = 512 if mode & 1 else 256; off = 4; glyph = lambda i: d[off + i*h: off + (i+1)*h]
    tab = d[off + n*h:]; uni = {}; i = 0; g = 0; cur = []
    while g < n and i + 1 < len(tab):
        v = struct.unpack_from('<H', tab, i)[0]; i += 2
        if v == 0xFFFF: g += 1; continue
        if v == 0xFFFE: continue
        uni.setdefault(v, g)
else:                                                       # PSF2
    _, ver, hs, fl, n, bpg, h, w = struct.unpack_from('<8I', d); glyph = lambda i: d[hs + i*bpg: hs + (i+1)*bpg]
    uni = {}; p = hs + n*bpg; g = 0; cur = b''
    while g < n and p < len(d):
        if d[p] == 0xFF: 
            for ch in cur.decode('utf-8', 'ignore'): uni.setdefault(ord(ch), g)
            g += 1; cur = b''
        else: cur += bytes([d[p]])
        p += 1
assert h == 16, h
rows = []
for c in range(256):
    gi = uni.get(c, uni.get(ord('?')))
    rows += list(glyph(gi))
open('rtl/font.hex', 'w').write('\n'.join('%02x' % b for b in rows) + '\n')

# ---- text layer ----
W, H = 80, 30
BLACK, LIGHT, MID, WHITE, YELLOW = 0, 1, 2, 3, 4
cells = [[(0, 0, 32)] * W for _ in range(H)]          # (shift, colour, char)
def put(col, row, s, colour, shift=0):
    for i, ch in enumerate(s): cells[row][col + i] = (shift, colour, ord(ch))
def centre(ccol, row, s, colour):
    """Centre s on the middle of cell ccol (pixel 8*ccol + 4).  A label with an even number of
    characters is drawn with the shift bit: video.v moves those cells 4 pixels to the right."""
    if len(s) % 2: put(ccol - len(s) // 2, row, s, colour)
    else:          put(ccol - len(s) // 2, row, s, colour, shift=1)
# I/O strip (rows 1-6): socket centres at text columns 7 | 14 18 22 26 | 38 42 46 50 | 60 | 72 (centred, see video.v)
centre(7, 1, 'GND', BLACK); centre(7, 2, '-', BLACK)
centre(20, 1, 'Ausgänge/Outputs', BLACK)
for i, c in enumerate((14, 18, 22, 26)): centre(c, 2, str(i + 1), BLACK)
centre(44, 1, 'Eingänge/Inputs', BLACK)
for i, c in enumerate((38, 42, 46, 50)): centre(c, 2, str(i + 1), BLACK)
centre(60, 1, 'Takt/Clock', BLACK); centre(60, 2, '1 Hz', BLACK)
centre(72, 1, 'GND', BLACK); centre(72, 2, '-', BLACK)
for i, c in enumerate((38, 42, 46, 50)): centre(c, 4, 'F' + str(i + 1), MID)
# left panel: everything centred on column 22 (x = 180), like the shapes in video.v
# the badge (rows 8-12) is a bitmap: rtl/badge.hex from tools/mkbadge.py
# carry / zero LEDs (row 13), display label (row 20, below the bezel)
put(16, 13, 'Carry', LIGHT); put(27, 13, 'Zero', LIGHT)
centre(22, 20, 'Anzeige/Display', LIGHT)
# red keys G / H: centres at columns 16 and 28
centre(16, 25, 'G', LIGHT); centre(28, 25, 'H', LIGHT)
centre(22, 26, 'Taster/Keys', LIGHT)
centre(16, 27, '( , )', MID); centre(28, 27, '( . )', MID)
# keypad: label rows 9, 14, 19, 24; key interiors on rows 11, 16, 21, 26; centres 46 51 56 61 | 68 73 (video.v keyx)
KEYS = [['C', 'D', 'E', 'F', 'NEXT', 'REG'], ['8', '9', 'A', 'B', 'BKP', 'STEP'],
        ['4', '5', '6', '7', 'RUN', 'HALT'], ['0', '1', '2', '3', 'C/CE', 'PGM']]
PCKEY = {'NEXT': 'Ent', 'REG': 'G', 'BKP': 'K', 'STEP': 'S', 'RUN': 'R', 'HALT': 'H', 'C/CE': 'Del', 'PGM': 'P'}
for r, row in enumerate(KEYS):
    for c, k in enumerate(row):
        cc = (46 + 5 * c) if c < 4 else (68 + 5 * (c - 4))
        centre(cc, 9 + 5 * r, k, BLACK)
        if k in PCKEY: centre(cc, 11 + 5 * r, PCKEY[k], MID)
put(1, 29, 'F1-F4 inputs   , . keys G/H   Esc reset   F12 menu: load .MIC, speed, wiring', MID)
flat = ['%03x' % ((sh << 11) | (col << 8) | ch) for row in cells for sh, col, ch in row]
flat += ['020'] * (4096 - len(flat))                       # padding: the blanking rows read spaces
open('rtl/text.hex', 'w').write('\n'.join(flat) + '\n')
print('font', len(rows), 'bytes; text', W * H, 'cells')
