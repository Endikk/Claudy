#!/usr/bin/env python3
"""Exports Claudy's look as plain data, into Design/.

The Swift sources stay the source of truth: this script reads the colours, metrics and motion of
`Theme.swift` and the mascot's frames from `ClaudyTyping.swift`, `ClaudyOverload.swift` and
`ClaudyWave.swift`, and writes them as JSON any tool can read, with the app icon as PNGs.

    python3 Scripts/export-design.py           rewrites Design/
    python3 Scripts/export-design.py --check   exits 1 when Design/ is out of date

Design/claudy.tokens.json follows the W3C Design Tokens format (2025.10).
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, 'Claudy')
OUT = os.path.join(ROOT, 'Design')


def read(path):
    with open(os.path.join(SOURCES, path), encoding='utf-8') as handle:
        return handle.read()


def hex_colour(value, opacity=None):
    colour = '#' + value.lower().rjust(6, '0')
    if opacity is not None and opacity < 1:
        colour += format(round(opacity * 255), '02x')
    return colour


def number(value):
    as_float = float(value)
    return int(as_float) if as_float.is_integer() else as_float


# ---------------------------------------------------------------------------------------------
# Theme.swift

def theme_tokens():
    source = read('Theme/Theme.swift')

    def block(name):
        start = source.index(f'enum {name}')
        depth, index = 0, source.index('{', start)
        for position in range(index, len(source)):
            if source[position] == '{':
                depth += 1
            elif source[position] == '}':
                depth -= 1
                if depth == 0:
                    return source[index:position]
        raise ValueError(name)

    accents = {
        name: {'$value': hex_colour(value)}
        for name, value in re.findall(r'case \.(\w+):\s*return Color\(hex: 0x([0-9A-Fa-f]+)\)',
                                      block('Accent'))
    }
    danger = re.search(r'static let danger = Color\(hex: 0x([0-9A-Fa-f]+)\)', source).group(1)

    pixel = {}
    for name, value, opacity in re.findall(
            r'static let (\w+) = Color\(hex: 0x([0-9A-Fa-f]+)\)(?:\.opacity\(([\d.]+)\))?',
            block('Pixel')):
        pixel[name] = {'$value': hex_colour(value, float(opacity) if opacity else None)}
    shadow_opacity = re.search(r'groundShadow = Color\.black\.opacity\(([\d.]+)\)', block('Pixel'))
    pixel['groundShadow'] = {'$value': hex_colour('000000', float(shadow_opacity.group(1)))}

    metric_source = block('Metric')
    metrics = {
        name: {'$value': f'{number(value)}px'}
        for name, value in re.findall(r'static let (\w+): CGFloat = ([\d.]+)\s*$', metric_source,
                                      re.MULTILINE)
    }
    shadow = {
        name: number(value)
        for name, value in re.findall(r'static let (\w+): (?:CGFloat|Double) = ([\d.]+)',
                                      block('Shadow'))
    }
    metrics['shadowInset'] = {
        '$value': f"{-(-(3 * shadow['radius'] + shadow['offset']) // 1):.0f}px",
        '$description': 'Transparent margin round the card where its shadow is drawn: three blur radii past the offset edge.',
    }

    springs = {
        name: {
            'response': {'$type': 'duration', '$value': {'value': number(response), 'unit': 's'}},
            'dampingFraction': {'$type': 'number', '$value': number(damping)},
        }
        for name, response, damping in re.findall(
            r'static let (\w+) = SwiftUI\.Animation\.spring\(response: ([\d.]+), dampingFraction: ([\d.]+)\)',
            block('Motion'))
    }

    return {
        '$description': "Claudy's design tokens, exported from Claudy/Theme/Theme.swift by Scripts/export-design.py. Do not edit by hand.",
        'color': {
            '$type': 'color',
            'accent': accents,
            'danger': {'$value': hex_colour(danger)},
            'pixel': pixel,
        },
        'dimension': {'$type': 'dimension', **metrics},
        'shadow': {
            'card': {
                '$type': 'shadow',
                '$value': [
                    {'color': hex_colour('000000', shadow['opacity']), 'offsetX': '0px',
                     'offsetY': f"{shadow['offset']}px", 'blur': f"{shadow['radius']}px", 'spread': '0px'},
                    {'color': hex_colour('000000', shadow['contactOpacity']), 'offsetX': '0px',
                     'offsetY': '0px', 'blur': f"{shadow['contactRadius']}px", 'spread': '0px'},
                ],
            },
        },
        'motion': {
            '$description': 'Spring animations, as SwiftUI defines them: response (seconds) and damping fraction.',
            **springs,
        },
        'threshold': {
            '$type': 'number',
            '$description': 'Fractions of a quota at which the gauge changes colour or the card strains.',
            'amber': {'$value': 0.75},
            'danger': {'$value': 0.90},
            'strain': {'$value': 0.95},
        },
        'font': {
            'design': {
                '$description': 'Rounded system design with monospaced digits wherever a number changes.',
                '$type': 'fontFamily',
                '$value': ['SF Pro Rounded', 'system-ui'],
            },
        },
    }


# ---------------------------------------------------------------------------------------------
# The mascot

def string_rows(text):
    return re.findall(r'"([^"]*)"', text)


def typing():
    source = read('Views/Components/ClaudyTyping.swift')
    poses = {}
    for name in ('resting', 'leftDown', 'rightDown'):
        match = re.search(rf'static let {name}: \[String\] = \[(.*?)\]', source, re.DOTALL)
        poses[name] = string_rows(match.group(1))
    sequence = re.search(r'static let sequence: \[Pose\] = \[(.*?)\]', source).group(1)
    duration = re.search(r'static let frameDuration: TimeInterval = ([\d.]+)', source).group(1)
    inks = dict(re.findall(r'case "(.)": return \[([^\]]*)\]', source))
    return {
        'columns': len(poses['resting'][0]),
        'rows': len(poses['resting']),
        'frameMs': round(float(duration) * 1000),
        'sequence': re.findall(r'\.(\w+)', sequence),
        'poses': poses,
    }, inks


def overload():
    source = read('Views/Components/ClaudyOverload.swift')
    origin = re.search(r'spriteOrigin = \(column: (\d+), row: (\d+)\)', source)
    durations = re.search(r'static let durations: \[Int\] = \[([^\]]*)\]', source).group(1)
    frames_text = source[source.index('static let frames'):]
    frames = [string_rows(frame) for frame in re.findall(r'\[\s*(".*?")\s*,?\s*\]', frames_text, re.DOTALL)]
    return {
        'columns': len(frames[0][0]),
        'rows': len(frames[0]),
        'spriteOrigin': {'column': int(origin.group(1)), 'row': int(origin.group(2))},
        'deadLoopCount': int(re.search(r'deadLoopCount = (\d+)', source).group(1)),
        'frameMs': [int(value) for value in durations.split(',')],
        'frames': frames,
    }


def wave():
    source = read('Views/Components/ClaudyWave.swift')
    steps = re.findall(r'\((\d+), (\d+)\),\s*// (\S+)', source)
    names = {}
    for index, _, name in steps:
        names[int(index)] = name
    frames_text = source[source.index('static let frames'):]
    frames = [string_rows(frame) for frame in re.findall(r'\[\s*(".*?")\s*,?\s*\]', frames_text, re.DOTALL)]
    return {
        'columns': int(re.search(r'static let columns = (\d+)', source).group(1)),
        'rows': int(re.search(r'static let rows = (\d+)', source).group(1)),
        'sequence': [{'frame': int(index), 'ms': int(ms)} for index, ms, _ in steps],
        'frames': [{'name': names.get(index, str(index)), 'rows': rows} for index, rows in enumerate(frames)],
    }


def palette(inks):
    """How each character of a frame is painted. `tint` is the gauge colour of the moment; the
    other entries name a token of color.pixel, stacked bottom first."""
    layers = {}
    for ink, expression in inks.items():
        parts = [part.strip() for part in expression.split(',') if part.strip()]
        layers[ink] = ['tint' if part == 'tint' else part.replace('Theme.Pixel.', 'color.pixel.')
                       for part in parts]
    return {
        '$description': "Ink of each frame character. 'tint' is the colour of the leading gauge; any other layer is a token. Layers are painted bottom first; '.' is empty.",
        'inks': dict(sorted(layers.items())),
    }


# ---------------------------------------------------------------------------------------------

# The app icon, as the asset catalogue holds it, one PNG per pixel size.
ICONS = os.path.join(SOURCES, 'Assets.xcassets', 'AppIcon.appiconset')
ICON_SIZES = {16: 'icon_16x16.png', 32: 'icon_32x32.png', 64: 'icon_32x32@2x.png',
              128: 'icon_128x128.png', 256: 'icon_256x256.png', 512: 'icon_512x512.png'}


def outputs():
    typing_frames, inks = typing()
    files = {
        'claudy.tokens.json': json.dumps(theme_tokens(), indent=2, ensure_ascii=False) + '\n',
        'mascot/palette.json': json.dumps(palette(inks), indent=2, ensure_ascii=False) + '\n',
        'mascot/typing.json': json.dumps(typing_frames, indent=2, ensure_ascii=False) + '\n',
        'mascot/overload.json': json.dumps(overload(), indent=2, ensure_ascii=False) + '\n',
        'mascot/wave.json': json.dumps(wave(), indent=2, ensure_ascii=False) + '\n',
    }
    for size, name in ICON_SIZES.items():
        with open(os.path.join(ICONS, name), 'rb') as handle:
            files[f'icon/icon-{size}.png'] = handle.read()
    return files


def main():
    check = '--check' in sys.argv
    stale = []
    for relative, content in outputs().items():
        path = os.path.join(OUT, relative)
        data = content.encode('utf-8') if isinstance(content, str) else content
        current = open(path, 'rb').read() if os.path.exists(path) else None
        if current == data:
            continue
        stale.append(relative)
        if not check:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'wb') as handle:
                handle.write(data)
    if check and stale:
        print('Design/ is out of date: ' + ', '.join(stale) + '. Run python3 Scripts/export-design.py')
        sys.exit(1)
    print('Design/ up to date' if not stale else 'wrote ' + ', '.join(stale))


if __name__ == '__main__':
    main()
