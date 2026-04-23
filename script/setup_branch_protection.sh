#!/usr/bin/env bash

set -euo pipefail

OWNER=""
REPO=""
BRANCH="main"
MODE="dry-run"

REQUIRED_CHECKS=(
  "PR Gate / build-and-test"
  "PR Gate / artifact-guard"
  "PR Hygiene / title-and-body-check"
)

usage() {
  cat <<'EOF'
Usage:
  script/setup_branch_protection.sh --owner <owner> --repo <repo> [--branch main] [--dry-run|--apply]

Examples:
  script/setup_branch_protection.sh --owner 37chengshan --repo DropKnow --dry-run
  script/setup_branch_protection.sh --owner 37chengshan --repo DropKnow --apply

Notes:
  - --dry-run only prints the payload.
  - --apply calls GitHub API to update branch protection.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --owner" >&2
        usage
        exit 1
      fi
      OWNER="$2"
      shift 2
      ;;
    --repo)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --repo" >&2
        usage
        exit 1
      fi
      REPO="$2"
      shift 2
      ;;
    --branch)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --branch" >&2
        usage
        exit 1
      fi
      BRANCH="$2"
      shift 2
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --apply)
      MODE="apply"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  echo "Both --owner and --repo are required." >&2
  usage
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required." >&2
  exit 1
fi

payload="$(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      {"context": "${REQUIRED_CHECKS[0]}"},
      {"context": "${REQUIRED_CHECKS[1]}"},
      {"context": "${REQUIRED_CHECKS[2]}"}
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": true
}
EOF
)"

echo "Target: ${OWNER}/${REPO} branch ${BRANCH}"

ENCODED_BRANCH="${BRANCH//\//%2F}"

if [[ "$MODE" == "dry-run" ]]; then
  echo "[DRY RUN] Branch protection payload:"
  echo "$payload"
  exit 0
fi

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/${OWNER}/${REPO}/branches/${ENCODED_BRANCH}/protection" \
  --input - <<<"$payload"

echo "Branch protection applied successfully."
echo "Reading effective protection configuration..."
gh api "repos/${OWNER}/${REPO}/branches/${ENCODED_BRANCH}/protection" || true
