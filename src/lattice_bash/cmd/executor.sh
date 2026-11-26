# lattice/cmd/executor.sh — command transport abstraction
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[executor]++ )) && return 0

lattice_executor_target ()
{
    local spec=${1:-pane}
    case "$spec" in
    pane|auto|right|primary|'')
        lattice_tmux_ensure_executor || return 1
        printf '%s' "$LATTICE_TMUX_TARGET"
        ;;
    pane:*)
        printf '%s' "${spec#pane:}"
        ;;
    *)
        # Layout targets are policy hooks. MVP maps every pane-like target
        # to the dedicated executor discovered in this session.
        lattice_tmux_ensure_executor || return 1
        printf '%s' "$LATTICE_TMUX_TARGET"
        ;;
    esac
}

lattice_executor_open_file ()
{
    local path=$1 cmd opener=${LATTICE_OPEN_CMD%% *}
    [[ -f "$path" ]] || return 1
    if [[ "$opener" == /* ]] ; then
        [[ -x "$opener" ]] || {
            lattice_status "editor not executable: $opener" error
            return 1
        }
    elif ! command -v "$opener" >/dev/null 2>&1 ; then
        lattice_status "editor not found: $opener" error
        return 1
    fi
    # Foreground: a failure is printed and the normal prompt comes back before
    # the next action. gvim itself detaches its GUI; no shell '&' is needed.
    cmd="$LATTICE_OPEN_CMD \"\$WB_FILE\""
    lattice_executor_send "$cmd" pane || return $?
    lattice_history_add "$cmd" "$LATTICE_DIR"
    lattice_status "open: ${path##*/}" ok
    return 0
}

lattice_executor_context_write ()
{
    local selected file='' pair name value
    lattice_selected_path
    selected=$REPLY
    [[ -f "$selected" ]] && file=$selected
    {
        printf '%s\n%s\n%s\n' "$LATTICE_DIR" "$file" "$LATTICE_ROOT"
        for pair in "$@" ; do
            name=${pair%%=*}
            value=${pair#*=}
            [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
            value=${value//$'\t'/ }
            value=${value//$'\n'/ }
            printf '%s\t%s\n' "$name" "$value"
        done
    } > "$LATTICE_CONTEXT_FILE"
}

lattice_executor_send ()
{
    local cmd=$1 target_spec=${2:-pane} submit=${3:-run} target
    shift 2
    if [[ "${1:-}" == 'run' || "${1:-}" == 'insert' ]] ; then
        submit=$1
        shift
    fi
    target=$(lattice_executor_target "$target_spec") || {
        lattice_status 'no executor pane; start via lattice.sh' error
        return 1
    }

    lattice_executor_context_write "$@"
    # The command is pasted verbatim. No wrapper, no env prefix, no marker.
    lattice_tmux_send "$target" "$cmd" "$submit" || {
        lattice_status "failed sending to $target" error
        return 1
    }
    return 0
}
