#!/bin/bash
#
# Checks to run before every release, with a verdict at the end.
#
#   ./Scripts/preflight.sh         → on this Mac: universal build, slow-Mac reads, the Homebrew
#                                    cask. Closes the Claudy in use for a few seconds, then reopens it.
#   ./Scripts/preflight.sh --ci    → on a CI runner: native build, budgets for a shared machine.
#
# 1. One Release build, testable, that every later step uses: binary, signature, plist checked.
# 2. The tests, and in the same run the first read of synthetic histories (20 MB to 1 GB). On this
#    Mac, again confined to the efficiency cores, and under Rosetta too when it is installed.
# 3. The real app on a stand-in Claude folder: the sign-in card must show quickly, then leave by
#    itself once a session file appears in that folder, as Claude Code writes one on sign-in.
# 4. The Homebrew cask's style, on this Mac only: the cask only changes at release time.
#
# Nobody's own data is used: histories are synthetic, the app runs on a stand-in folder with its
# log kept apart, and its preferences only change for the process through launch arguments.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/preflight"      # logs, tools and the verdict
DERIVED="$WORK/DerivedData"
# What the built app reads and writes lives outside the project. Under ~/Documents, macOS would
# ask every new build for access to that folder, and the tests would wait on the dialog.
DATA="${TMPDIR:-/tmp}/claudy-preflight"
ci=false
for arg in "$@"; do
    case "$arg" in
        --ci) ci=true ;;
        *) echo "unknown option: $arg (expected: --ci)" >&2; exit 1 ;;
    esac
done

# Budgets, in seconds. On this Mac they are the release gate. A CI runner is a shared virtual
# machine whose timings vary two to three times from one run to the next (a 1 GB read took 5.7 s,
# then 14.8 s, with the same code): there, budgets only catch a disaster.
read_budget=4          # first read of 1 GB
slow_read_budget=20    # same, efficiency cores (this Mac only)
sign_in_budget=1.5     # the sign-in card shows, over a 1 GB history it must not wait for
switch_budget=15       # the card leaves sign-in once a session appears (a 10-second timer paces it)
if $ci; then
    read_budget=60
    sign_in_budget=10
    switch_budget=30
fi

mkdir -p "$WORK" "$DATA"
summary=()
failures=0

fail() {
    summary+=("$(printf '%-44s %s' "$1" "FAILED")")
    failures=$((failures + 1))
}

record() {   # record <label> <seconds> <budget or ->
    local label="$1" value="$2" budget="$3" verdict="ok"
    if [[ -z "$value" ]]; then
        fail "$label (no figure)"
        return
    fi
    if [[ "$budget" != "-" ]] && awk "BEGIN { exit !($value > $budget) }"; then
        verdict="OVER BUDGET ($budget s)"
        failures=$((failures + 1))
    fi
    summary+=("$(printf '%-44s %8s s  %s' "$label" "$value" "$verdict")")
}

seconds() {  # seconds <json file> <key path>, empty when missing
    # plutil prints its "no value" error on standard output on some macOS versions: only a number
    # read with success counts.
    local value
    value="$(plutil -extract "$2" raw -o - "$1" 2>/dev/null)" || return 0
    [[ "$value" =~ ^[0-9.]+$ ]] && printf '%.2f' "$value"
    return 0
}

# ── 1. One build ─────────────────────────────────────────────────────────────
echo "▸ Release build"
architecture_settings=(ONLY_ACTIVE_ARCH=YES)
$ci || architecture_settings=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
if ! xcodebuild build-for-testing -project "$ROOT/Claudy.xcodeproj" -scheme Claudy -configuration Release \
        -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
        ENABLE_TESTABILITY=YES COMPILER_INDEX_STORE_ENABLE=NO "${architecture_settings[@]}" \
        > "$WORK/build.log" 2>&1; then
    fail "Release build (see build/preflight/build.log)"
    printf '%s\n' "${summary[@]}"
    exit 1
fi
APP="$DERIVED/Build/Products/Release/Claudy.app"
binary_archs="$(lipo -archs "$APP/Contents/MacOS/Claudy")"
if { $ci || [[ "$binary_archs" == *arm64* && "$binary_archs" == *x86_64* ]]; } \
        && codesign --verify --deep "$APP" 2>/dev/null \
        && plutil -lint "$APP/Contents/Info.plist" > /dev/null; then
    summary+=("$(printf '%-44s %s' "Release build ($binary_archs)" "ok")")
else
    fail "Release build: binary ($binary_archs), signature or plist"
fi

# ── 2. Tests and first reads ─────────────────────────────────────────────────
sizes=(20 250 1000)
$ci && sizes=(20 1000)
echo "▸ synthetic histories (${sizes[*]} MB)"
swiftc -O "$ROOT/Scripts/preflight/MakeHistory.swift" -o "$WORK/make-history"
histories=()
for megabytes in "${sizes[@]}"; do
    history="$DATA/history-$megabytes"
    # Dated from the moment they are written: past a day, they drift out of the seven days read.
    if [[ -z "$(find "$history/projects" -maxdepth 0 -mmin -720 2>/dev/null)" ]]; then
        "$WORK/make-history" "$history" "$megabytes" > /dev/null
    fi
    histories+=("$history")
