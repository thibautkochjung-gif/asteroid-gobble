"""Procedural pixel-art ring station renderer for the hub mockups.
Everything attached to the ring is drawn in the ring's (rotating) frame, so it's static on screen.
The despun hub and the sky rotate around the ring centre in the game (Hub/hub.gd)."""
import math, random, json, os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
import os
os.makedirs(OUT, exist_ok=True)


def hexc(h, a=255):
	h = h.lstrip("#")
	return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a], dtype=np.uint8)


P = {k: hexc(v) for k, v in {
	"out": "0f0e12", "hull": "8f8a83", "hull2": "a49e95", "hull3": "77726c", "hull_dk": "57534f",
	"steel": "6b6862", "steel_dk": "3d3a37", "dark": "242226", "window": "ffd98a", "window2": "f2b45c",
	"window_off": "2e2c2c", "glass": "5aa6a0", "glass2": "7fc4a8", "green": "6fae5a", "rust": "8a4a2c",
	"primer": "ab5c2e", "yel": "d4a329", "yel_dk": "785a0f", "cream": "e8decc", "red": "e35420",
	"teal": "335a7a", "pipe": "9c958a", "pipe_dk": "5c5750", "rad": "c9c3b6", "rad2": "aaa395",
	"solar": "263a5c", "solar2": "35507a", "white": "ffffff", "blue": "61b0c4", "fin": "966145",
}.items()}


