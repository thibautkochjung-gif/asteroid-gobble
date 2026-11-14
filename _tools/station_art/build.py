import math, random, json
import numpy as np
from PIL import Image
from station import *
from PIL import ImageDraw


def add_far_traffic(im, seed, freighters=7):
	rng = random.Random(seed)
	d = ImageDraw.Draw(im)
	W_, H_ = im.size
	# a mothership train far off: locomotive then flatcars, a few px each
	x, y = W_ * 0.18, H_ * 0.3
	for k in range(14):
		col = (212, 163, 41) if k == 0 else (60, 58, 55)
		d.rectangle([x + k * 10, y, x + k * 10 + 7, y + 3], fill=col)
		if k:
			d.rectangle([x + k * 10 + 2, y - 1, x + k * 10 + 4, y], fill=(97, 176, 196))
	d.rectangle([x - 6, y + 1, x - 2, y + 2], fill=(245, 204, 92))
	# bulk freighters and tugs
	for _ in range(freighters):
		fx, fy = rng.uniform(0, W_), rng.uniform(0, H_)
		L = rng.choice([6, 8, 14])
		d.rectangle([fx, fy, fx + L, fy + 3], fill=(110, 105, 98))
		d.rectangle([fx - 2, fy + 1, fx - 1, fy + 2], fill=(255, 220, 140))


D = math.radians


def bbox(mask, scale=2, pad=4):
	ys, xs = np.nonzero(mask)
	return [int(xs.min() * scale - pad), int(ys.min() * scale - pad), int((xs.max() - xs.min() + 1) * scale + 2 * pad), int((ys.max() - ys.min() + 1) * scale + 2 * pad)]


def deg_of(i, n):
	return (i + 0.5) * 360 / n


def in_range(a, lo, hi):
	return lo <= a < hi


meta = {}

# ---------------- V1: the whole wheel ----------------
W, H = 640, 360
K = 2 # output px per design texel: the hub draws the station at double resolution
c = Canvas(W, H, 320, 180, K)
rng = random.Random(3)
R_in, R_out = 104, 136

# outward structures first (the ring paints over their roots)
drydock(c, 0.0, R_out + 2, 74, 40, rng)
tower(c, D(308), R_out + 2, 30, 18, rng)
for a in (D(192), D(204), D(216)):
	containers(c, a, R_out + 6, 5, 3, rng, area="market")
hangar(c, D(142), R_out + 2, 24, 24)
for a in (D(32), D(96), D(250), D(276)):
	radiator(c, a, R_out + 1, 26 if a != D(96) else 34)
for a in (D(62), D(170)):
	solar(c, a, R_out + 1, 30)
for a in (D(18), D(120), D(232), D(290), D(330), D(345)):
	antenna(c, a, R_out + 1, 9)
# spokes
for k in range(6):
	spoke(c, D(30 + k * 60), 32, R_in + 1, 9, area="undock" if k == 4 else None)
inner_rail(c, R_in - 9, 3)
for a, col in ((D(84), P["teal"]), (D(88), P["primer"]), (D(226), P["hull2"]), (D(262), P["cabin"] if "cabin" in P else P["green"]), (D(337), P["primer"]), (D(103), P["teal"]), (D(157), P["yel"])):
	parked_ship(c, a, R_out + 4, col)
parked_ship(c, D(181), R_out + 6, P["rust"], 3)


def types_v1(i, n):
	a = deg_of(i, n)
	if a < 10 or a >= 350:
		return "dock"
	if in_range(a, 298, 320):
		return "guild"
	if in_range(a, 186, 222):
		return "exchange"
	if in_range(a, 132, 152):
		return "ind"
	if in_range(a, 108, 126):
		return "scaffold"
	if in_range(a, 60, 92) or in_range(a, 232, 252):
		return "green"
	if in_range(a, 20, 48) or in_range(a, 156, 184) or in_range(a, 258, 290):
		return "ind"
	return "hab"


def area_v1(i, n):
	a = deg_of(i, n)
	if in_range(a, 298, 320):
		return "guild"
	if in_range(a, 186, 222):
		return "market"
	if in_range(a, 132, 152):
		return "mechanic"
	if a < 10 or a >= 350:
		return "shipyard"
	return None


