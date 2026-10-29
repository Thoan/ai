#!/usr/bin/env bash
# Fails if a change would put personal or machine-specific info into the repo.
#   check-sensitive.sh <base> <head>   check the commits and diff between two refs (CI)
#   check-sensitive.sh --staged        check what's staged for the next commit (pre-commit hook)
# Secrets (keys, tokens) are covered separately by gitleaks and GitHub push protection.
set -euo pipefail

# Emails allowed in commit metadata and in file content.
ALLOWED_EMAIL='^([0-9]+\+)?[A-Za-z0-9-]+@users\.noreply\.github\.com$|^noreply@github\.com$|^noreply@anthropic\.com$'
EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# Local home paths (/Users/<name>, /home/<name>) and Apple device/simulator UDIDs.
HOME_PATH='/(Users|home)/[A-Za-z0-9._-]+'
UDID='[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}|[0-9A-F]{8}-[0-9A-F]{16}'

fail=0
problem() { echo "✗ $*"; fail=1; }

if [[ "${1:-}" == "--staged" ]]; then
  added="$(git diff --cached -U0 --no-color -- . ':!scripts/check-sensitive.sh' | grep '^+' | grep -v '^+++' || true)"
  # the commit's author email is checked here too, since it's about to be recorded
  email="$(git config user.email || true)"
  if [[ -n "$email" ]] && ! grep -Eq "$ALLOWED_EMAIL" <<<"$email"; then
    problem "git user.email is '$email' — use your GitHub noreply address (<id>+<login>@users.noreply.github.com)"
  fi
else
  base="${1:?usage: check-sensitive.sh <base> <head> | --staged}" head="${2:?}"
  while IFS='|' read -r sha ae ce; do
    for e in "$ae" "$ce"; do
      grep -Eq "$ALLOWED_EMAIL" <<<"$e" || problem "commit ${sha:0:7} records email '$e' — use the GitHub noreply address"
    done
  done < <(git log --format='%H|%ae|%ce' "$base..$head")
  while IFS= read -r line; do
    grep -Eq "$ALLOWED_EMAIL" <<<"$line" || problem "a commit message in $base..$head contains email '$line'"
  done < <(git log --format='%B' "$base..$head" | grep -Eo "$EMAIL" | sort -u)
  added="$(git diff -U0 --no-color "$base" "$head" -- . ':!scripts/check-sensitive.sh' | grep '^+' | grep -v '^+++' || true)"
fi

while IFS= read -r e; do
  [[ -z "$e" ]] && continue
  grep -Eq "$ALLOWED_EMAIL" <<<"$e" || problem "added content contains email '$e'"
done < <(grep -Eo "$EMAIL" <<<"$added" | sort -u || true)
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  problem "added content contains a local home path '$p' — use ~ or <repo> instead"
done < <(grep -Eo "$HOME_PATH" <<<"$added" | sort -u || true)
while IFS= read -r u; do
  [[ -z "$u" ]] && continue
  problem "added content contains a device/simulator id '$u'"
done < <(grep -Eo "$UDID" <<<"$added" | sort -u || true)

if (( fail )); then
  echo "Sensitive-info check failed. Remove the items above (or rewrite the commit) and try again."
  exit 1
fi
echo "✓ no personal emails, home paths or device ids"
