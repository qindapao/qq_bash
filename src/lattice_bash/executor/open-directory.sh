#!/usr/bin/env bash
# Open a directory in the platform's default file manager.
set -u
dir=${1:-$PWD}
[[ -d "$dir" ]] || exit 1

case "${OSTYPE:-}" in
msys*|cygwin*|mingw*)
    target=$(cygpath -w "$dir" 2>/dev/null) || target=$dir
    if command -v setsid >/dev/null 2>&1 ; then
        nohup setsid explorer.exe "$target" </dev/null >/dev/null 2>&1 &
    else
        nohup explorer.exe "$target" </dev/null >/dev/null 2>&1 &
    fi
    ;;
darwin*)
    nohup open "$dir" </dev/null >/dev/null 2>&1 &
    ;;
*)
    if command -v xdg-open >/dev/null 2>&1 ; then
        nohup xdg-open "$dir" </dev/null >/dev/null 2>&1 &
    else
        exit 1
    fi
    ;;
esac
