#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat >&2 <<'USAGE'
Usage:
  inspect_image.sh <image>

Prints basic image metadata using macOS built-in tools.
USAGE
  exit 2
fi

image="$1"
file "$image"
sips -g pixelWidth -g pixelHeight -g format -g hasAlpha "$image"
