# Design

Claudy's look as plain data: colours, metrics, shadow, motion and the pixel mascot.
**Generated, do not edit by hand.** The source of truth is the Swift code
(`Claudy/Theme/Theme.swift` and the mascot under `Claudy/Views/Components/`); rerun the export after
changing it:

```bash
python3 Scripts/export-design.py           # rewrites Design/
python3 Scripts/export-design.py --check   # fails when Design/ is out of date
```

| File | What it holds |
|---|---|
| `claudy.tokens.json` | Colours, dimensions, shadow, springs and gauge thresholds, in the [W3C Design Tokens](https://www.designtokens.org/) format |
| `mascot/palette.json` | How each frame character is painted: the gauge tint, a pixel token, or both stacked |
| `mascot/typing.json` | The three typing poses and their loop |
| `mascot/overload.json` | The explosion at 100 %, then the dead loop |
| `mascot/wave.json` | The wave shown when a new version is out |

Frames are rows of characters, one per pixel, `.` for empty.
