#!/bin/bash
#
# Checks to run before every release. A few minutes, and a verdict at the end.
#
#   ./Scripts/preflight.sh         → on this Mac (closes Claudy for a few seconds, then reopens it)
#   ./Scripts/preflight.sh --ci    → on a CI runner, with performance budgets for a slower machine
#
# 1. The test suite.
# 2. The Release build: universal binary, signature, plist (build-app.sh).
# 3. The first read of synthetic histories (20 MB, 250 MB, 1 GB) in a Release build, as is and
#    confined to the efficiency cores, the closest this Mac comes to a slower one. Under Rosetta
#    too when it is installed, to run the Intel code.
# 4. The real app, launched on a stand-in Claude folder: the sign-in card must show within a
#    second and a half, then leave by itself once a session appears in that folder.
# 5. The Homebrew cask's style.
#
# Nobody's own data is used: histories are synthetic, the app runs on a stand-in folder with its
# log kept apart, and its preferences only change for the process through launch arguments.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/preflight"
DERIVED="$WORK/DerivedData"
ci=false
for arg in "$@"; do
    case "$arg" in
        --ci) ci=true ;;
        *) echo "unknown option: $arg (expected: --ci)" >&2; exit 1 ;;
    esac
done

# Budgets, in seconds. A CI runner is a shared virtual machine: three times the time is allowed.
scale=1
$ci && scale=3
read_budget=$((4 * scale))          # first read of 1 GB, as is
slow_read_budget=$((20 * scale))    # first read of 1 GB, efficiency cores
sign_in_budget=1.5                  # the sign-in card shows
switch_budget=15                    # the card leaves sign-in once a session appears

mkdir -p "$WORK"
summary=()
failures=0

record() {   # record <label> <value> <budget or -> <unit>
    local label="$1" value="$2" budget="$3" unit="$4" verdict="ok"
    if [[ -z "$value" ]]; then
        fail "$label (no figure)"
        return
    fi
    if [[ "$budget" != "-" ]] && awk "BEGIN { exit !($value > $budget) }"; then
        verdict="OVER BUDGET ($budget $unit)"
        failures=$((failures + 1))
    fi
    summary+=("$(printf '%-44s %8s %-3s %s' "$label" "$value" "$unit" "$verdict")")
}

fail() {
    summary+=("$(printf '%-44s %s' "$1" "FAILED")")
    failures=$((failures + 1))
}

seconds() {  # seconds <json file> <key>, empty when the key is missing
    { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; } | awk 'NF { printf "%.2f", $1 }'
}

# ── 1. Tests ─────────────────────────────────────────────────────────────────
echo "▸ tests"
if xcodebuild test -project "$ROOT/Claudy.xcodeproj" -scheme Claudy -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED/debug" > "$WORK/tests.log" 2>&1; then
    summary+=("$(printf '%-44s %s' "tests" "ok ($(grep -c "' passed" "$WORK/tests.log" || true) passed)")")
else
    fail "tests (see build/preflight/tests.log)"
fi

# ── 2. Release build ─────────────────────────────────────────────────────────
echo "▸ Release build"
if "$ROOT/Scripts/build-app.sh" > "$WORK/build.log" 2>&1; then
    summary+=("$(printf '%-44s %s' "Release build (universal, signed)" "ok")")
else
    fail "Release build (see build/preflight/build.log)"
fi
APP="$ROOT/build/Claudy.app"

# ── 3. First read of synthetic histories ─────────────────────────────────────
echo "▸ synthetic histories"
swiftc -O "$ROOT/Scripts/preflight/MakeHistory.swift" -o "$WORK/make-history"
for megabytes in 20 250 1000; do
    history="$WORK/history-$megabytes"
    # Dated from the moment they are written: past a day, they drift out of the seven days read.
    if [[ -z "$(find "$history/projects" -maxdepth 0 -mmin -720 2>/dev/null)" ]]; then
        "$WORK/make-history" "$history" "$megabytes" > /dev/null
    fi
done

echo "▸ first read, Release build"
xcodebuild build-for-testing -project "$ROOT/Claudy.xcodeproj" -scheme Claudy -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED/release" ENABLE_TESTABILITY=YES -quiet \
    > "$WORK/benchmark-build.log" 2>&1 || fail "benchmark build (see build/preflight/benchmark-build.log)"

architectures=("arm64")
[[ "$(uname -m)" == "x86_64" ]] && architectures=("x86_64")
if [[ "$(uname -m)" == "arm64" ]] && arch -x86_64 /usr/bin/true 2>/dev/null; then
    architectures+=("x86_64")
