#!/bin/sh
# Identity hygiene gate for a pseudonymous public repo.
# Fails if any committed author/committer identity is outside the allowlist, or if any
# pattern from an EXTERNAL denylist appears in the tree or history.
#
# The denylist is intentionally NOT committed (committing the real name to hide would
# itself leak it). Provide it via env IDENTITY_DENYLIST_FILE or a gitignored
# .identity-denylist (one regex per line). In CI, source it from a secret.
set -eu

ALLOW_NAMES="ankuper"
ALLOW_EMAILS="anton.kuper.x875@outlook.com|ankuper@users.noreply.github.com|[0-9]+\+ankuper@users.noreply.github.com"

fail=0

echo "== author/committer identities in history =="
bad=$(git log --all --format='%an|%ae|%cn|%ce' \
  | awk -F'|' -v n="$ALLOW_NAMES" -v e="$ALLOW_EMAILS" '
      $1 !~ n || $3 !~ n || $2 !~ e || $4 !~ e { print }' || true)
if [ -n "$bad" ]; then
  echo "IDENTITY LEAK: non-allowlisted git identity:" >&2
  echo "$bad" >&2
  fail=1
fi

DENYFILE="${IDENTITY_DENYLIST_FILE:-.identity-denylist}"
if [ -f "$DENYFILE" ]; then
  echo "== scanning tree + log against external denylist =="
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if git grep -niE "$pat" -- . >/dev/null 2>&1; then
      echo "IDENTITY LEAK: denylist pattern in tree: /$pat/" >&2; fail=1
    fi
    if git log --all -iE --grep="$pat" --oneline | grep -q .; then
      echo "IDENTITY LEAK: denylist pattern in commit messages: /$pat/" >&2; fail=1
    fi
  done < "$DENYFILE"
else
  echo "WARN: no denylist file ($DENYFILE) — skipping content scan." >&2
fi

# shellcheck disable=SC2015
[ "$fail" -eq 0 ] && echo "identity-audit: PASS" || { echo "identity-audit: FAIL" >&2; exit 1; }
