#!/usr/bin/env bash
# Refresh the cached clipboard and let the TUI status worker pick it up.
set -u

state=${LATTICE_STATE_DIR:-}
[[ -n "$state" ]] || exit 1
reader="${LATTICE_HOME:-}/executor/read-clipboard.sh"
[[ -x "$reader" ]] || exit 1

if command -v timeout >/dev/null 2>&1 ; then
    value=$(timeout --kill-after=1 3 "$reader" 2>/dev/null) || exit 1
else
    value=$("$reader" 2>/dev/null) || exit 1
fi
preview=${value//$'\n'/ }
preview=${preview//$'\r'/ }
preview=${preview//$'\t'/ }
if (( ${#preview} > 10 )) ; then
    preview="...${preview: -10}"
fi
printf '%s' "$preview" > "$state/wb-clip" || exit 1
tmux display-message 'WB_CLIP refreshed' 2>/dev/null || true