class Canvas:
	def __init__(self, w, h, cx, cy, k=1):
		"""w, h, cx, cy in design texels. k = output pixels per design texel (2 = double resolution:
		same drawing, finer edges)."""
		self.k = k
		self.w, self.h, self.cx, self.cy = w * k, h * k, cx, cy
		self.img = np.zeros((self.h, self.w, 4), dtype=np.uint8)
		ys, xs = np.mgrid[0:self.h, 0:self.w]
		self.dx = (xs + 0.5) / k - cx
		self.dy = (ys + 0.5) / k - cy
		self.r = np.hypot(self.dx, self.dy)
		self.th = np.arctan2(self.dy, self.dx) % (2 * math.pi)  # clockwise on screen
		self.masks = {}

	def paint(self, mask, col, area=None):
		self.img[mask] = col
		if area:
			self.masks[area] = self.masks.get(area, np.zeros(mask.shape, bool)) | mask

	def local(self, ang, rad):
		"""Local frame at angle ang: u = along the arc (px, clockwise), v = radial distance from centre."""
		d = (self.th - ang + math.pi) % (2 * math.pi) - math.pi
		return d * rad, self.r, d

	def rect_polar(self, ang, u0, u1, v0, v1, ref_r):
		"""Box in a straight local frame (tangent u, normal v) at angle ang, so long things stay straight."""
		ca, sa = math.cos(ang), math.sin(ang)
		# normal n = (ca, sa), tangent t = (-sa, ca)
		nv = self.dx * ca + self.dy * sa
		tu = -self.dx * sa + self.dy * ca
		return (tu >= u0) & (tu < u1) & (nv >= v0) & (nv < v1) & (nv > 0), tu, nv

	def outline(self, col=P["out"]):
		for _ in range(self.k):  # one design texel thick, whatever the resolution
			self._outline_once(col)

	def _outline_once(self, col):
		a = self.img[:, :, 3] > 0
		grown = a.copy()
		grown[1:, :] |= a[:-1, :]
		grown[:-1, :] |= a[1:, :]
		grown[:, 1:] |= a[:, :-1]
		grown[:, :-1] |= a[:, 1:]
		edge = grown & ~a
		self.img[edge] = col

	def save(self, name, scale=2):
		"""scale: output px per design texel."""
		im = Image.fromarray(self.img, "RGBA")
		im = im.resize((self.w * scale // self.k, self.h * scale // self.k), Image.NEAREST)
		im.save(f"{OUT}/{name}.png", optimize=True)

	def save_highlight(self, area, name, col=(245, 204, 92, 255), scale=2):
		m = self.masks[area]
		grown = m.copy()
		for _ in range(2 * self.k):
			g = grown.copy()
			g[1:, :] |= grown[:-1, :]
			g[:-1, :] |= grown[1:, :]
			g[:, 1:] |= grown[:, :-1]
			g[:, :-1] |= grown[:, 1:]
			grown = g
		edge = grown & ~m
		# keep the outline dashed so it reads as a selection, not as art
		ys, xs = np.mgrid[0:self.h, 0:self.w]
		edge &= ((xs + ys) // (3 * self.k)) % 2 == 0
		out = np.zeros((self.h, self.w, 4), np.uint8)
		out[edge] = col
		Image.fromarray(out, "RGBA").resize((self.w * scale // self.k, self.h * scale // self.k), Image.NEAREST).save(f"{OUT}/{name}.png", optimize=True)


def panel_noise(c, mask, u, v, base_cols, cell=(7, 5), seed=0):
	rng = np.random.default_rng(seed)
	cu = np.floor(u / cell[0]).astype(int)
	cv = np.floor(v / cell[1]).astype(int)
	key = (cu * 73856093 ^ cv * 19349663) & 0xFFFF
	lut = rng.integers(0, len(base_cols), 0x10000)
	choice = lut[key]
	for i, col in enumerate(base_cols):
		c.paint(mask & (choice == i), col)
	# panel seams
	seam = mask & ((np.mod(u, cell[0]) < 0.9) | (np.mod(v, cell[1]) < 0.9))
	c.paint(seam, P["hull_dk"])


FONT_PATHS = [
	"/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf",
	"/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
	"/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf",
]


def text_bitmap(text, px):
	"""Text as a boolean bitmap, px tall letters, in output pixels. No anti-aliasing: crisp pixels."""
	from PIL import ImageFont, ImageDraw
	f = None
	for path in FONT_PATHS:
		if os.path.exists(path):
			f = ImageFont.truetype(path, px)
			break
	if f is None:
		f = ImageFont.load_default()
	im = Image.new("L", (len(text) * px + 8, px * 2), 0)
	ImageDraw.Draw(im).text((2, 0), text, fill=255, font=f)
	a = np.array(im) > 140
	ys, xs = np.nonzero(a)
	return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def paint_text_local(c, m, uu, v, bitmap, u0, v0, col, flip=False, mirror=False):
	"""uu, v, u0, v0 in design texels; the bitmap is in output pixels."""
	h, w = bitmap.shape
	iu = np.floor((uu - u0) * c.k).astype(int)
	iv = np.floor((v - v0) * c.k).astype(int)
	if flip:
		iv = h - 1 - iv
	if mirror:
		iu = w - 1 - iu
	ok = m & (iu >= 0) & (iu < w) & (iv >= 0) & (iv < h)
	sel = np.zeros(m.shape, bool)
	sel[ok] = bitmap[iv[ok], iu[ok]]
	c.paint(sel, col)


def ring(c, R_in, R_out, seg_len, types, seed=1, area_of=None, label="RING 4"):
	"""types: function(seg_index, n_segments) -> type string."""
	rng = random.Random(seed)
	Rm = (R_in + R_out) / 2
	n = max(8, int(round(2 * math.pi * Rm / seg_len)))
	seg_ang = 2 * math.pi / n
	body = (c.r >= R_in) & (c.r < R_out)
	seg = np.floor(c.th / seg_ang).astype(int) % n
	frac = (c.th / seg_ang) % 1.0
	v = c.r - R_in
	H = R_out - R_in
	x = v / H
	# hull, shaded across the tube so it reads as a cylinder
	panel_noise(c, body, c.th * Rm, c.r, [P["hull"], P["hull2"], P["hull"], P["hull3"], P["hull"]], cell=(5, max(3, H // 6)), seed=seed)
	c.paint(body & ((x < 0.12) | (x > 0.9)), P["hull_dk"])
	c.paint(body & (((x >= 0.12) & (x < 0.2)) | ((x > 0.82) & (x <= 0.9))), P["hull3"])
	c.paint(body & (x > 0.42) & (x < 0.47), P["hull2"])
	label_bm = text_bitmap(label, max(7, int(H * c.k * 0.3)))
	label_h = label_bm.shape[0] / c.k
	for i in range(n):
		t = types(i, n)
		m = body & (seg == i)
		a0 = i * seg_ang
		uu = (c.th - a0) * Rm
		L = seg_ang * Rm
		area = area_of(i, n) if area_of else None
		if area:
			c.masks[area] = c.masks.get(area, np.zeros(m.shape, bool)) | m
		inner = m & (x > 0.2) & (x < 0.82)
		if t == "hab":
			cell = (np.floor(uu / 3).astype(int) * 131 + np.floor(x * 10).astype(int) * 977 + i * 7919) % 1000
			for xc in (0.3, 0.66):
				band = m & (np.abs(x - xc) * H < (1.0 if H < 36 else 1.6)) & (uu > 2) & (uu < L - 2)
				c.paint(band, P["steel_dk"])
				win = band & (np.mod(uu, 3) < 2)
				c.paint(win & (cell < 520), P["window"])
				c.paint(win & (cell >= 520) & (cell < 700), P["window2"])
				c.paint(win & (cell >= 700), P["window_off"])
			if i % 5 == 2:
				mid = (i + 0.5) * seg_ang
				top = mid > math.pi
				paint_text_local(c, m & (x > 0.3) & (x < 0.66), uu, v, label_bm, 3, H * 0.48 - label_h / 2, P["cream"], flip=top, mirror=not top)
		elif t == "green":
			pane = m & (x > 0.18) & (x < 0.84) & (uu > 1) & (uu < L - 1)
			c.paint(pane, P["glass"])
			c.paint(pane & (np.mod(uu * 3 + v * 5, 23) < 4), P["green"])
			c.paint(pane & (np.mod(uu + v, 11) < 1.2), P["glass2"])
			c.paint(pane & ((np.mod(uu, 4) < 0.8) | (np.mod(v, 5) < 0.8)), P["steel_dk"])
		elif t == "ind":
			c.paint(inner, P["steel"])
			for xc in (0.24, 0.32, 0.78):
				c.paint(m & (np.abs(x - xc) * H < 0.8), P["pipe"])
			for k in range(int(L // 8)):
				cx_ = 4 + k * 8
				tank = m & (np.hypot(uu - cx_, (x - 0.55) * H) < H * 0.13 + 0.8)
				c.paint(tank, P["cream"] if (k + i) % 3 else P["primer"])
				c.paint(tank & (np.hypot(uu - cx_ + 1, (x - 0.55) * H + 1) < 1.1), P["white"])
		elif t == "dock":
			c.paint(inner, P["steel_dk"])
			bay = m & (x > 0.28) & (x < 0.76) & (uu > 2) & (uu < L - 2)
			c.paint(bay, P["dark"])
			c.paint(m & (x > 0.2) & (x < 0.26) & (np.mod(uu, 4) < 2), P["yel"])
			c.paint(m & (x > 0.78) & (x < 0.84) & (np.mod(uu, 4) < 2), P["yel"])
			c.paint(bay & (np.mod(uu, 6) < 1), P["window2"])
		elif t == "scaffold":
			c.paint(m, (0, 0, 0, 0))
			frame = m & ((np.mod(uu, 5) < 1) | (np.mod(v, 5) < 1) | (np.abs(np.mod(uu + v, 10) - 5) < 0.7))
			c.paint(frame, P["yel_dk"])
			c.paint(m & (np.mod(uu, 10) < 1), P["yel"])
			c.paint(m & (uu < L * 0.35) & (x > 0.2) & (x < 0.8) & (np.mod(uu + v, 3) < 2), P["primer"])
		elif t == "exchange":
			atrium = m & (x > 0.2) & (x < 0.8) & (uu > 1) & (uu < L - 1)
			c.paint(atrium, P["glass"])
			c.paint(atrium & (np.mod(uu, 3) < 0.9), P["steel_dk"])
			c.paint(atrium & (np.mod(uu * 7 + v * 3, 13) < 2), P["window"])
			c.paint(m & (x <= 0.2) & (x > 0.12), P["yel"])
		elif t == "guild":
			c.paint(inner, P["hull3"])
			cell = (np.floor(uu / 2).astype(int) * 131 + np.floor(v / 2).astype(int) * 977 + i * 31) % 100
			win = inner & (np.mod(v, 2) < 1) & (np.mod(uu, 2) < 1)
			c.paint(win & (cell < 55), P["window"])
			c.paint(win & (cell >= 55), P["window_off"])
		# greebles on the shaded edges: vents, boxes
		for g in range(int(L // 4)):
			gu = rng.uniform(1, L - 4)
			gx = rng.choice([0.04, 0.86])
			gw = rng.randint(2, 4)
			gm = m & (uu > gu) & (uu < gu + gw) & (x > gx) & (x < gx + 0.08)
			c.paint(gm, rng.choice([P["steel_dk"], P["pipe"], P["hull2"], P["dark"]]))
		# segment joint
		j = body & (seg == i) & ((frac < 0.04) | (frac > 0.97))
		c.paint(j, P["steel_dk"])
	cm = collar_mask(c, R_in, R_out, seg_ang)
	c.paint(cm, P["steel_dk"])
	c.paint(cm & (np.abs(c.r - (R_out + 1)) < 0.7), P["yel"])
	# rim conduit and rail
	c.paint((np.abs(c.r - R_in - 0.5) < 0.8), P["pipe_dk"])
	c.paint((np.abs(c.r - R_out + 1) < 0.6) & (np.mod(c.th * Rm, 6) < 3), P["yel_dk"])
	return n, seg_ang


def inner_rail(c, R, width=3):
	m = np.abs(c.r - R) < width / 2
	c.paint(m, P["steel_dk"])
	c.paint(m & (np.abs(c.r - R) < 0.6), P["pipe"])


def parked_ship(c, ang, r0, col, size=1):
	L, Wd = 5 * size, 3 * size
	m, tu, nv = c.rect_polar(ang, -Wd / 2, Wd / 2, r0, r0 + L, 0)
	c.paint(m, col)
	c.paint(m & (nv > r0 + L - 1.5 * size), P["blue"])
	c.paint(m & (nv < r0 + size), P["steel_dk"])
	mm, _, _ = c.rect_polar(ang, -1, 1, r0 - 2, r0, 0)
	c.paint(mm, P["pipe_dk"])


def collar_mask(c, R_in, R_out, seg_ang):
	frac = (c.th / seg_ang) % 1.0
	Rm = (R_in + R_out) / 2
	d = np.minimum(frac, 1 - frac) * seg_ang * Rm
	return (c.r >= R_in - 2) & (c.r < R_out + 2) & (d < 1.6)


def spoke(c, ang, r0, r1, width=6, area=None):
	m, tu, nv = c.rect_polar(ang, -width / 2, width / 2, r0, r1, 0)
	c.paint(m, P["steel_dk"])
	lattice = m & ((np.abs(tu) > width / 2 - 1.2) | (np.abs(np.mod(nv + tu * 1.0, 8) - 4) < 0.7) | (np.abs(np.mod(nv - tu * 1.0, 8) - 4) < 0.7))
	c.paint(lattice, P["pipe"])
	c.paint(m & (np.abs(tu) < 0.8), P["yel_dk"])  # lift rail
	if area:
		c.masks[area] = c.masks.get(area, np.zeros(m.shape, bool)) | m


def boom(c, ang, r0, r1, width, col=P["steel"]):
	m, tu, nv = c.rect_polar(ang, -width / 2, width / 2, r0, r1, 0)
	c.paint(m, col)
	c.paint(m & (np.mod(nv, 6) < 1), P["steel_dk"])
	return m


def radiator(c, ang, r0, length, width=8):
	boom(c, ang, r0, r0 + length, 2, P["pipe_dk"])
	for side in (-1, 1):
		m, tu, nv = c.rect_polar(ang, (1 if side > 0 else -1 - width) if side > 0 else -1 - width, 1 + width if side > 0 else -1, r0 + 3, r0 + length - 1, 0)
		c.paint(m, P["rad"])
		c.paint(m & (np.mod(nv, 3) < 1), P["rad2"])


def solar(c, ang, r0, length, width=10):
	boom(c, ang, r0, r0 + length, 2, P["pipe_dk"])
	for side in (-1, 1):
		u0, u1 = (1, 1 + width) if side > 0 else (-1 - width, -1)
		m, tu, nv = c.rect_polar(ang, u0, u1, r0 + 4, r0 + length, 0)
		c.paint(m, P["solar"])
		c.paint(m & ((np.mod(nv, 4) < 0.8) | (np.mod(tu, 4) < 0.8)), P["solar2"])


def antenna(c, ang, r0, length):
	m, tu, nv = c.rect_polar(ang, -0.5, 0.5, r0, r0 + length, 0)
	c.paint(m, P["pipe"])
	d = (c.dx - math.cos(ang) * (r0 + length)) ** 2 + (c.dy - math.sin(ang) * (r0 + length)) ** 2
	c.paint(d < 4.5, P["cream"])


def containers(c, ang, r0, rows, cols, rng, area=None):
	cw, ch = 5, 3
	for row in range(rows):
		for col in range(cols):
			if rng.random() < 0.88:
				u0 = (col - cols / 2) * (cw + 1)
				m, tu, nv = c.rect_polar(ang, u0, u0 + cw, r0 + row * (ch + 1), r0 + row * (ch + 1) + ch, 0)
				c.paint(m, rng.choice([P["rust"], P["yel"], P["teal"], P["primer"], P["cream"], P["hull3"], P["green"]]), area)
	# rack frame
	m, tu, nv = c.rect_polar(ang, -cols / 2 * (cw + 1) - 1, cols / 2 * (cw + 1), r0 - 1, r0 + rows * (ch + 1), 0)
	frame = m & ((np.mod(nv - r0 + 1, ch + 1) < 1) & (c.img[:, :, 3] == 0))
	c.paint(frame, P["pipe_dk"], area)
	boom(c, ang, r0 - 6, r0, 3, P["steel_dk"])


def drydock(c, ang, r0, length, width, rng, area="shipyard"):
	half = width / 2
	m, tu, nv = c.rect_polar(ang, -half, half, r0, r0 + length, 0)
	c.masks[area] = c.masks.get(area, np.zeros(m.shape, bool)) | m
	beams = m & ((np.abs(tu) > half - 2) | (nv < r0 + 2) | (nv > r0 + length - 2) | (np.mod(nv - r0, 12) < 1.2))
	c.paint(beams, P["yel"])
	c.paint(beams & (np.mod(nv + tu, 6) < 2), P["yel_dk"])
	# hull under construction: ribs and keel
	keel = m & (np.abs(tu) < 1.5) & (nv > r0 + 6) & (nv < r0 + length - 6)
	c.paint(keel, P["pipe"])
	ribs = m & (np.abs(tu) < half * 0.55) & (np.mod(nv - r0, 5) < 1.4) & (nv > r0 + 8) & (nv < r0 + length - 10)
	c.paint(ribs, P["hull"])
	plated = m & (np.abs(tu) < half * 0.55) & (nv > r0 + length * 0.55) & (nv < r0 + length - 10)
	c.paint(plated, P["primer"])
	c.paint(plated & (np.mod(tu * 2 + nv, 7) < 1), P["rust"])
	nose = m & (np.abs(tu) < half * 0.4) & (nv >= r0 + length - 10) & (nv < r0 + length - 6)
	c.paint(nose, P["hull2"])
	boom(c, ang, r0 - 8, r0, 6, P["steel_dk"])
	# gantry cranes
	for k, frac in enumerate((0.3, 0.72)):
		mm, tu2, nv2 = c.rect_polar(ang, -half - 3, half + 3, r0 + length * frac, r0 + length * frac + 3, 0)
		c.paint(mm, P["red"] if k else P["yel_dk"])


def tower(c, ang, r0, length, width, rng, area="guild"):
	half = width / 2
	m, tu, nv = c.rect_polar(ang, -half, half, r0, r0 + length, 0)
	c.paint(m, P["hull3"], area)
	cell = (np.floor((tu + 100) / 2).astype(int) * 131 + np.floor(nv / 3).astype(int) * 977) % 100
	win = m & (np.mod(nv - r0 - 2, 3) < 0.9) & (np.mod(tu + half, 2) < 1) & (np.abs(tu) < half - 1.5) & (nv < r0 + length - 1)
	c.paint(win & (cell < 55), P["window"])
	c.paint(win & (cell >= 55), P["window_off"])
	c.paint(m & (np.abs(tu) > half - 1.2), P["steel_dk"])
	# crown: comms
	mm, tu2, nv2 = c.rect_polar(ang, -half - 2, half + 2, r0 + length, r0 + length + 3, 0)
	c.paint(mm, P["steel_dk"], area)
	for k in (-1, 1):
		antenna(c, ang + k * 0.02, r0 + length + 3, 8)
	# guild banner: crossed picks on rust
	bm, tu3, nv3 = c.rect_polar(ang, half + 1, half + 7, r0 + 4, r0 + 14, 0)
	c.paint(bm, P["rust"], area)
	c.paint(bm & ((np.abs((tu3 - half - 4) - (nv3 - r0 - 9) * 0.6) < 0.7) | (np.abs((tu3 - half - 4) + (nv3 - r0 - 9) * 0.6) < 0.7)), P["yel"])


def hangar(c, ang, r0, length, width, area="mechanic"):
	half = width / 2
	m, tu, nv = c.rect_polar(ang, -half, half, r0, r0 + length, 0)
	c.paint(m, P["hull3"], area)
	c.paint(m & (np.mod(tu + half, 5) < 1), P["hull_dk"])
	door = m & (np.abs(tu) < half - 3) & (nv > r0 + length - 6)
	c.paint(door, P["dark"])
	c.paint(m & (nv > r0 + length - 2) & (np.mod(tu, 4) < 2), P["yel"])
	# a ship on the cradle in the open bay (generic tug)
	sm = m & (np.abs(tu) < 3) & (nv > r0 + length - 9) & (nv < r0 + length - 3)
	c.paint(sm, P["teal"])
	# arms
	for k in (-1, 1):
		mm, tu2, nv2 = c.rect_polar(ang, k * (half + 1) - (0 if k > 0 else 2), k * (half + 1) + (2 if k > 0 else 0), r0 + 4, r0 + length + 6, 0)
		c.paint(mm, P["yel_dk"], area)


def nav_lights(c, R, n, offset=0.0):
	pts = []
	for k in range(n):
		a = offset + k * 2 * math.pi / n
		pts.append((c.cx + math.cos(a) * R, c.cy + math.sin(a) * R))
	return pts


def stars_img(size, seed, cx, cy, scale=2, nebula=True):
	rng = np.random.default_rng(seed)
	img = np.zeros((size, size, 4), np.uint8)
	img[:, :] = (8, 8, 13, 255)
	if nebula:
		ys, xs = np.mgrid[0:size, 0:size]
		field = np.zeros((size, size))
		for _ in range(9):
			x0, y0 = rng.uniform(0, size, 2)
			sx, sy = rng.uniform(30, 110, 2)
			field += rng.uniform(0.4, 1.0) * np.exp(-(((xs - x0) / sx) ** 2 + ((ys - y0) / sy) ** 2))
		dither = rng.uniform(0, 1, (size, size))
		lvl = np.clip(field * 0.55 + (dither - 0.5) * 0.12, 0, 1)
		cols = [(8, 8, 13), (20, 14, 30), (38, 20, 42), (62, 28, 52), (90, 40, 60)]
		idx = np.clip((lvl * 6).astype(int), 0, 4)
		for i, cc in enumerate(cols):
			img[idx == i, :3] = cc
		# teal wisps
		f2 = np.zeros((size, size))
		for _ in range(4):
			x0, y0 = rng.uniform(0, size, 2)
			f2 += np.exp(-(((xs - x0) / rng.uniform(20, 60)) ** 2 + ((ys - y0) / rng.uniform(60, 140)) ** 2))
		img[(f2 * 0.5 + (dither - 0.5) * 0.1) > 0.32, :3] = (24, 44, 52)
	for _ in range(int(size * size * 0.004)):
		x, y = rng.integers(0, size, 2)
		col = [(255, 255, 255), (207, 216, 255), (255, 233, 196), (138, 143, 176)][rng.integers(0, 4)]
		img[y, x, :3] = col
		if rng.random() < 0.06 and 0 < x < size - 1 and 0 < y < size - 1:
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				img[y + dy, x + dx, :3] = (120, 120, 150)
	im = Image.fromarray(img, "RGBA").resize((size * scale, size * scale), Image.NEAREST)
	return im


def ring_text(c, text, center_deg, R_in, R_out, col, back, px=None):
	"""Big lettering painted across segments. Readable on the bottom half of the ring."""
	H = R_out - R_in
	bm = text_bitmap(text, px or int(H * c.k * 0.42))
	h, w = bm.shape[0] / c.k, bm.shape[1] / c.k  # design texels
	Rm = (R_in + R_out) / 2
	ang0 = math.radians(center_deg)
	d = (c.th - ang0 + math.pi) % (2 * math.pi) - math.pi
	u = -d * Rm + w / 2  # left to right on screen at the bottom
	v = c.r - (R_in + H / 2 - h / 2)
	band = (c.r >= R_in + H / 2 - h / 2 - 2) & (c.r < R_in + H / 2 + h / 2 + 2) & (u >= -3) & (u < w + 3)
	c.paint(band, back)
	iu = np.floor(u * c.k).astype(int)
	iv = np.floor(v * c.k).astype(int)
	ok = band & (iu >= 0) & (iu < bm.shape[1]) & (iv >= 0) & (iv < bm.shape[0])
	sel = np.zeros(ok.shape, bool)
	sel[ok] = bm[iv[ok], iu[ok]]
	c.paint(sel, col)


def dish(c, ang, r0, size):
	boom(c, ang, r0, r0 + 4, 2, P["pipe_dk"])
	cx_ = c.cx + math.cos(ang) * (r0 + 4 + size)
	cy_ = c.cy + math.sin(ang) * (r0 + 4 + size)
	d = np.hypot(c.dx + c.cx - cx_, c.dy + c.cy - cy_)
	c.paint(d < size, P["cream"])
	c.paint((d < size) & (d > size - 1.2), P["rad2"])
	c.paint(d < 1.5, P["steel_dk"])


def patch(c, ang, r_a, r_b, du, col):
	m, tu, nv = c.rect_polar(ang, -du / 2, du / 2, r_a, r_b, 0)
	c.paint(m, col)
	c.paint(m & ((np.abs(tu) > du / 2 - 0.8) | (nv < r_a + 0.8) | (nv > r_b - 0.8)), P["rust"])


def gantry(c, ang, r0, r1, du):
	for side in (-1, 1):
		m, tu, nv = c.rect_polar(ang, side * du / 2 - 1, side * du / 2 + 1, r0, r1, 0)
		c.paint(m, P["yel_dk"])
	m, tu, nv = c.rect_polar(ang, -du / 2 - 1, du / 2 + 1, r1 - 3, r1, 0)
	c.paint(m, P["yel"])
	m, tu, nv = c.rect_polar(ang, -1.5, 1.5, r1 - 7, r1 - 3, 0)
	c.paint(m, P["steel_dk"])
