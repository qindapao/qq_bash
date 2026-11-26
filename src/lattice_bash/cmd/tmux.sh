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

lattice_tmux_apply_tui_width ()
{
    [[ -n "${TMUX_PANE:-}" ]] || return 0
    local total w
    total=$(lattice_tmux_quick display-message -p -t "$TMUX_PANE" '#{window_width}' 2>/dev/null) || return 0
    [[ "$total" =~ ^[0-9]+$ ]] || return 0
    w=$(( total * 30 / 100 ))
    (( w < 24 )) && w=24
    (( w >= total - 24 )) && w=$(( total - 24 ))
    (( w < 1 )) && w=1
    lattice_tmux_quick resize-pane -t "$TMUX_PANE" -x "$w" 2>/dev/null || true
}

lattice_tmux_mouse_on ()
{
    lattice_tmux_quick set-option -g mouse on 2>/dev/null || true
    lattice_tmux_quick set-option -g set-clipboard on 2>/dev/null || true
    lattice_tmux_quick set-environment -g LATTICE_EDITOR "$LATTICE_EDITOR" 2>/dev/null || true
    # tmux has no minimum pane width. A border drag can destroy the TUI pane
    # before WINCH reaches the application, so border dragging stays off.
    lattice_tmux_quick unbind -n MouseDrag1Border 2>/dev/null || true
    # The TUI handles its own double-click; do not let tmux copy a word first.
    lattice_tmux_quick unbind -n DoubleClick1Pane 2>/dev/null || true

    # In copy mode, select file[:line] and press e. Only the executor pane gets
    # the editor action; other panes retain normal copy-selection behavior.
    lattice_tmux_quick bind -T prefix z confirm-before -p 'zoom pane? (y/n)' \
        'resize-pane -Z' 2>/dev/null || true
    # Guard the TUI and original executor from an accidental Ctrl-b x. A
    # deliberate shell exit still works; Ctrl-g is the normal whole-workbench
    # exit.
    lattice_tmux_quick bind -T prefix x if-shell -F \
        '#{m/r:^(tui|executor)$,#{@lattice_role}}' \
        'display-message "protected Lattice pane; use Ctrl-g to exit"' \
        'confirm-before -p "kill pane? (y/n)" kill-pane' \
        2>/dev/null || true

    local helper="$LATTICE_HOME/executor/open-selection.sh"
    local copier="$LATTICE_HOME/executor/copy-selection.sh"
    local table
    # Remove obsolete bindings from older Lattice versions.
    for table in copy-mode copy-mode-vi ; do
        lattice_tmux_quick unbind -T "$table" e 2>/dev/null || true
        lattice_tmux_quick bind -T "$table" MouseDragEnd1Pane \
            send-keys -X copy-pipe "$copier" \
            2>/dev/null || true
    done
    lattice_tmux_quick unbind -T prefix O 2>/dev/null || true

    # The supported editor action: copy a selection, then Ctrl-b e.
    lattice_tmux_quick bind -T prefix e run-shell \
        "tmux show-buffer | \"$helper\" #{q:pane_current_path}" \
        2>/dev/null || true
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
    printf 'LATTICE_CONTEXT_FILE=%q LATTICE_EDITOR=%q exec bash --noprofile --rcfile %q -i' \
        "$LATTICE_CONTEXT_FILE" "$LATTICE_EDITOR" "$LATTICE_EXECUTOR_RC"
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