ring(c, R_in, R_out, 26, types_v1, seed=5, area_of=area_v1, label="U-4")
# hand-placed detail
ring_text(c, "UNION RING FOUR", 90, R_in, R_out, P["yel"], P["dark"])
ring_text(c, "BERTH 6", 345 - 360 + 360, R_in, R_out, P["cream"], P["steel_dk"])
patch(c, D(292), R_in + 6, R_in + 14, 7, P["primer"])
patch(c, D(31), R_in + 18, R_in + 25, 5, P["cream"])
patch(c, D(162), R_in + 4, R_in + 10, 6, P["primer"])
gantry(c, D(204), R_out + 3, R_out + 30, 26)
dish(c, D(150.5), R_out + 1, 6)
dish(c, D(240), R_out + 1, 4)
for a in (D(30), D(90), D(150), D(210), D(270), D(330)):
	m, tu, nv = c.rect_polar(a, -7, 7, R_in - 4, R_in + 1, 0)
	c.paint(m, P["steel_dk"])
	c.paint(m & (np.mod(tu + 7, 4) < 2), P["yel"])
# bearing collar around the despun hub (part of the ring frame)
coll = (c.r >= 28) & (c.r < 33)
c.paint(coll, P["steel_dk"])
c.paint(coll & (np.mod(c.th * 40, 2) < 1), P["pipe_dk"])
c.masks["undock"] = c.masks.get("undock", np.zeros(coll.shape, bool)) | (c.r < 33)
c.outline()
c.save("v1_station")
import os as _os
GD = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), "godot_art")
_os.makedirs(GD, exist_ok=True)
Image.fromarray(c.img, "RGBA").save(f"{GD}/station.png", optimize=True)
for a in ("market", "mechanic", "shipyard", "guild", "undock"):
	mm = np.zeros((H * K, W * K, 4), np.uint8)
	mm[c.masks[a]] = (255, 255, 255, 255)
	Image.fromarray(mm, "RGBA").save(f"{GD}/area_{a}.png", optimize=True)
	c.save_highlight(a, f"../godot_art/highlight_{a}", scale=K)
for a in ("market", "mechanic", "shipyard", "guild", "undock"):
	c.save_highlight(a, f"v1_hl_{a}")
