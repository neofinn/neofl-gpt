#!/usr/bin/env bash
#
# Compile MQL5 source on macOS using the MetaEditor inside MetaTrader 5.app's Wine container.
#
#   tools/mql5_compile.sh <path-to-.mq5>          compile one file
#   tools/mql5_compile.sh <path-to-directory>     compile every .mq5 in that directory
#
# Exit 0 only when MetaEditor reports zero errors.
#
# WHY THIS PARSES THE LOG INSTEAD OF CHECKING $?:
# MetaEditor64.exe's exit code does not indicate success. Measured on this machine:
#     0 errors, 1 warning  -> exit 1
#     2 errors, 0 warnings -> exit 0
# Trusting the exit code would report a broken build as green. The "Result:" line in the
# log is authoritative. The log is UTF-16LE and must be decoded.

set -uo pipefail

WINE_PREFIX="${WINE_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
WINE_BIN="${WINE_BIN:-/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine}"
METAEDITOR='C:\Program Files\MetaTrader 5\MetaEditor64.exe'
# Staging area inside the Wine drive; MetaEditor can only see paths under drive_c.
STAGE_WIN='C:\MQLCompile'
STAGE_UNIX="$WINE_PREFIX/drive_c/MQLCompile"

die() { printf '%s\n' "$*" >&2; exit 2; }

[ -x "$WINE_BIN" ]      || die "Wine not found: $WINE_BIN
Is MetaTrader 5.app installed in /Applications?"
[ -d "$WINE_PREFIX" ]   || die "Wine prefix not found: $WINE_PREFIX
Launch MetaTrader 5.app once to create it."

target="${1:-}"
[ -n "$target" ] || die "usage: $(basename "$0") <file.mq5|directory>"
[ -e "$target" ] || die "no such path: $target"

mkdir -p "$STAGE_UNIX"

# Stage the source next to its siblings so #include "..." resolves. Per the NeoFL
# single-folder packaging rule, an EA and its .mqh files live in one directory.
sources=()
if [ -d "$target" ]; then
    src_dir="$target"
    # macOS ships bash 3.2, which has no `mapfile`; read the list portably.
    while IFS= read -r f; do sources+=("$f"); done < <(find "$target" -maxdepth 1 -name '*.mq5' | sort)
    [ "${#sources[@]}" -gt 0 ] || die "no .mq5 files in $target"
else
    src_dir="$(dirname "$target")"
    sources=("$target")
fi

# Decide what to stage.
#
# A deployment package is flat (canon: EA + every required .mqh in ONE folder), so
# staging that one directory is enough. But CORE modules are organised into sibling
# directories during development and include each other with "../Other/File.mqh".
# Those need the parent tree staged, or the include cannot resolve.
if grep -rqs '#include[[:space:]]*"\.\./' "$src_dir" 2>/dev/null; then
    stage_root="$(cd "$src_dir/.." && pwd)"
    sub="$(basename "$src_dir")"
    echo "note: cross-directory includes detected; staging parent tree $(basename "$stage_root")/"
else
    stage_root="$(cd "$src_dir" && pwd)"
    sub="."
fi

work="$STAGE_UNIX/$(basename "$stage_root")"
rm -rf "$work"; mkdir -p "$work"

# Copy the tree, preserving relative structure so "../Sibling/File.mqh" resolves.
( cd "$stage_root" && find . -type f \
    \( -name '*.mq5' -o -name '*.mqh' -o -name '*.set' \) -print0 \
  | while IFS= read -r -d '' rel; do
        mkdir -p "$work/$(dirname "$rel")"
        cp "$rel" "$work/$rel"
    done )

if [ "$sub" = "." ]; then
    work_dir="$work"
    work_win="$STAGE_WIN\\$(basename "$stage_root")"
else
    work_dir="$work/$sub"
    work_win="$STAGE_WIN\\$(basename "$stage_root")\\$sub"
fi

failed=0
for src in "${sources[@]}"; do
    name="$(basename "$src")"
    stem="${name%.mq5}"
    log_unix="$work_dir/$stem.compile.log"

    printf '\n=== compiling %s ===\n' "$name"
    WINEPREFIX="$WINE_PREFIX" WINEDEBUG=-all "$WINE_BIN" "$METAEDITOR" \
        /compile:"$work_win\\$name" /log:"$work_win\\$stem.compile.log" >/dev/null 2>&1

    # MetaEditor writes the log asynchronously; wait briefly for it to appear.
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$log_unix" ] && break; sleep 0.4; done

    if [ ! -s "$log_unix" ]; then
        echo "FAIL  $name — MetaEditor produced no log"
        failed=$((failed + 1)); continue
    fi

    text="$(iconv -f UTF-16LE -t UTF-8 "$log_unix" 2>/dev/null || cat "$log_unix")"
    printf '%s\n' "$text" | grep -E ': (error|warning) ' || true

    result="$(printf '%s\n' "$text" | grep -E '^Result:' | tail -1)"
    errors="$(printf '%s\n' "$result" | sed -nE 's/^Result: ([0-9]+) errors.*/\1/p')"
    echo "${result:-Result: (none reported)}"

    if [ "${errors:-1}" -ne 0 ] 2>/dev/null; then
        failed=$((failed + 1))
    elif [ -f "$work_dir/$stem.ex5" ]; then
        cp "$work_dir/$stem.ex5" "$src_dir/"
        echo "OK    -> $src_dir/$stem.ex5"
    else
        echo "FAIL  $name — reported 0 errors but produced no .ex5"
        failed=$((failed + 1))
    fi
done

printf '\n'
if [ "$failed" -ne 0 ]; then
    echo "BUILD FAILED — $failed file(s) did not compile cleanly"
    exit 1
fi
echo "BUILD OK"