fi

for architecture in "${architectures[@]}"; do
    for megabytes in 20 250 1000; do
        report="$WORK/read-$architecture-$megabytes.json"
        rm -f "$report"
        TEST_RUNNER_CLAUDY_BENCHMARK_HISTORY="$WORK/history-$megabytes" \
        TEST_RUNNER_CLAUDY_BENCHMARK_REPORT="$report" \
        xcodebuild test-without-building -project "$ROOT/Claudy.xcodeproj" -scheme Claudy \
            -configuration Release -destination "platform=macOS,arch=$architecture" \
            -derivedDataPath "$DERIVED/release" -only-testing:ClaudyTests/ScanBenchmarkTests -quiet \
            > "$WORK/read-$architecture-$megabytes.log" 2>&1 || true
        if [[ ! -f "$report" ]]; then
            fail "first read, $megabytes MB, $architecture"
            continue
        fi
        budget="-"; slow_budget="-"
        if [[ "$megabytes" == 1000 ]]; then budget=$read_budget; slow_budget=$slow_read_budget; fi
        record "first read, $megabytes MB, $architecture" "$(seconds "$report" seconds)" "$budget" "s"
        record "  same, efficiency cores" "$(seconds "$report" efficiencySeconds)" "$slow_budget" "s"
    done
done

# ── 4. The real app on a stand-in Claude folder ──────────────────────────────
echo "▸ real app: sign-in card and automatic switch"
swiftc -O "$ROOT/Scripts/preflight/LaunchProbe.swift" -o "$WORK/launch-probe"
config="$WORK/stand-in-claude"
rm -rf "$config"
mkdir -p "$config"
ln -s "$WORK/history-250/projects" "$config/projects"

# The Claudy in use is closed for the run, then reopened from where it was: opening it by bundle
# identifier could land on the build just made instead.
running=""
if ! $ci && pgrep -x Claudy > /dev/null; then
    running="$(ps -o comm= -p "$(pgrep -x Claudy | head -1)" | sed 's|/Contents/MacOS/Claudy$||')"
    osascript -e 'quit app id "com.claudy.Claudy"' > /dev/null 2>&1 || true
    for _ in $(seq 1 20); do pgrep -x Claudy > /dev/null || break; sleep 0.5; done
fi
probe="$WORK/launch.json"
if "$WORK/launch-probe" "$APP/Contents/MacOS/Claudy" "$probe" "$config" --switch > /dev/null 2>&1 \
        && [[ -n "$(seconds "$probe" cardSeconds)" ]]; then
    record "sign-in card shows after" "$(seconds "$probe" cardSeconds)" "$sign_in_budget" "s"
    switched="$(seconds "$probe" switchSeconds)"
    if [[ -n "$switched" ]]; then
        record "card leaves sign-in, session appeared" "$switched" "$switch_budget" "s"
    else
        fail "card leaves sign-in once a session appears"
    fi
else
    fail "real app launch (see build/preflight/launch.json)"
fi
[[ -n "$running" ]] && open "$running"
# Keep this project's builds out of Launch Services: after an upgrade, brew reopens Claudy by bundle
# identifier, and Launch Services can pick any registered copy instead of the installed one.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -dump 2>/dev/null | sed -n 's|^path: *\(.*/Claudy\.app\) (0x[0-9a-f]*)$|\1|p' | sort -u \
    | while IFS= read -r copy; do
        [[ "$copy" == "$ROOT/build/"* ]] && "$lsregister" -u "$copy" > /dev/null 2>&1
    done || true

# ── 5. Homebrew cask ─────────────────────────────────────────────────────────
if command -v brew > /dev/null; then
    echo "▸ cask"
    if brew style "$ROOT/Casks/claudy.rb" > "$WORK/cask.log" 2>&1; then
        summary+=("$(printf '%-44s %s' "cask style" "ok")")
    else
        fail "cask style (see build/preflight/cask.log)"
    fi
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
echo
echo "Preflight on $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m), macOS $(sw_vers -productVersion)"
printf '%s\n' "${summary[@]}" | tee "$WORK/report.txt"
echo
if [[ $failures -gt 0 ]]; then
    echo "✗ $failures check(s) failed: do not release." | tee -a "$WORK/report.txt"
    exit 1
fi
echo "✓ ready to release." | tee -a "$WORK/report.txt"
