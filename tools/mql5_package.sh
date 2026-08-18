#!/usr/bin/env bash
#
# Build a self-contained MQL5 deployment package.
#
#   tools/mql5_package.sh <entry.mq5> <output-dir>
#
# Canon (hard packaging rule): every deployable EA ships as ONE folder containing the
# .mq5 and every .mqh and support file it requires. No dependency hunt across folders.
#
# Development is organised differently -- CORE modules live in sibling directories and
# include each other with "../Sibling/File.mqh". This tool bridges the two: it walks the
# include graph from the entry point, copies every dependency flat into the output
# folder, and rewrites the include paths to match. Then it compiles the result, because
# a package that has not been compiled is not known to be deployable.

set -uo pipefail

die() { printf '%s\n' "$*" >&2; exit 2; }

entry="${1:-}"
outdir="${2:-}"
[ -n "$entry" ] && [ -n "$outdir" ] || die "usage: $(basename "$0") <entry.mq5> <output-dir>"
[ -f "$entry" ] || die "no such file: $entry"

here="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$outdir"

# Walk the include graph breadth-first, copying each dependency flat.
# Quoted includes are project-relative; angle-bracket includes are MetaTrader's own
# library (<Trade/Trade.mqh>) and must be left untouched.
python3 - "$entry" "$outdir" << 'PY'
import re, shutil, sys
from pathlib import Path

entry = Path(sys.argv[1]).resolve()
outdir = Path(sys.argv[2]).resolve()
outdir.mkdir(parents=True, exist_ok=True)

QUOTED_INCLUDE = re.compile(r'#include\s+"([^"]+)"')

seen, queue, copied = set(), [entry], []

while queue:
    src = queue.pop(0)
    if src in seen:
        continue
    seen.add(src)

    text = src.read_text(encoding="utf-8")

    for rel in QUOTED_INCLUDE.findall(text):
        dep = (src.parent / rel).resolve()
        if not dep.exists():
            print(f"ERROR: {src.name} includes '{rel}' which does not exist", file=sys.stderr)
            sys.exit(1)
        # Flat packaging means two dependencies cannot share a basename.
        clash = next((s for s in seen | set(queue)
                      if s.name == dep.name and s != dep), None)
        if clash:
            print(f"ERROR: basename collision in flat package: {dep} vs {clash}", file=sys.stderr)
            sys.exit(1)
        queue.append(dep)

    # Rewrite every quoted include to a bare filename; angle-bracket ones are untouched.
    flattened = QUOTED_INCLUDE.sub(lambda m: f'#include "{Path(m.group(1)).name}"', text)
    (outdir / src.name).write_text(flattened, encoding="utf-8")
    copied.append(src.name)

print(f"packaged {len(copied)} file(s): {', '.join(sorted(copied))}")
PY
[ $? -eq 0 ] || die "packaging failed"

echo "verifying the package compiles..."
"$here/tools/mql5_compile.sh" "$outdir/$(basename "$entry")" || die "package does not compile"

echo "PACKAGE OK -> $outdir"
