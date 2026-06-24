#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sudo nixos-rebuild switch
"$repo_root/scripts/snapshot.sh"

printf '\nReview changes with:\n  git -C %q diff\n' "$repo_root"

