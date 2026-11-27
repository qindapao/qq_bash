#!/usr/bin/env bash
# Minimal executor rc: prompt only. Commands arrive fully expanded as literals.
PROMPT_DIRTRIM=2
PS1='\[\e[1;34m\]\w\[\e[0m\]\[\e[1;32m\]\$\[\e[0m\] '

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
    "${LATTICE_EDITOR:-gvim}" --remote-silent +"$line" "$file" >/dev/null 2>&1 &
}
