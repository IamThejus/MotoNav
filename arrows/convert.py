"""
Convert arrow PNGs → RGB565 big-endian .bin files for GC9A01 blit_buffer.

Usage:
    pip install pillow
    python convert.py

Outputs:
    large_<name>.bin  — 80×80 px, RED   (main turn arrow)
    small_<name>.bin  — 36×36 px, GREY  (next-turn preview)

Copy all .bin files to the Pico 2 W filesystem root (or /arrows/).
"""

from PIL import Image
import struct
import os

# Map filename keyword → GraphHopper sign value (used in output filename)
SIGN_MAP = {
    'straight':       'sign_0',
    'arrow_left':     'sign_m2',
    'arrow_right':    'sign_2',
    'slight_left':    'sign_m1',
    'slight_right':   'sign_1',
    'u_turn_left':    'sign_m3',
    'u_turn_right':   'sign_3',
    'check_circle':   'sign_4',
}

# Display colors (RGB tuples) for each variant
LARGE_COLOR = (220, 40,  40)   # RED  — main arrow
SMALL_COLOR = (180, 180, 180)  # LGREY — next-turn preview


def to_rgb565_be(r, g, b):
    """Convert RGB888 → 16-bit RGB565, return as 2 big-endian bytes."""
    c = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
    return struct.pack('>H', c)


def convert(src_path, out_path, size, color):
    img = Image.open(src_path).convert('RGBA')
    img = img.resize((size, size), Image.LANCZOS)

    buf = bytearray()
    r_col, g_col, b_col = color

    for py in range(size):
        for px in range(size):
            r, g, b, a = img.getpixel((px, py))
            if a > 64:
                # Blend icon pixel with target color weighted by icon brightness
                brightness = (r + g + b) / (3 * 255)
                fr = int(r_col * brightness)
                fg = int(g_col * brightness)
                fb = int(b_col * brightness)
                # Boost: ensure the arrow is fully saturated
                fr = max(fr, int(r_col * 0.6))
                fg = max(fg, int(g_col * 0.6))
                fb = max(fb, int(b_col * 0.6))
            else:
                fr, fg, fb = 0, 0, 0  # black background
            buf += to_rgb565_be(fr, fg, fb)

    with open(out_path, 'wb') as f:
        f.write(buf)
    print(f'  {out_path}  ({len(buf)} bytes)')


def match_key(filename):
    name = os.path.basename(filename).lower()
    for keyword, sign in SIGN_MAP.items():
        if keyword in name:
            return sign
    return None


if __name__ == '__main__':
    png_files = [f for f in os.listdir('.') if f.endswith('.png')]
    if not png_files:
        print('No PNG files found. Run this script from the arrows/ folder.')
        exit(1)

    print(f'Found {len(png_files)} PNG files\n')

    for png in sorted(png_files):
        sign = match_key(png)
        if sign is None:
            print(f'  SKIP (no sign mapping): {png}')
            continue

        print(f'{png}  ->  {sign}')
        convert(png, f'large_{sign}.bin', 80, LARGE_COLOR)
        convert(png, f'small_{sign}.bin', 36, SMALL_COLOR)

    print('\nDone. Copy all .bin files to the Pico filesystem.')
    print('Suggested layout on Pico:')
    print('  /arrows/large_sign_0.bin')
    print('  /arrows/small_sign_0.bin  ... etc.')
