# Small "pop out" button icon for the character pane: a gold box with an
# arrow pointing up and out of its top-right corner, dark outline.
# Writes a 32x32 uncompressed 32-bit TGA with bottom-left origin (what the
# 1.12 client reads). Usage: python3 tools/button_textures.py HoABetterGear
import struct, sys
from PIL import Image, ImageDraw, ImageFilter

S = 8                      # supersample
N = 32 * S
GOLD = (255, 210, 0, 255)
DARK = (25, 18, 0, 255)

def draw(color, width):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = int(width * S)
    # box (open at the top-right corner, where the arrow leaves it)
    d.line([(14 * S, 7 * S), (6 * S, 7 * S), (6 * S, 26 * S), (25 * S, 26 * S), (25 * S, 18 * S)], fill=color, width=w, joint="curve")
    # arrow shaft from the middle of the box to the top-right
    d.line([(13 * S, 19 * S), (26 * S, 6 * S)], fill=color, width=w)
    # arrow head
    d.polygon([(27.5 * S, 4.5 * S), (17 * S, 5 * S), (27 * S, 15 * S)], fill=color)
    return img

outline = draw(DARK, 5.2)
fill = draw(GOLD, 2.6)
img = Image.alpha_composite(outline, fill).resize((32, 32), Image.LANCZOS)

def write_tga(img, path):
    img = img.transpose(Image.FLIP_TOP_BOTTOM)   # bottom-left origin
    px = img.load()
    data = bytearray()
    for y in range(32):
        for x in range(32):
            r, g, b, a = px[x, y]
            data += bytes((b, g, r, a))
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, 32, 32, 32, 8)
    with open(path, 'wb') as fh:
        fh.write(header + bytes(data))

write_tga(img, sys.argv[1] + "/PopOutButton.tga")
