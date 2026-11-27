#!/usr/bin/env bash
# Copy system clipboard into WB_A/WB_B/WB_C. $1=A|B|C.
set -u

key=${1:-}
case "$key" in A|B|C) ;; *) exit 2 ;; esac
state=${LATTICE_STATE_DIR:-}
[[ -n "$state" ]] || exit 1
reader="${LATTICE_HOME:-}/executor/read-clipboard.sh"
[[ -x "$reader" ]] || exit 1

value_file=$(mktemp) || exit 1
if command -v timeout >/dev/null 2>&1 ; then
    timeout --kill-after=1 3 "$reader" > "$value_file" 2>/dev/null || { rm -f -- "$value_file" ; exit 1 ; }
else
    "$reader" > "$value_file" 2>/dev/null || { rm -f -- "$value_file" ; exit 1 ; }
fi
value=''
IFS= read -r -d '' value < "$value_file" || true
rm -f -- "$value_file"
preview=${value//$'\n'/ }
preview=${preview//$'\r'/ }
preview=${preview//$'\t'/ }
if (( ${#preview} > 10 )) ; then
    preview="...${preview: -10}"
fi
printf '%s' "$preview" > "$state/wb-clip" || exit 1
tmp=$(mktemp "$state/wb-register-$key.XXXXXX") || exit 1
printf '%s' "$value" > "$tmp" || { rm -f -- "$tmp" ; exit 1 ; }
mv -f -- "$tmp" "$state/wb-register-$key" || { rm -f -- "$tmp" ; exit 1 ; }
tmux display-message "WB_$key <- clipboard" 2>/dev/null || true
