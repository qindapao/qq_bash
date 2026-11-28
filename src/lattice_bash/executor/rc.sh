#!/usr/bin/env bash
# Minimal executor rc: prompt only. Commands arrive fully expanded as literals.
PROMPT_DIRTRIM=2
PS1='\[\e[1;34m\]\w\[\e[0m\]\[\e[1;32m\]\$\[\e[0m\] '

# Lattice sends commands with tmux paste-buffer -p. The executor must opt into
# bracketed paste, otherwise the ESC[200~/ESC[201~ markers are read as text.
bind 'set enable-bracketed-paste on' 2>/dev/null || true

# Open a path or a grep-style file:line token in the editor.
eg ()
{
    local spec=${1:-} file line=1
    [[ -n "$spec" ]] || { printf 'usage: eg file[:line]\n' >&2; return 2; }
    if [[ "$spec" =~ ^(.*):([0-9]+)(:.*)?$ ]] ; then
        file=${BASH_REMATCH[1]}
        line=${BASH_REMATCH[2]}
    else
        file=$spec
    fi
    if [[ ! -f "$file" ]] ; then
        printf 'eg: not a file: %s\n' "$file" >&2
        return 1
    fi
    if [[ -z "${LATTICE_EDITOR:-}" ]] ; then
        printf 'eg: LATTICE_EDITOR is not set\n' >&2
        return 1
    fi
    case "${LATTICE_EDITOR##*/}" in
    gvim|gvim.exe)
        "${LATTICE_EDITOR}" --remote-silent +"$line" "$file" >/dev/null 2>&1 &
        ;;
    *)
        "${LATTICE_EDITOR}" +"$line" "$file"
        ;;
    esac
}
