"""Turns raw.json into the frames folder (text grids and PNGs) and wave.json (palette, sequence)."""
import json, os, struct, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CELL, MARGIN = 12, 24   # same format as docs/claudy-typing.gif and docs/claudy-overload.gif

raw = json.load(open(os.path.join(HERE, 'raw.json')))
W, H, names, frames = raw['w'], raw['h'], raw['names'], raw['frames']

def rgba(value):
    h = value.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16) if len(h) == 8 else 255)

palette = {ink: rgba(colour) for ink, colour in raw['pal'].items()}

def write_png(path, frame, cell, margin):
    width, height = W * cell + 2 * margin, H * cell + 2 * margin
    pixels = [[(0, 0, 0, 0)] * width for _ in range(height)]
    for r, line in enumerate(frame):
        for c, ink in enumerate(line):
            if ink == '.':
                continue
            for y in range(cell):
                row = pixels[margin + r * cell + y]
                for x in range(cell):
                    row[margin + c * cell + x] = palette[ink]
    data = b''.join(b'\x00' + bytes(v for p in row for v in p) for row in pixels)
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(data, 9)) + chunk(b'IEND', b''))

os.makedirs(os.path.join(ROOT, 'frames'), exist_ok=True)
ids = [f'{i:02d}-{name}' for i, name in enumerate(names)]
for frame_id, frame in zip(ids, frames):
    base = os.path.join(ROOT, 'frames', frame_id)
    with open(base + '.txt', 'w') as f:
        f.write('\n'.join(frame) + '\n')
    write_png(base + '.png', frame, CELL, MARGIN)
    write_png(base + '@1x.png', frame, 1, 0)

json.dump({
    'width': W, 'height': H, 'cellPixels': CELL, 'marginPixels': MARGIN,
    'palette': raw['pal'],
    'frames': ids,
    'sequence': [{'frame': ids[index], 'ms': ms} for index, ms in raw['order']],
}, open(os.path.join(ROOT, 'wave.json'), 'w'), indent=2)
print(len(ids), 'frames exported')
