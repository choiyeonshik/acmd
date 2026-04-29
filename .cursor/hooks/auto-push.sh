#!/bin/bash
set -euo pipefail

# Consume hook payload without parsing to avoid blocking on stdin.
cat >/dev/null || true

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"

# Do not auto-push from detached HEAD.
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "${branch}" ]]; then
  exit 0
fi

# Run at most once per hour.
state_dir="${repo_root}/.cursor/hooks/.state"
state_file="${state_dir}/auto-push-last-run.epoch"
now_epoch="$(date +%s)"
# 3hour interval.
interval_seconds=3*3600

mkdir -p "${state_dir}"
if [[ -f "${state_file}" ]]; then
  last_epoch="$(cat "${state_file}" 2>/dev/null || echo 0)"
  if [[ "${last_epoch}" =~ ^[0-9]+$ ]]; then
    elapsed=$((now_epoch - last_epoch))
    if (( elapsed < interval_seconds )); then
      exit 0
    fi
  fi
fi

# Avoid committing obvious secret files.
if git status --porcelain | grep -Eq '(^| )(\.env($|\.|_)|.*credentials.*|.*secret.*)'; then
  exit 0
fi

# Nothing to commit.
if git diff --quiet && git diff --cached --quiet; then
  exit 0
fi

git add -A

# Exit cleanly when no staged changes remain (e.g. ignored files only).
if git diff --cached --quiet; then
  exit 0
fi

git commit -m "chore: Cursor 훅으로 변경사항 자동 반영" || exit 0
git push origin "${branch}" || exit 0
echo "${now_epoch}" > "${state_file}"