meta["v1"] = {a: bbox(c.masks[a], 2 // K) for a in ("market", "mechanic", "shipyard", "guild")}
meta["v1"]["undock"] = [640 - 70, 360 - 70, 140, 140]

# despun hub, drawn on its own so the page can turn it with the sky
h = Canvas(140, 140, 70, 70, K)
for k in range(4):
	a = k * math.pi / 2 + math.pi / 4
	m, tu, nv = h.rect_polar(a, -2.5, 2.5, 20, 62, 0)
	h.paint(m, P["steel"])
	h.paint(m & (np.mod(nv, 5) < 1), P["steel_dk"])
	h.paint(m & (nv > 60), P["red"] if k % 2 else P["scope"] if "scope" in P else P["green"])
	for j, rr in enumerate((34, 46)):
		for side in (-1, 1):
			sm, tu2, nv2 = h.rect_polar(a, (3 if side > 0 else -8), (8 if side > 0 else -3), rr, rr + 5, 0)
			h.paint(sm, [P["teal"], P["primer"], P["hull2"], P["yel"]][(k + j + side) % 4])
			h.paint(sm & (np.abs(tu2) > 6.5), P["blue"])
body = h.r < 27
h.paint(body, P["hull2"])
h.paint(body & (np.mod(h.th * 12 / math.pi, 2) < 1) & (h.r > 13), P["hull"])
for k in range(6):
	a = k * math.pi / 3
	m, tu, nv = h.rect_polar(a, -3, 3, 15, 26, 0)
	h.paint(m, P["steel_dk"])
	h.paint(m & (nv > 23), P["yel"])
	m2, _, _ = h.rect_polar(a, -1, 1, 19, 23, 0)
	h.paint(m2, P["teal"] if k % 2 else P["primer"])
hatch = h.r < 9
h.paint(hatch, P["dark"])
h.paint((h.r >= 9) & (h.r < 11), P["yel"])
h.paint((h.r >= 9) & (h.r < 11) & (np.mod(h.th * 16 / math.pi, 2) < 1), P["out"])
h.paint((h.r < 3), P["red"])
h.outline()
h.save("v1_hub")
Image.fromarray(h.img, "RGBA").save(f"{GD}/hub_core.png", optimize=True)

sky = stars_img(820, 7, 410, 410)
# The game's sky is bigger than the mockup's: it turns behind the whole window, wide screens
# included (the stage is 16:9, the window may not be). 1400 px at 2 stage px each covers windows
# up to about 3.7:1. Same density of clouds and freighters as the 820 px mockup sky.
GAME_SKY = 1400
density = (GAME_SKY / 820) ** 2
sky1 = stars_img(GAME_SKY, 7, GAME_SKY // 2, GAME_SKY // 2, scale=1, clouds=round(9 * density), wisps=round(4 * density))
add_far_traffic(sky1, 7, round(7 * density))
sky1.save(f"{GD}/sky.png", optimize=True)
add_far_traffic(sky, 7)
sky.save(f"{OUT}/v1_sky.png", optimize=True)

# nav lights and lift cars for the page
meta["v1_lights"] = [[round(x * 2), round(y * 2)] for (x, y) in nav_lights(c, R_out + 1, 16, D(11))]
meta["v1_spokes"] = [30 + k * 60 for k in range(6)]

# ---------------- V2: close on the rim, centre far below ----------------
c2 = Canvas(W, H, 320, 600)
rng = random.Random(8)
R_in2, R_out2 = 436, 500
S = 1.6  # bigger kit at this zoom


def a2(deg):
	return D(deg)


drydock(c2, a2(301), R_out2 + 2, 120, 70, rng)
tower(c2, a2(282), R_out2 + 2, 56, 28, rng)
for a in (a2(238), a2(244), a2(250)):
	containers(c2, a, R_out2 + 8, 9, 4, rng, area="market")
hangar(c2, a2(262), R_out2 + 2, 40, 40)
for a in (a2(229), a2(256), a2(292), a2(313)):
	radiator(c2, a, R_out2 + 1, 54, 12)
solar(c2, a2(270), R_out2 + 1, 70, 16)
for a in (a2(234), a2(259), a2(275), a2(288), a2(309), a2(317)):
	antenna(c2, a, R_out2 + 1, 14)
for deg in (246, 270, 294):
	spoke(c2, a2(deg), 0, R_in2 + 1, 18, area="undock" if deg == 270 else None)


def types_v2(i, n):
	a = deg_of(i, n)
	if in_range(a, 296, 306):
		return "dock"
	if in_range(a, 278, 286):
		return "guild"
	if in_range(a, 236, 252):
		return "exchange"
	if in_range(a, 258, 266):
		return "ind"
	if in_range(a, 266, 274):
		return "dock"
	if in_range(a, 286, 292) or in_range(a, 226, 232):
		return "green"
	if in_range(a, 310, 316):
		return "scaffold"
	if in_range(a, 252, 258) or in_range(a, 292, 296):
		return "ind"
	return "hab"


def area_v2(i, n):
	a = deg_of(i, n)
	if in_range(a, 278, 286):
		return "guild"
	if in_range(a, 236, 252):
		return "market"
	if in_range(a, 258, 266):
		return "mechanic"
	if in_range(a, 296, 306):
		return "shipyard"
	if in_range(a, 266, 274):
		return "undock"
	return None


inner_rail(c2, R_in2 - 16, 5)
for a, col in ((a2(225), P["teal"]), (a2(232), P["primer"]), (a2(258.5), P["teal"]), (a2(274), P["hull2"]), (a2(290.5), P["yel"]), (a2(317), P["primer"])):
	parked_ship(c2, a, R_out2 + 5, col, 2)
parked_ship(c2, a2(254), R_out2 + 8, P["rust"], 5)
ring(c2, R_in2, R_out2, 34, types_v2, seed=9, area_of=area_v2)
c2.outline()
c2.save("v2_station")
for a in ("market", "mechanic", "shipyard", "guild", "undock"):
	c2.save_highlight(a, f"v2_hl_{a}")
meta["v2"] = {a: bbox(c2.masks[a]) for a in ("market", "mechanic", "shipyard", "guild", "undock")}
meta["v2_lights"] = [[round(x * 2), round(y * 2)] for (x, y) in nav_lights(c2, R_out2 + 1, 90, D(1)) if 0 < x < W and 0 < y < H]
sky = stars_img(1300, 21, 650, 650)
add_far_traffic(sky, 21)
sky.save(f"{OUT}/v2_sky.png", optimize=True)

json.dump(meta, open(f"{OUT}/meta.json", "w"), indent=1)
print(json.dumps({k: v for k, v in meta.items() if not k.endswith("lights")}, indent=0))
