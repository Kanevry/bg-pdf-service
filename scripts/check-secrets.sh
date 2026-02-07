#!/usr/bin/env bash
# Pre-Commit Secret Scanner for BG PDF Service
#
# Scans staged files for accidental secret commits.
# Compatible with macOS (bash 3.2+) and Linux.
#
# Exit Codes:
#   0 - No secrets found
#   1 - Secrets detected, commit blocked

set -eo pipefail

FOUND_SECRETS=false

# Get staged files
if git rev-parse --git-dir > /dev/null 2>&1; then
  STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
else
  echo "Not in a git repository"
  exit 0
fi

if [ -z "$STAGED_FILES" ]; then
  echo "No staged files to check"
  exit 0
fi

FILE_COUNT=$(echo "$STAGED_FILES" | wc -l | tr -d ' ')
echo "Scanning $FILE_COUNT staged file(s) for secrets..."

# Check for .env files (except .env.example)
while IFS= read -r file; do
  case "$file" in
    *.env.example|README.md|CLAUDE.md|.gitignore|pnpm-lock.yaml|package-lock.json)
      continue
      ;;
    *.env|*.env.local|*.env.production|*.env.*.local)
      echo "ERROR: Attempting to commit env file: $file"
      FOUND_SECRETS=true
      ;;
  esac
done <<< "$STAGED_FILES"

# Scan for secret patterns in staged file contents
while IFS= read -r file; do
  # Skip safe files
  case "$file" in
    *.env.example|README.md|CLAUDE.md|.gitignore|pnpm-lock.yaml|package-lock.json|LICENSE|scripts/check-secrets.sh)
      continue
      ;;
  esac

  # Skip non-existent or binary files
  [ ! -f "$file" ] && continue
  file -b "$file" 2>/dev/null | grep -q text || continue

  # Check for API keys
  if grep -qE 'sk_[a-zA-Z0-9]{20,}' "$file" 2>/dev/null; then
    echo "ERROR: Found API key (sk_) in: $file"
    FOUND_SECRETS=true
  fi

  # Check for Railway tokens
  if grep -qE 'rw_[a-zA-Z0-9]{20,}' "$file" 2>/dev/null; then
    echo "ERROR: Found Railway token (rw_) in: $file"
    FOUND_SECRETS=true
  fi

  # Check for IP addresses (skip common safe patterns like 0.0.0.0, 127.0.0.1, localhost refs)
  if grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$file" 2>/dev/null; then
    # Filter out safe IPs
    if grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$file" 2>/dev/null | \
       grep -vE '(127\.0\.0\.1|0\.0\.0\.0|localhost|255\.255|192\.168\.0\.0|10\.0\.0\.0|example)' | \
       grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then
      echo "WARNING: Found IP address in: $file"
      grep -nE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$file" | \
        grep -vE '(127\.0\.0\.1|0\.0\.0\.0|255\.255|192\.168\.0\.0|10\.0\.0\.0|example)' | head -3
      FOUND_SECRETS=true
    fi
  fi

  # Check for SSH private keys
  if grep -qE 'BEGIN.*(RSA|DSA|EC|OPENSSH).*PRIVATE KEY' "$file" 2>/dev/null; then
    echo "ERROR: Found SSH private key in: $file"
    FOUND_SECRETS=true
  fi

  # Check for password assignments
  if grep -qiE 'password[[:space:]]*[:=][[:space:]]*["\x27][^"\x27]{8,}' "$file" 2>/dev/null; then
    echo "WARNING: Found password assignment in: $file"
    FOUND_SECRETS=true
  fi

done <<< "$STAGED_FILES"

echo ""

if [ "$FOUND_SECRETS" = "true" ]; then
  echo "Secrets detected! Commit blocked."
  echo ""
  echo "Fix: Remove sensitive data, use .env.example as template."
  echo "Bypass (NOT recommended): git commit --no-verify"
  exit 1
else
  echo "No secrets detected."
  exit 0
fi
