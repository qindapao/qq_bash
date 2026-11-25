# lattice/cmd/tmux.sh — tmux discovery and low-level sending
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[tmux]++ )) && return 0

LATTICE_TMUX_BIN=${LATTICE_TMUX_BIN:-}
LATTICE_TMUX_SESSION=${LATTICE_TMUX_SESSION:-lattice}
LATTICE_TMUX_TARGET=''

lattice_tmux_available ()
{
    if [[ -n "$LATTICE_TMUX_BIN" && -x "$LATTICE_TMUX_BIN" ]] ; then
        return 0
    fi
    LATTICE_TMUX_BIN=$(command -v tmux 2>/dev/null || true)
    [[ -n "$LATTICE_TMUX_BIN" ]]
}

lattice_tmux ()
{
    lattice_tmux_available || {
        lattice_status 'tmux not found (install tmux or set LATTICE_TMUX_BIN)' error
        return 1
    }
    "$LATTICE_TMUX_BIN" "$@"
}

# Non-attach tmux calls must not be able to freeze the TUI forever when the
# server is wedged. Three seconds is enough for list/split/send; attach stays
# on lattice_tmux because it is interactive.
lattice_tmux_quick ()
{
    local rc t=${LATTICE_TMUX_TIMEOUT:-3}
    lattice_tmux_available || return 1
    if command -v timeout >/dev/null 2>&1 ; then
        timeout "$t" "$LATTICE_TMUX_BIN" "$@"
        rc=$?
        ((rc == 124)) && printf 'lattice: tmux command timed out after %ss: %s\n' "$t" "$*" >&2
        return $rc
    fi
    "$LATTICE_TMUX_BIN" "$@"
}

lattice_tmux_session_exists ()
{
    lattice_tmux_quick has-session -t "$LATTICE_TMUX_SESSION" 2>/dev/null
}

lattice_tmux_has_role ()
{
    local role=$1 pane r
    while read -r pane r ; do
        [[ "$r" == "$role" ]] && return 0
    done < <(lattice_tmux_quick list-panes -t "$LATTICE_TMUX_SESSION" \
                -F '#{pane_id} #{@lattice_role}' 2>/dev/null)
    return 1
}

lattice_tmux_executor_command ()
{
    printf 'LATTICE_CONTEXT_FILE=%q exec bash --noprofile --rcfile %q -i' \
        "$LATTICE_CONTEXT_FILE" "$LATTICE_EXECUTOR_RC"
}

lattice_tmux_select_executor ()
{
    local pane role
    LATTICE_TMUX_TARGET=''
    while read -r pane role ; do
        [[ -n "$pane" ]] || continue
        if [[ "$role" == 'executor' || "$role" == 'primary' ]] ; then
            LATTICE_TMUX_TARGET=$pane
            return 0
        fi
    done < <(lattice_tmux_quick list-panes -t "$LATTICE_TMUX_SESSION" \
                -F '#{pane_id} #{@lattice_role}' 2>/dev/null)
    return 1
}

lattice_tmux_select_role ()
{
    local role=$1 pane r
    while read -r pane r ; do
        [[ "$r" == "$role" ]] || continue
        lattice_tmux_quick select-pane -t "$pane" 2>/dev/null || true
        return 0
    done < <(lattice_tmux_quick list-panes -t "$LATTICE_TMUX_SESSION" \
                -F '#{pane_id} #{@lattice_role}' 2>/dev/null)
    return 1
}

lattice_tmux_ensure_executor ()
{
    # Never split from inside the TUI. A blocked split-window client freezes
    # the whole workbench. The launcher creates both panes before respawning
    # the TUI; a missing executor is an error the TUI can report and survive.
    lattice_tmux_select_executor && return 0
    lattice_status 'no executor pane; start via lattice.sh' error
    return 1
}

lattice_tmux_mark_role ()
{
    local pane=$1 role=$2
    lattice_tmux_quick set-option -p -t "$pane" @lattice_role "$role" 2>/dev/null || true
}

lattice_tmux_send ()
{
    local target=$1 cmd=$2
    # set-buffer + paste-buffer -p preserves special characters and avoids
    # send-keys interpreting them as key names.
    printf '%s' "$cmd" | lattice_tmux_quick load-buffer - 2>/dev/null || {
        lattice_tmux_quick set-buffer -- "$cmd" || return 1
    }
    lattice_tmux_quick paste-buffer -p -d -t "$target" || return 1
    lattice_tmux_quick send-keys -t "$target" Enter || return 1
    return 0
}
