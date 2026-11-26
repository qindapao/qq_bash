#!/usr/bin/env bash
# stdin: one full tmux mouse line. $1: pane current directory.
# Scan whitespace-separated tokens from the start; open the first existing
# path[:line] or directory. Do nothing if none exists.
set -u

line=$(cat)
line=${line%$'\r'}
line=${line#"${line%%[![:space:]]*}"}
line=${line%"${line##*[![:space:]]}"}
[[ -n "$line" ]] || exit 0
line=$(printf '%s' "$line" | sed -E 's/\x1B\[[0-9;]*[mK]//g')
base=${1:-$PWD}

candidate=''
# Any POSIX whitespace separates fields, including tab and CR.
IFS=$' \t\n\r\v\f' read -ra tokens <<< "$line"
for token in "${tokens[@]}" ; do
    token=${token#[\"\'\(<\[]}
    token=${token%[\]\)>\"\',;:]}
    [[ -n "$token" ]] || continue

    path=$token
    lineno=''
    if [[ "$token" =~ ^(.+):([0-9]+)(:.*)?$ ]] ; then
        path=${BASH_REMATCH[1]}
        lineno=${BASH_REMATCH[2]}
    fi
    [[ -n "$path" ]] || continue

    check=$path
    [[ "$check" == /* ]] || check="$base/$check"
    [[ -e "$check" ]] || continue
    candidate=$path
    [[ -n "$lineno" ]] && candidate+=":$lineno"
    break
done

[[ -n "$candidate" ]] || exit 0
printf '%s' "$candidate" | "${BASH_SOURCE[0]%/*}/open-selection.sh" "$base"
