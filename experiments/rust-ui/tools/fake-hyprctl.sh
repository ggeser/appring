#!/usr/bin/env bash
# A stand-in for `hyprctl`, for this spike's own gallery only (never the
# main repo's tools/gallery.sh, never the real compositor): answers
# `cursorpos` and `monitors -j`, the only two things the egui/iced spikes'
# cursor-centering code calls. Point MIRQL_RING_HYPRCTL at this script's
# path; nothing calls bare `hyprctl` so it never needs to be on PATH.
set -euo pipefail
case "${1:-}" in
  cursorpos)
    echo "${FAKE_HYPRCTL_CURSOR:-1440, 900}"
    ;;
  monitors)
    cat <<'JSON'
[{"name":"HEADLESS-1","x":0,"y":0,"width":2880,"height":1800,"focused":true}]
JSON
    ;;
  *)
    echo "fake-hyprctl: unsupported command: $*" >&2
    exit 1
    ;;
esac
