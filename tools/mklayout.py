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
cells = [[(0, 32)] * W for _ in range(H)]
def put(col, row, s, colour):
    for i, ch in enumerate(s): cells[row][col + i] = (colour, ord(ch))
def centre(ccol, row, s, colour): put(ccol - (len(s) - 1) // 2, row, s, colour)
# I/O strip (rows 1-6): socket centres at text columns 5 | 12 16 20 24 | 36 40 44 48 | 58 | 70
centre(5, 1, 'GND', BLACK); centre(5, 2, '-', BLACK)
centre(18, 1, 'Ausgänge/Outputs', BLACK)
for i, c in enumerate((12, 16, 20, 24)): centre(c, 2, str(i + 1), BLACK)
centre(42, 1, 'Eingänge/Inputs', BLACK)
for i, c in enumerate((36, 40, 44, 48)): centre(c, 2, str(i + 1), BLACK)
centre(58, 1, 'Takt/Clock', BLACK); centre(58, 2, '1 Hz', BLACK)
centre(70, 1, 'GND', BLACK); centre(70, 2, '-', BLACK)
for i, c in enumerate((36, 40, 44, 48)): centre(c, 4, 'F' + str(i + 1), MID)
# badge
centre(20, 9, 'microtronic', BLACK); centre(20, 10, 'computer system', BLACK)
# carry / zero LEDs (row 12), display label (row 18)
put(13, 12, 'Carry', LIGHT); put(26, 12, 'Zero', LIGHT)
centre(25, 18, 'Anzeige/Display', LIGHT)
# red keys G / H: centres at columns 14 and 26
centre(14, 25, 'G', LIGHT); centre(26, 25, 'H', LIGHT)
centre(20, 26, 'Taster/Keys', LIGHT)
centre(14, 27, '( , )', MID); centre(26, 27, '( . )', MID)
# keypad: label rows 9, 14, 19, 24; key interiors on rows 11, 16, 21, 26; centres 48 53 58 63 68 73
KEYS = [['C', 'D', 'E', 'F', 'NEXT', 'REG'], ['8', '9', 'A', 'B', 'BKP', 'STEP'],
        ['4', '5', '6', '7', 'RUN', 'HALT'], ['0', '1', '2', '3', 'C/CE', 'PGM']]
PCKEY = {'NEXT': 'Ent', 'REG': 'G', 'BKP': 'K', 'STEP': 'S', 'RUN': 'R', 'HALT': 'H', 'C/CE': 'Bksp', 'PGM': 'P'}
for r, row in enumerate(KEYS):
    for c, k in enumerate(row):
        cc = 48 + 5 * c
        centre(cc, 9 + 5 * r, k, BLACK)
        if k in PCKEY: centre(cc, 11 + 5 * r, PCKEY[k], MID)
put(1, 29, 'F1-F4 inputs   , . keys G/H   Esc reset   F12 menu: load .MIC, speed, wiring', MID)
flat = ['%03x' % ((col << 8) | ch) for row in cells for col, ch in row]
flat += ['020'] * (4096 - len(flat))                       # padding: the blanking rows read spaces
open('rtl/text.hex', 'w').write('\n'.join(flat) + '\n')
print('font', len(rows), 'bytes; text', W * H, 'cells')
