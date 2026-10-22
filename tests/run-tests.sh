#!/usr/bin/env bash
# Acceptance suite for gh-app.
#
# §1 needs no credentials and is the part worth running in review. §2 runs only
# when the four GITHUB_APP_* variables are set, i.e. inside an avatar that has
# them, and proves the app end to end without ever printing the token:
#
#   tests/run-tests.sh                     # inside the avatar
#   tests/run-tests.sh owner/repo          # also prove git reaches that repo
#
# Exit codes: 0 all run checks passed | 1 a check failed | 2 cannot start

set -uo pipefail   # deliberately not -e: run every check, then report

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="${GH_APP_BIN:-}"
[[ -z "$G" && -x "$here/../bin/gh-app" ]] && G="$here/../bin/gh-app"
[[ -z "$G" ]] && G="$(command -v gh-app 2>/dev/null || true)"
[[ -n "$G" && -x "$G" ]] || { echo "cannot find gh-app (set GH_APP_BIN)" >&2; exit 2; }
REPO="${1:-}"

pass=0; fail=0; skip=0
ok()  { printf '  \033[32mok\033[0m    %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }
skp() { printf '  \033[33mskip\033[0m  %s\n' "$*"; skip=$((skip+1)); }
sect() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- 1. offline
sect "Arguments and fail-closed configuration (no credentials needed)"
"$G" help >/dev/null 2>&1 && ok "help exits 0" || bad "help should exit 0"

"$G" nope >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "unknown verb exits 1" || bad "unknown verb should exit 1"

"$G" exec >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "exec without a command exits 2" || bad "exec without a command should exit 2"

out="$(env -u GITHUB_APP_ORG GITHUB_APP_ID=1 GITHUB_APP_PRIVATE_KEY=x GITHUB_APP_NAME=x "$G" check 2>&1)"
grep -q 'GITHUB_APP_ORG is not set' <<<"$out" \
  && ok "a missing variable is named" || bad "a missing variable should be named: $out"

out="$(GITHUB_APP_ID=1 GITHUB_APP_PRIVATE_KEY=garbage GITHUB_APP_NAME=x GITHUB_APP_ORG=y "$G" check 2>&1)"
grep -q 'not a usable PEM' <<<"$out" \
  && ok "an unusable key fails before any request" || bad "an unusable key should fail closed: $out"

# ---------------------------------------------------------------- 2. live
sect "Live, as the configured app"
if [[ -z "${GITHUB_APP_ID:-}" || -z "${GITHUB_APP_PRIVATE_KEY:-}" || -z "${GITHUB_APP_NAME:-}" || -z "${GITHUB_APP_ORG:-}" ]]; then
  skp "GITHUB_APP_* not all set -- run this inside the avatar"
else
  out="$("$G" check 2>&1)"; rc=$?
  [[ $rc -eq 0 ]] && ok "check succeeds" || bad "check failed: $out"
  grep -Eq 'gh[sp]_[A-Za-z0-9]{20,}' <<<"$out" \
    && bad "check printed a token" || ok "check prints no token"
  grep -q '^identity .*\[bot\]' <<<"$out" && ok "identity is the app's bot" || bad "no [bot] identity in: $out"

  "$G" exec sh -c '[ -n "$GH_TOKEN" ] && [ -z "${GITHUB_APP_PRIVATE_KEY:-}" ]' \
    && ok "exec child has a token and not the key" || bad "exec child env is wrong"

  author="$("$G" exec git var GIT_AUTHOR_IDENT 2>&1)"
  [[ "$author" == *"[bot] <"*"[bot]@users.noreply.github.com>"* ]] \
    && ok "commits under exec are authored by the app" || bad "author under exec: $author"

  n="$("$G" exec gh api /installation/repositories --jq .total_count 2>&1)"
  [[ "$n" =~ ^[0-9]+$ ]] && ok "gh runs as the app ($n repositories)" || bad "gh under exec: $n"

  if [[ -n "$REPO" ]]; then
    "$G" exec git ls-remote "git@github.com:$REPO.git" HEAD >/dev/null 2>&1 \
      && ok "git reaches $REPO over the app's https credential" || bad "git ls-remote $REPO failed"
  else
    skp "no owner/repo argument -- git ls-remote not tried"
  fi
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
(( fail == 0 ))
