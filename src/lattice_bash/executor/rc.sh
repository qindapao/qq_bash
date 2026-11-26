# lattice/executor/rc.sh — dedicated executor shell context hook
# The TUI writes WB_DIR/WB_FILE/WB_ROOT to LATTICE_CONTEXT_FILE before it
# pastes a command. DEBUG exports them before execution.

__lattice_context ()
{
    local dir file root name value var tmp had_params=0
    (( ${LATTICE_CONTEXT_LOADED:-0} )) && return 0
    [[ -n "${LATTICE_CONTEXT_FILE:-}" && -s "$LATTICE_CONTEXT_FILE" ]] || return 0
    {
        IFS= read -r dir
        IFS= read -r file
        IFS= read -r root
    } < "$LATTICE_CONTEXT_FILE" || true
    export WB_DIR=$dir WB_FILE=$file WB_ROOT=$root

    # Parameters are namespaced; never overwrite PATH, HOME, etc.
    for var in ${!LP_@} ; do
        unset "$var"
    done
    while IFS=$'\t' read -r name value ; do
        had_params=1
        [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        case "$name" in
        WB_DIR|WB_FILE|WB_ROOT) continue ;;
        esac
        var="LP_$name"
        printf -v "$var" '%s' "$value"
        export "$var"
    done < <(tail -n +4 "$LATTICE_CONTEXT_FILE" 2>/dev/null)

    LATTICE_CONTEXT_LOADED=1

    # Consume the one-shot parameter block. The next prompt must not inherit
    # stale values; the TUI writes a fresh block before the next command.
    if (( had_params )) ; then
        tmp=$(mktemp "${LATTICE_CONTEXT_FILE}.XXXXXX") || return 0
        printf '%s\n%s\n%s\n' "$dir" "$file" "$root" > "$tmp" || {
            rm -f -- "$tmp"
            return 0
        }
        mv -f -- "$tmp" "$LATTICE_CONTEXT_FILE" 2>/dev/null || rm -f -- "$tmp"
    fi
}

__lattice_prompt_cleanup ()
{
    local var
    for var in ${!LP_@} ; do
        unset "$var"
    done
    LATTICE_CONTEXT_LOADED=0
}

trap '__lattice_context' DEBUG
PROMPT_COMMAND="__lattice_prompt_cleanup${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
# Keep deep paths from swallowing the whole input line; Bash prints
# .../parent/leaf instead of the full absolute path.
PROMPT_DIRTRIM=2
PS1='lattice:\w\$ '

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
