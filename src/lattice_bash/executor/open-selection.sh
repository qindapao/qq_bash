#!/usr/bin/env bash
# Open a selected `file[:line]` token from tmux.
# stdin: selection. $1: pane current directory.
set -u

spec=$(cat)
spec=${spec%$'\r'}
spec=${spec#"${spec%%[![:space:]]*}"}
spec=${spec%"${spec##*[![:space:]]}"}
base=${1:-$PWD}
line=1

# Strip common SGR escapes if a colored grep line was copied.
spec=$(printf '%s' "$spec" | sed -E 's/\x1B\[[0-9;]*[mK]//g')

# Find the last path:line-looking token anywhere in the selection. This also
# handles a copied full grep line or a prompt-prefixed line.
if [[ "$spec" =~ ([^[:space:]]+):([0-9]+)(:.*)?$ ]] ; then
    file=${BASH_REMATCH[1]}
    line=${BASH_REMATCH[2]}
else
    file=$spec
fi

[[ -n "$file" ]] || exit 1
[[ "$file" == /* ]] || file="$base/$file"

if [[ -d "$file" ]] ; then
    opener="${BASH_SOURCE[0]%/*}/open-directory.sh"
    if [[ -x "$opener" ]] ; then
        "$opener" "$file" >/dev/null 2>&1
        exit $?
    fi
    exit 1
fi

if [[ ! -f "$file" ]] ; then
    tmux set-buffer -- "$spec" 2>/dev/null || true
    tmux display-message "not a file: $file" 2>/dev/null || true
    exit 1
fi

editor=${LATTICE_EDITOR:-gvim}
if [[ "$editor" == */* ]] ; then
    if [[ ! -x "$editor" ]] ; then
        tmux display-message "editor not executable: $editor" 2>/dev/null || true
        exit 1
    fi
elif ! command -v "$editor" >/dev/null 2>&1 ; then
    tmux display-message "editor not found: $editor" 2>/dev/null || true
    exit 1
fi

# run-shell/tmux may close the command's stdio immediately. Detach the GUI and
# give it /dev/null on stdin.
if command -v setsid >/dev/null 2>&1 ; then
    nohup setsid "$editor" --remote-silent +"$line" "$file" </dev/null >/dev/null 2>&1 &
else
    nohup "$editor" --remote-silent +"$line" "$file" </dev/null >/dev/null 2>&1 &
fi
