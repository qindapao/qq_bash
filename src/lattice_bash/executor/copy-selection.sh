#!/usr/bin/env bash
# stdin: tmux selection. Put it in tmux's buffer and the system clipboard.
set -u
tmp=$(mktemp) || exit 1
trap 'rm -f -- "$tmp"' EXIT
cat > "$tmp"
tmux set-buffer -- "$(cat "$tmp")" 2>/dev/null || true

clip=''
if command -v clip.exe >/dev/null 2>&1 ; then
    clip=$(command -v clip.exe)
elif command -v wl-copy >/dev/null 2>&1 ; then
    clip=$(command -v wl-copy)
elif command -v xclip >/dev/null 2>&1 ; then
    clip=$(command -v xclip)
fi

if [[ -n "$clip" ]] ; then
    if [[ "$clip" == */xclip ]] ; then
        "$clip" -selection clipboard < "$tmp" >/dev/null 2>&1 || true
    else
        "$clip" < "$tmp" >/dev/null 2>&1 || true
    fi
fi
rm -f -- "$tmp"
