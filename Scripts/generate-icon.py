#!/usr/bin/env python3
"""Generates Claudy/Assets.xcassets/AppIcon.appiconset: Claudy, the pixel mascot, on the card's
dark glass, the same face the widget shows.

    pip install Pillow
    python3 Scripts/generate-icon.py
    python3 Scripts/export-design.py     # then copy the new icon into Design/

The mascot is read from Design/mascot (its resting pose, in coral), so the icon can never drift
from the sprite the app draws. Each size is drawn with whole pixels per sprite cell where it fits;
the smallest sizes are scaled down from a larger drawing. The PNGs are committed: rerun only when
the mascot or the icon style changes.
"""
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.join(ROOT, 'Design')
CATALOG = os.path.join(ROOT, 'Claudy', 'Assets.xcassets')
ICONSET = os.path.join(CATALOG, 'AppIcon.appiconset')

CORAL = (0xD9, 0x77, 0x57, 255)
TOP = (0x2A, 0x27, 0x25)       # background, top left
BOTTOM = (0x12, 0x10, 0x0F)    # background, bottom right


def load(name):
    with open(os.path.join(DESIGN, name), encoding='utf-8') as handle:
        return json.load(handle)


def rgba(hex_value):
    digits = hex_value.lstrip('#')
    channels = [int(digits[index:index + 2], 16) for index in range(0, len(digits), 2)]
    return tuple(channels + [255] * (4 - len(channels)))


def over(top, bottom):
    """`top` painted over `bottom`, as the app stacks an ink's layers."""
    alpha, below = top[3] / 255, bottom[3] / 255
    out = alpha + below * (1 - alpha)
    if out == 0:
        return (0, 0, 0, 0)
    mix = [round((top[i] * alpha + bottom[i] * below * (1 - alpha)) / out) for i in range(3)]
    return tuple(mix + [round(out * 255)])


def inks():
    tokens = load('claudy.tokens.json')['color']['pixel']
    palette = load('mascot/palette.json')['inks']
    colours = {}
    for ink, layers in palette.items():
        colour = None
        for layer in layers:
            paint = CORAL if layer == 'tint' else rgba(tokens[layer.split('.')[-1]]['$value'])
            colour = paint if colour is None else over(paint, colour)
        colours[ink] = colour
    return colours


def background(side):
    """The macOS icon grid: a 824/1024 rounded square, the card's dark gradient, a coral halo."""
    inset = round(side * 100 / 1024)
    inner = side - 2 * inset
    corner = round(side * 185 / 1024)

    gradient = Image.new('RGBA', (side, side))
    pixels = gradient.load()
    halo_radius = inner * 0.55
    centre = side / 2
    for y in range(side):
        for x in range(side):
            t = ((x - inset) + (y - inset)) / (2 * inner)
            t = min(max(t, 0), 1)
            base = [TOP[i] + (BOTTOM[i] - TOP[i]) * t for i in range(3)]
            distance = ((x + 0.5 - centre) ** 2 + (y + 0.5 - centre) ** 2) ** 0.5
            glow = max(0.0, 1 - distance / halo_radius) * 0.32
            colour = [round(base[i] + (CORAL[i] - base[i]) * glow) for i in range(3)]
            pixels[x, y] = tuple(colour + [255])

    mask = Image.new('L', (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, side - inset - 1, side - inset - 1),
                                           radius=corner, fill=255)
    gradient.putalpha(mask)
    return gradient, inset, inner


def draw(side, rows, colours):
    icon, inset, inner = background(side)
    columns = len(rows[0])
    # The mascot spans about two thirds of the square, in whole pixels per cell.
    cell = max(1, int(inner * 0.66 / columns))
    width, height = columns * cell, len(rows) * cell
    left = inset + (inner - width) // 2
    top = inset + (inner - height) // 2 + cell  # a hair low: the desk sits, the head floats
    sprite = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas = ImageDraw.Draw(sprite)
    for row, line in enumerate(rows):
        for column, ink in enumerate(line):
            if ink == '.' or ink not in colours:
                continue
            x, y = left + column * cell, top + row * cell
            canvas.rectangle((x, y, x + cell - 1, y + cell - 1), fill=colours[ink])
    return Image.alpha_composite(icon, sprite)


def render(pixels, rows, colours):
    # Below 4 pixels per cell the sprite cannot keep its shape: draw large, then scale down.
    if pixels * 0.66 * 824 / 1024 / len(rows[0]) >= 4:
        return draw(pixels, rows, colours)
    return draw(1024, rows, colours).resize((pixels, pixels), Image.LANCZOS)


def main():
    rows = load('mascot/typing.json')['poses']['resting']
    colours = inks()
    os.makedirs(ICONSET, exist_ok=True)
    images = []
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f'icon_{size}x{size}.png' if scale == 1 else f'icon_{size}x{size}@2x.png'
            render(size * scale, rows, colours).save(os.path.join(ICONSET, name), optimize=True)
            images.append({'filename': name, 'idiom': 'mac', 'scale': f'{scale}x', 'size': f'{size}x{size}'})
            print('▸', name)
    with open(os.path.join(ICONSET, 'Contents.json'), 'w', encoding='utf-8') as handle:
        json.dump({'images': images, 'info': {'author': 'xcode', 'version': 1}}, handle, indent=2, sort_keys=True)
        handle.write('\n')


if __name__ == '__main__':
    main()