done

architectures=("$(uname -m)")
if ! $ci && [[ "$(uname -m)" == "arm64" ]] && arch -x86_64 /usr/bin/true 2>/dev/null; then
    architectures+=("x86_64")
fi

for architecture in "${architectures[@]}"; do
    echo "▸ tests and first reads, $architecture"
    report="$DATA/reads-$architecture.json"
    log="$WORK/tests-$architecture.log"
    rm -f "$report"
    if TEST_RUNNER_CLAUDY_BENCHMARK_HISTORIES="$(IFS=:; echo "${histories[*]}")" \
       TEST_RUNNER_CLAUDY_BENCHMARK_REPORT="$report" \
       TEST_RUNNER_CLAUDY_BENCHMARK_EFFICIENCY="$($ci && echo 0 || echo 1)" \
       xcodebuild test-without-building -project "$ROOT/Claudy.xcodeproj" -scheme Claudy \
            -configuration Release -destination "platform=macOS,arch=$architecture" \
            -derivedDataPath "$DERIVED" > "$log" 2>&1; then
        summary+=("$(printf '%-44s %s' "tests, $architecture" "ok ($(grep -c "' passed" "$log" || true) passed)")")
    else
        fail "tests, $architecture (see build/preflight/tests-$architecture.log)"
    fi
    for megabytes in "${sizes[@]}"; do
        budget="-"; slow_budget="-"
        if [[ "$megabytes" == 1000 ]]; then budget=$read_budget; slow_budget=$slow_read_budget; fi
        record "first read, $megabytes MB, $architecture" "$(seconds "$report" "history-$megabytes.seconds")" "$budget"
        $ci || record "  same, efficiency cores" \
            "$(seconds "$report" "history-$megabytes.efficiencySeconds")" "$slow_budget"
    done
done

# ── 3. The real app on a stand-in Claude folder ──────────────────────────────
# GitHub's Intel Macs are virtual machines whose graphics device Metal cannot load SwiftUI's
# shaders for: any SwiftUI window aborts there, Claudy's and every released version's alike.
if [[ "$(uname -m)" == "x86_64" ]] && system_profiler SPDisplaysDataType 2>/dev/null | grep -qi paravirtual; then
    summary+=("$(printf '%-44s %s' "real app" "skipped: virtual Intel graphics, no SwiftUI")")
else
    echo "▸ real app: sign-in card and automatic switch"
    swiftc -O "$ROOT/Scripts/preflight/LaunchProbe.swift" -o "$WORK/launch-probe"
    config="$DATA/stand-in-claude"
    rm -rf "$config"
    mkdir -p "$config"
    # The largest history: a sign-in card that went back to waiting for it would miss its budget.
    ln -s "$DATA/history-1000/projects" "$config/projects"

    # The Claudy in use is closed for the run, then reopened from where it was: opening it by
    # bundle identifier could land on the build just made instead.
    running=""
    if ! $ci && pgrep -x Claudy > /dev/null; then
        running="$(ps -o comm= -p "$(pgrep -x Claudy | head -1)" | sed 's|/Contents/MacOS/Claudy$||')"
        osascript -e 'quit app id "com.claudy.Claudy"' > /dev/null 2>&1 || true
        for _ in $(seq 1 20); do pgrep -x Claudy > /dev/null || break; sleep 0.5; done
    fi
    probe="$DATA/launch.json"
    "$WORK/launch-probe" "$APP/Contents/MacOS/Claudy" "$probe" "$config" --switch > /dev/null 2>&1 || true
    record "sign-in card shows after" "$(seconds "$probe" cardSeconds)" "$sign_in_budget"
    record "card leaves sign-in, session appeared" "$(seconds "$probe" switchSeconds)" "$switch_budget"
    [[ -n "$running" ]] && open "$running"
fi

# Keep this project's builds out of Launch Services: after an upgrade, brew reopens Claudy by bundle
# identifier, and Launch Services can pick any registered copy instead of the installed one.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -dump 2>/dev/null | sed -n 's|^path: *\(.*/Claudy\.app\) (0x[0-9a-f]*)$|\1|p' | sort -u \
    | while IFS= read -r copy; do
        [[ "$copy" == "$ROOT/build/"* ]] && "$lsregister" -u "$copy" > /dev/null 2>&1
    done || true

# ── 4. Homebrew cask ─────────────────────────────────────────────────────────
if ! $ci && command -v brew > /dev/null; then
    echo "▸ cask"
    if brew style "$ROOT/Casks/claudy.rb" > "$WORK/cask.log" 2>&1; then
        summary+=("$(printf '%-44s %s' "cask style" "ok")")
    else
        fail "cask style (see build/preflight/cask.log)"
    fi
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
cp "$DATA"/*.json "$WORK"/ 2> /dev/null || true
echo
echo "Preflight on $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m), macOS $(sw_vers -productVersion)"
printf '%s\n' "${summary[@]}" | tee "$WORK/report.txt"
echo
if [[ $failures -gt 0 ]]; then
    echo "✗ $failures check(s) failed: do not release." | tee -a "$WORK/report.txt"
    exit 1
fi
echo "✓ ready to release." | tee -a "$WORK/report.txt"
