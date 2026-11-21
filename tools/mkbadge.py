#!/usr/bin/env python3
"""Generate rtl/badge.hex: the console badge ("microtronic / computer system" between two rules) as a
120x64 bitmap of 4-bit ink coverage, stored 128 entries per row (address = y*128 + x).

The artwork is the SVG of the browser emulator's badge (index.html, <svg id="badgeart">), which was
traced from a photo of the real badge.  It is filled here with the even-odd rule at 8x8 samples per
pixel, so the curves come out antialiased.  Writes badge_preview.png next to the hex when PIL is there."""
import os, re, sys
import numpy as np

W, H, SS = 120, 64, 8
EMU = os.environ.get('MICROTRONIC_EMU', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'microtronic-emulator'))
html = open(os.path.join(EMU, 'index.html'), encoding='utf-8').read()
svg = re.search(r'<svg id="badgeart"(.*?)</svg>', html, re.S).group(0)
vw, vh = map(float, re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg).groups())
tx, ty = map(float, re.search(r'translate\(([\d.-]+) ([\d.-]+)\)', svg).groups())
sx, sy = W * SS / vw, H * SS / vh                      # preserveAspectRatio="none": the SVG fills the plate

def pt(x, y): return ((x + tx) * sx, (y + ty) * sy)

# ---- outlines -> closed polygons (cubic curves flattened to 8 segments) ----
polys = []
toks = re.findall(r'[MLCZ]|-?\d+(?:\.\d+)?', re.search(r' d="([^"]+)"', svg).group(1))
i, cur, start, pos = 0, [], None, None
while i < len(toks):
	c = toks[i]; i += 1
	if c == 'M':
		if cur: polys.append(cur)
		pos = (float(toks[i]), float(toks[i + 1])); i += 2; cur = [pt(*pos)]; start = pos
	elif c == 'L':
		pos = (float(toks[i]), float(toks[i + 1])); i += 2; cur.append(pt(*pos))
	elif c == 'C':
		p0 = pos; p1, p2, p3 = [(float(toks[i + 2 * k]), float(toks[i + 2 * k + 1])) for k in range(3)]; i += 6
		for k in range(1, 9):
			t = k / 8; u = 1 - t
			cur.append(pt(*(u**3 * p0[j] + 3 * u * u * t * p1[j] + 3 * u * t * t * p2[j] + t**3 * p3[j] for j in (0, 1))))
		pos = p3
	elif c == 'Z':
		if cur: polys.append(cur); cur = []
		pos = start
if cur: polys.append(cur)
for m in re.finditer(r'<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)"', svg):   # the two rules
	x, y, w, h = map(float, m.groups())
	polys.append([pt(x, y), pt(x + w, y), pt(x + w, y + h), pt(x, y + h)])

# ---- even-odd scanline fill on the sample grid ----
edges = []
for p in polys:
	for (x0, y0), (x1, y1) in zip(p, p[1:] + p[:1]):
		if y0 != y1: edges.append((x0, y0, x1, y1))
e = np.array(edges)
samp = np.zeros((H * SS, W * SS), bool)
for row in range(H * SS):
	ys = row + 0.5
	a = e[((e[:, 1] <= ys) & (e[:, 3] > ys)) | ((e[:, 3] <= ys) & (e[:, 1] > ys))]
	if not len(a): continue
	xs = np.sort(a[:, 0] + (ys - a[:, 1]) * (a[:, 2] - a[:, 0]) / (a[:, 3] - a[:, 1]))
	for xa, xb in zip(xs[0::2], xs[1::2]):              # sample centres x + 0.5 inside [xa, xb)
		samp[row, max(0, int(np.ceil(xa - 0.5))):min(W * SS, int(np.ceil(xb - 0.5)))] ^= True
cov = samp.reshape(H, SS, W, SS).mean(axis=(1, 3))
lvl = np.rint(cov * 15).astype(int)

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'rtl', 'badge.hex')
with open(out, 'w') as f:
	for y in range(H):
		f.write('\n'.join('%x' % v for v in list(lvl[y]) + [0] * (128 - W)) + '\n')
print('badge', W, 'x', H, '->', os.path.normpath(out), '; ink', int((lvl > 7).sum()), 'pixels')
if len(sys.argv) > 1:                                   # mkbadge.py preview.png: an enlarged preview
	from PIL import Image
	top, bot = np.array([0xcf, 0xcf, 0xcd]), np.array([0xb1, 0xb2, 0xb3])
	plate = top + (bot - top) * (np.arange(H)[:, None, None] / (H - 1))
	img = plate * (1 - lvl[:, :, None] / 15) + np.array([0x0d, 0x0d, 0x0e]) * (lvl[:, :, None] / 15)
	Image.fromarray(img.astype(np.uint8)).resize((W * 4, H * 4), Image.NEAREST).save(sys.argv[1])
