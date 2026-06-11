#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat >&2 <<'USAGE'
Usage:
  verify_alpha.sh <output.png>

Fails unless the image has an alpha channel.
USAGE
  exit 2
fi

image="$1"
metadata="$(sips -g pixelWidth -g pixelHeight -g format -g hasAlpha "$image")"
file "$image"
printf '%s\n' "$metadata"
printf '%s\n' "$metadata" | grep -q 'hasAlpha: yes'
