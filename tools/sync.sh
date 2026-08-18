#!/usr/bin/env bash
#
# Sync between the NeoFL rooms.
#
# Each room works in its own git worktree on its own branch, so the rooms cannot
# overwrite each other while working. `main` is the meeting point: work becomes visible
# to the other room only when it is shared there.
#
#   tools/sync.sh start           pull main into your branch, then test
#   tools/sync.sh save "message"  test, compile, commit, push YOUR branch
#   tools/sync.sh share           merge your branch into main so the other room sees it
#   tools/sync.sh status          who is where, and what is unshared
#
set -uo pipefail
cd "$(dirname "$0")/.."

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
die() { printf '\n%s\n' "$*" >&2; exit 1; }

room_name() {
  case "$(pwd)" in
    */python*) echo "Python room" ;;
    *)         echo "Infrastructure + MT5 room" ;;
  esac
}

run_tests() {
  echo "=== tests ==="
  python3 -m unittest discover -s tests -t . 2>&1 | tail -3
  python3 -m unittest discover -s tests -t . >/dev/null 2>&1 || die "Tests fail. Stopping."
}

compile_if_mql() {
  if git status --porcelain | grep -qE '\.(mq5|mqh)$'; then
    echo "=== MQL5 changed — compiling ==="
    ./tools/mql5_compile.sh DEPLOYMENTS/NeoFL_CandleRevisit_v3_86 2>&1 | grep -E "Result|BUILD"
    ./tools/mql5_compile.sh DEPLOYMENTS/NeoFL_CandleRevisit_v3_86 >/dev/null 2>&1 \
      || die "MQL5 does not compile. Stopping."
  fi
}

case "${1:-}" in
  status)
    echo "room     : $(room_name)"
    echo "branch   : $BRANCH"
    echo "worktree : $(pwd)"
    echo
    git fetch -q origin 2>/dev/null || true
    if [ "$BRANCH" = "main" ]; then
      git log --oneline -1 main
    else
      local_ahead=$(git rev-list --count origin/main.."$BRANCH" 2>/dev/null || echo 0)
      local_behind=$(git rev-list --count "$BRANCH"..origin/main 2>/dev/null || echo 0)
      echo "unshared commits (not yet in main): $local_ahead"
      echo "behind main by                    : $local_behind"
      [ "$local_ahead" != "0" ] && echo && echo "Run 'tools/sync.sh share' to publish them to the other room."
      [ "$local_behind" != "0" ] && echo "Run 'tools/sync.sh start' to pick up the other room's work."
    fi
    echo
    git status --short | head -10
    ;;

  start)
    echo "=== $(room_name) on $BRANCH — pulling the other room's work ==="
    git diff --quiet && git diff --cached --quiet \
      || die "Uncommitted changes. Run: tools/sync.sh save \"what you did\""
    git fetch -q origin
    if [ "$BRANCH" = "main" ]; then
      git pull --rebase -q origin main || die "Conflict. Resolve, then: git rebase --continue"
    else
      # Merge main IN rather than rebasing: these branches are pushed, and rebasing
      # published history rewrites commits the other room may already have.
      git merge --no-edit origin/main || die "Conflict merging main. Resolve, git add, then: git commit"
    fi
    run_tests
    echo
    echo "Up to date with main."
    ;;

  save)
    msg="${2:-}"
    [ -n "$msg" ] || die "usage: tools/sync.sh save \"commit message\""
    run_tests
    compile_if_mql
    echo "=== secret scan ==="
    git status --porcelain | awk '{print $2}' \
      | grep -iE '\.env|secret|credential|\.key$|\.pem$|assistant\.ini' \
      && die "Refusing: a filename looks like it carries secrets."
    git add -A
    git commit -q -m "$msg" || die "Nothing to commit."
    git push -q -u origin "$BRANCH"
    echo
    echo "Committed and pushed $BRANCH."
    [ "$BRANCH" = "main" ] || echo "Not visible to the other room yet — run 'tools/sync.sh share' when ready."
    ;;

  share)
    [ "$BRANCH" != "main" ] || die "Already on main; 'save' publishes directly."
    git diff --quiet && git diff --cached --quiet \
      || die "Uncommitted changes. Run: tools/sync.sh save \"what you did\""
    run_tests
    echo "=== merging $BRANCH into main ==="
    git fetch -q origin
    git checkout -q main
    git pull --rebase -q origin main
    if ! git merge --no-edit "$BRANCH"; then
      git checkout -q "$BRANCH"
      die "Conflict merging into main. Resolve on main manually, or ask the other room."
    fi
    run_tests
    git push -q origin main
    git checkout -q "$BRANCH"
    echo
    echo "Shared. The other room gets it with 'tools/sync.sh start'."
    ;;

  *)
    echo "usage: tools/sync.sh {status|start|save \"message\"|share}"
    exit 1
    ;;
esac
