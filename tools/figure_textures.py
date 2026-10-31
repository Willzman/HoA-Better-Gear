# Necklace and ring icons in the style of the 1.12 durability figure:
# light grey, softly shaded pieces with a dark outline, meant to be tinted
# by SetVertexColor (white / yellow / red). 32x32 BGRA TGA, bottom-left origin.
import math, struct, sys
W = H = 32
SS = 4

def ring(x, y):
    # band: annulus, plus a small gem on top (y up)
    cx, cy = 16, 14
    d = math.hypot(x - cx, (y - cy) * 1.08)
    if 7.0 <= d <= 11.5:
        return True
    if math.hypot(x - 16, y - 26.5) <= 4.2:   # gem
        return True
    return False

def necklace(x, y):
    # a rounded U of beads (the chain) with a gem pendant at the bottom
    cx, cy, rx, ry = 16, 21, 12.5, 11
    n = 13
    for i in range(n):
        a = math.radians(180 + 180 * i / (n - 1))  # left top -> bottom -> right top
        bx = cx + rx * math.cos(a)
        by = cy + ry * math.sin(a) * 1.0
        if math.hypot(x - bx, y - by) <= 1.55:
            return True
    # pendant: a gem (diamond) hanging below the lowest bead
    gx, gy = 16, 6.5
    if abs(x - gx) / 4.2 + abs(y - gy) / 5.0 <= 1:
        return True
    return False

def trinket(x, y):
    # a round medallion with a four-pointed star cut out, hanging from a loop
    cx, cy = 16, 13
    dx, dy = x - cx, y - cy
    d = math.hypot(dx, dy)
    if d <= 10.5:
        # star cutout: |dx|^0.5 + |dy|^0.5 <= k  (an astroid-like 4-point star)
        if (abs(dx) ** 0.5 + abs(dy) ** 0.5) <= 2.75 and d > 0.0:
            return False
        if d < 0.8:
            return False
        return True
    # hanging loop on top
    ld = math.hypot(x - 16, y - 26.5)
    if 2.0 <= ld <= 4.3:
        return True
    return False

def cloak(x, y):
    # a cape: narrow at the collar, flaring out to a wavy hem
    if y > 30 or y < 1:
        return False
    hw = 6.5 + (30 - y) / 28 * 9.0           # half width: 6.5 at top, 15.5 at bottom
    if abs(x - 16) > hw:
        return False
    hem = 2.2 + 1.1 * math.sin((x - 16) * 0.85)
    if y < hem:
        return False
    # rounded collar corners
    if y > 27 and abs(x - 16) > 6.5 - (y - 27) * 0.9:
        return False
    return True

def cloak_shade(x, y):
    # darker vertical folds, like cloth
    fold = 0
    for fx in (11, 16, 21):
        spread = 1.0 + (30 - y) / 28 * 1.4   # folds widen toward the hem
        fold = max(fold, math.exp(-((x - (fx + (fx - 16) * (30 - y) / 40)) ** 2) / (2 * spread ** 2)))
    return 1 - 0.28 * fold

# Where the figure's own parts sit over the cloak (1.12 DurabilityFrame.xml
# layout; x from the figure's center line, y down from its top). The cloak is
# drawn 38x44 starting 12px down. Behind these, the cloak is faded so it
# doesn't show through the half-transparent body.
BODY_RECTS = [  # (half width, top, bottom)
    (24, 6, 28),    # shoulders
    (10, 13, 35),   # chest
    (22, 21, 43),   # arms (wrists)
    (21, 28, 46),   # hands
    (14.5, 32, 60), # legs and ankles (the feet below cover the middle)
]
CLOAK_W, CLOAK_H, CLOAK_TOP = 38, 44, 12
BEHIND_ALPHA = 0.33

def cloak_cover(tx, ty_top):
    # tx, ty_top: texture position (0..32, y from the top)
    fx = tx / 32 * CLOAK_W - CLOAK_W / 2
    fy = CLOAK_TOP + ty_top / 32 * CLOAK_H
    return any(abs(fx) <= hw and top <= fy <= bottom for hw, top, bottom in BODY_RECTS)

def cloak_alpha(px, py):
    # soft edge: average the cover test around the pixel (about 2px)
    hits = n = 0
    for i in range(-2, 3):
        for j in range(-2, 3):
            n += 1
            hits += cloak_cover(px + 0.5 + i * 0.4, (31 - py) + 0.5 + j * 0.4)
    c = hits / n
    return 1 - c * (1 - BEHIND_ALPHA)

def coverage(shape, px, py, grow):
    hit = 0
    for i in range(SS):
        for j in range(SS):
            x = px + (i + .5) / SS
            y = py + (j + .5) / SS
            if grow == 0:
                hit += shape(x, y)
            else:
                hit += any(shape(x + dx, y + dy) for dx in (-grow, 0, grow) for dy in (-grow, 0, grow))
    return hit / (SS * SS)

def render(shape, path, shade=None, alpha=None):
    pixels = []
    for py in range(H):
        for px in range(W):
            fill = coverage(shape, px, py, 0)
            edge = coverage(shape, px, py, 1.3)
            a = max(fill, edge)
            if a == 0:
                pixels.append((0, 0, 0, 0))
                continue
            # light grey with a highlight toward the top-left, dark outline
            # mid/dark grey like the game's figure: about 140-190 before
            # shading, a highlight toward the top-left
            light = 0.55 + 0.20 * ((py / H) * 0.6 + (1 - px / W) * 0.4)
            if shade:
                light *= shade(px + 0.5, py + 0.5)
            f = fill / a
            v = int(255 * light * f + 25 * (1 - f))
            if alpha:
                a *= alpha(px, py)
            pixels.append((v, v, v, int(a * 255)))
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
    with open(path, 'wb') as fh:
        fh.write(header)
        fh.write(bytes(b for p in pixels for b in p))

out = sys.argv[1]
render(ring, out + '/DurabilityRing.tga')
render(necklace, out + '/DurabilityNeck.tga')
render(trinket, out + '/DurabilityTrinket.tga')
render(cloak, out + '/DurabilityCloak.tga', cloak_shade, cloak_alpha)
