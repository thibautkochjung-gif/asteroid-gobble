"""Sky textures for Asteroid Gobble's background (style of mockup 2).

Outputs, in the given folder:
- nebula_<palette>_<n>.png : transparent pixel-art nebulas (pool for NebulaField)
- stars_faint.png, stars.png, stars_bright.png, dust.png : seamless tiles
"""
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import zoom, map_coordinates, gaussian_filter

BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0

PALETTES = {
	"red": ["#07060c", "#170914", "#2c0c1e", "#4c1229", "#7a1c34", "#ab3447", "#d66673", "#f0a9ad", "#ffe6e0"],
	"violet": ["#07060c", "#0d0a1a", "#17112c", "#251a44", "#3a2a63", "#5a4389", "#8a74b4", "#b9a8dc"],
	"teal": ["#07060c", "#08111a", "#0c1e2a", "#12303d", "#1d4a55", "#336f74", "#5c9c98"],
}


def hexc(h):
	h = h.lstrip("#")
	return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def noise(scale, rng, n):
	g = rng.random((n // scale + 4, n // scale + 4))
	return zoom(g, scale, order=3)[:n, :n]


def fbm(base, octaves, rng, n, gain=0.55):
	total = np.zeros((n, n), np.float32)
	amp, norm = 1.0, 0.0
	for i in range(octaves):
		total += amp * noise(max(base >> i, 2), rng, n)
		norm += amp
		amp *= gain
	return total / norm


def warped_fbm(base, octaves, rng, n, warp):
	wx = (fbm(base * 2, 3, rng, n) - 0.5) * warp
	wy = (fbm(base * 2, 3, rng, n) - 0.5) * warp
	f = fbm(base, octaves, rng, n)
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
	return map_coordinates(f, [np.clip(yy + wy, 0, n - 1), np.clip(xx + wx, 0, n - 1)], order=1)


def nebula(rng, n, palette, lanes, warp, contrast):
	# noise scales tuned for the 2048 px mockup, rescaled to this texture size
	k = n / 2048.0
	s = lambda v: max(int(v * k), 4)
	c = (n - 1) / 2
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
	rx = n * rng.uniform(0.36, 0.42)
	ry = n * rng.uniform(0.30, 0.38)
	d2 = ((xx - c) / rx) ** 2 + ((yy - c) / ry) ** 2
	d2 = d2 * (1.0 + (fbm(s(256), 4, rng, n) - 0.5) * 1.8)
	mask = gaussian_filter(np.clip(1.0 - d2, 0, 1) ** 1.3, 40 * k)
	# hard guarantee: nothing touches the texture border
	edge = np.minimum(np.minimum(xx, n - 1 - xx), np.minimum(yy, n - 1 - yy))
	mask = mask * np.clip(edge / (n * 0.06), 0, 1)

	f = warped_fbm(s(384), 6, rng, n, warp * k)
	body = np.clip((f - 0.30) * 1.6, 0, 1)
	ridge = 1.0 - np.abs(warped_fbm(s(224), 5, rng, n, warp * 1.3 * k) - 0.5) * 2
	fil = gaussian_filter(ridge, 1.2) ** 5
	d = mask * (0.45 * body + 0.7 * fil * (0.35 + body))
	core = np.exp(-(((xx - c) / (rx * 0.35)) ** 2 + ((yy - c) / (ry * 0.30)) ** 2))
	d = d + core * body * 0.35 * mask
	if lanes:
		lane = warped_fbm(s(160), 5, rng, n, warp * k)
		d = d * (1.0 - 0.85 * np.clip((lane - 0.5) * 4, 0, 1))
	d = np.clip(d * contrast * 0.9, 0, 0.92) ** 1.25

	bayer = np.tile(BAYER, (n // 4 + 1, n // 4 + 1))[:n, :n]
	levels = len(palette)
	idx = np.clip(np.floor(d * (levels - 1) + (bayer - 0.5) * 0.9 + 0.5), 0, levels - 1).astype(int)
	pal = np.stack([hexc(col) for col in palette])
	rgba = np.zeros((n, n, 4), np.uint8)
	rgba[..., :3] = pal[idx].astype(np.uint8)
	rgba[..., 3] = np.where(idx > 0, 255, 0)
	return rgba


def star_tile(rng, n, count, bright_range, big=0.0, sparkle=0.0, tinted=True):
	img = np.zeros((n, n, 4), np.float32)
	tints = [hexc("#ffffff"), hexc("#cfe0ff"), hexc("#ffe9c4"), hexc("#ffd0d6")]

	def put(x, y, col):
		# wrap so the tile is seamless
		x %= n
		y %= n
		if img[y, x, 3] == 0 or col.sum() > img[y, x, :3].sum():
			img[y, x, :3] = col
			img[y, x, 3] = 255

	for _ in range(count):
		x = int(rng.integers(0, n))
		y = int(rng.integers(0, n))
		col = (tints[int(rng.integers(0, 4))] if tinted else tints[0]) * rng.uniform(*bright_range)
		r = rng.random()
		if r < sparkle:
			put(x, y, col)
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				put(x + dx, y + dy, col * 0.6)
			for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
				put(x + dx, y + dy, col * 0.25)
		elif r < sparkle + big:
			for dx in (0, 1):
				for dy in (0, 1):
					put(x + dx, y + dy, col * (1.0 if dx == dy == 0 else 0.7))
		else:
			put(x, y, col)
	return img.clip(0, 255).astype(np.uint8)


def dust_tile(rng, n, count, col_hex, alpha):
	img = np.zeros((n, n, 4), np.uint8)
	col = hexc(col_hex)
	for _ in range(count):
		x = int(rng.integers(0, n))
		y = int(rng.integers(0, n))
		img[y, x, :3] = (col * rng.uniform(0.7, 1.0)).astype(np.uint8)
		img[y, x, 3] = int(alpha * 255)
		if rng.random() < 0.15:
			img[y, (x + 1) % n, :3] = (col * 0.7).astype(np.uint8)
			img[y, (x + 1) % n, 3] = int(alpha * 255)
	return img


def save(arr, path):
	Image.fromarray(arr, "RGBA").save(path, optimize=True)


if __name__ == "__main__":
	out = sys.argv[1]
	rng = np.random.default_rng(2026)
	# (palette, count, size in texels, dust lanes, warp, contrast)
	pool = [("red", 4, 1408, True, 180, 1.15), ("violet", 3, 1152, False, 240, 1.0), ("teal", 3, 1024, False, 260, 1.0)]
	for name, count, size, lanes, warp, contrast in pool:
		for i in range(count):
			save(nebula(rng, size, PALETTES[name], lanes, warp, contrast), f"{out}/nebula_{name}_{i + 1}.png")
			print("nebula", name, i + 1)
	# densities match the mockup (stars per texel)
	save(star_tile(rng, 1024, 2700, (0.12, 0.35)), f"{out}/stars_faint.png")
	save(star_tile(rng, 1024, 800, (0.35, 0.75), big=0.02), f"{out}/stars.png")
	save(star_tile(rng, 1536, 180, (0.7, 1.0), big=0.25, sparkle=0.12), f"{out}/stars_bright.png")
	save(dust_tile(rng, 768, 240, "#6d6a72", 0.55), f"{out}/dust.png")
	print("tiles done")
