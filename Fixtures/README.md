# Fixtures

What Claudy must read from Anthropic's answers, written down as plain data rather than inside the
Swift tests. `ClaudyTests/FixtureConformanceTests.swift` runs every case against the real parsers,
so a case here is always true of the app.

| Path | What it holds |
|---|---|
| `usage/<case>.json` | A `GET /api/oauth/usage` answer, as the API sends it (anonymised) |
| `usage/<case>.expected.json` | The reading Claudy takes from it at the instant `now`, or `null` when there is none |
| `plan-labels.json` | Tier fields and the plan label they read as |
| `model-names.json` | Model identifiers and the label and accent they read as |

In an expected reading, percentages are fractions (0.48 for 48 %), instants are ISO 8601 in UTC
with whole seconds, and amounts are in major units (46.31 for $46.31). A window that is absent or
`null` must not be read.

**One bug fixed, one case added.** When Anthropic's answer changes shape or a reading turns out
wrong, the fix comes with the answer that showed it, here.
