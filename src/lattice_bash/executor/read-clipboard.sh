#!/usr/bin/env bash
# Print the system clipboard as UTF-8 text. Best-effort across platforms.
set -u

run_clip ()
{
    if command -v timeout >/dev/null 2>&1 ; then
        timeout --kill-after=1 2 "$@"
    else
        "$@"
    fi
}

if [[ -r /dev/clipboard ]] ; then
    run_clip cat /dev/clipboard
elif command -v getclip.exe >/dev/null 2>&1 ; then
    run_clip getclip.exe
elif command -v pbpaste >/dev/null 2>&1 ; then
    run_clip pbpaste
elif command -v wl-paste >/dev/null 2>&1 ; then
    run_clip wl-paste
elif command -v xclip >/dev/null 2>&1 ; then
    run_clip xclip -selection clipboard -o
elif command -v xsel >/dev/null 2>&1 ; then
    run_clip xsel --clipboard --output
elif command -v powershell.exe >/dev/null 2>&1 ; then
    run_clip powershell.exe -NoProfile -NonInteractive -Command 'Get-Clipboard -Raw'
elif command -v pwsh >/dev/null 2>&1 ; then
    run_clip pwsh -NoProfile -NonInteractive -Command 'Get-Clipboard -Raw'
else
    exit 1
fi
