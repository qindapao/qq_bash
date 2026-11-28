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

lattice_search_status_update ()
{
    local q=${LATTICE_CMD_QUERY:-}
    q=${q//#/##}
    lattice_tmux_quick set-option -g status-right " search> ${q}_ " 2>/dev/null || true
}

lattice_search_status_start ()
{
    [[ -n "${TMUX:-}" ]] || return 0
    LATTICE_SEARCH_STATUS_RIGHT=$(lattice_tmux_quick show-options -gv status-right 2>/dev/null) || LATTICE_SEARCH_STATUS_RIGHT=''
    LATTICE_SEARCH_STATUS_RIGHT_LENGTH=$(lattice_tmux_quick show-options -gv status-right-length 2>/dev/null) || LATTICE_SEARCH_STATUS_RIGHT_LENGTH=''
    LATTICE_SEARCH_STATUS_ACTIVE=1
    lattice_tmux_quick set-option -g status-right-length 240 2>/dev/null || true
    lattice_search_status_update
}

lattice_search_status_end ()
{
    (( LATTICE_SEARCH_STATUS_ACTIVE )) || return 0
    if [[ -n "$LATTICE_SEARCH_STATUS_RIGHT" ]] ; then
        lattice_tmux_quick set-option -g status-right "$LATTICE_SEARCH_STATUS_RIGHT" 2>/dev/null || true
    else
        lattice_tmux_quick set-option -gu status-right 2>/dev/null || true
    fi
    if [[ -n "$LATTICE_SEARCH_STATUS_RIGHT_LENGTH" ]] ; then
        lattice_tmux_quick set-option -g status-right-length "$LATTICE_SEARCH_STATUS_RIGHT_LENGTH" 2>/dev/null || true
    else
        lattice_tmux_quick set-option -gu status-right-length 2>/dev/null || true
    fi
    LATTICE_SEARCH_STATUS_ACTIVE=0
    LATTICE_SEARCH_STATUS_RIGHT=''
    LATTICE_SEARCH_STATUS_RIGHT_LENGTH=''
}

lattice_status_left_worker ()
{
    local file=$1 stop=$2 parent=$PPID last='' want base key value
    local dir file_path tag tag2
    while [[ ! -e "$stop" ]] && kill -0 "$parent" 2>/dev/null ; do
        base=''
        IFS= read -r base < "$file" 2>/dev/null || base=''
        dir=''
        file_path=''
        if [[ "$base" == DIR$'\t'* ]] ; then
            IFS=$'\t' read -r tag dir tag2 file_path <<< "$base"
        elif [[ -n "$base" ]] ; then
            # Backward-compatible read of the old one-line base format.
            dir=${base# DIR }
            if [[ "$dir" == *'  FILE '* ]] ; then
                file_path=${dir##*'  FILE '}
                dir=${dir%%'  FILE '*}
            fi
        fi

        want=''
        [[ -n "$dir" ]] && want+=" DIR $dir"
        for key in A B C ; do
            lattice_register_file "$key"
            lattice_file_preview "$REPLY" 512
            value=$REPLY
            [[ -n "$value" ]] || continue
            lattice_preview_tail "$value"
            want+="  $key $REPLY"
        done

        lattice_file_preview "$LATTICE_CLIP_CACHE_FILE" 64
        value=$REPLY
        if [[ -n "$value" ]] ; then
            want+="  CLIP $value"
        fi

        [[ -n "$file_path" ]] && want+="  FILE $file_path"

        want=${want//#/##}
        if [[ "$want" != "$last" ]] ; then
            lattice_tmux_quick set-option -g status-left "$want " 2>/dev/null || true
            last=$want
        fi
        sleep 0.15
    done
}

lattice_status_left_start ()
{
    [[ -n "${TMUX:-}" ]] || return 0
    (( LATTICE_STATUS_LEFT_SAVED )) && return 0
    LATTICE_STATUS_LEFT_ORIG=$(lattice_tmux_quick show-options -gv status-left 2>/dev/null) || LATTICE_STATUS_LEFT_ORIG=''
    LATTICE_STATUS_LEFT_LENGTH_ORIG=$(lattice_tmux_quick show-options -gv status-left-length 2>/dev/null) || LATTICE_STATUS_LEFT_LENGTH_ORIG=''
    LATTICE_STATUS_LEFT_SAVED=1
    lattice_tmux_quick set-option -g status-left-length 160 2>/dev/null || true

    # One window only: remove the window list and keep the context left/right.
    LATTICE_STATUS_FORMAT_ORIG=$(lattice_tmux_quick show-options -gv 'status-format[0]' 2>/dev/null) || LATTICE_STATUS_FORMAT_ORIG=''
    lattice_tmux_quick set-option -g 'status-format[0]' \
        '#[align=left range=left #{E:status-left-style}]#[push-default]#{T;=/#{status-left-length}:status-left}#[pop-default]#[align=right range=right #{E:status-right-style}]#[push-default]#{T;=/#{status-right-length}:status-right}#[pop-default]' \
        2>/dev/null || true

    # Put WB_ROOT in the outer terminal title, not the useless session/window label.
    LATTICE_SET_TITLES_ORIG=$(lattice_tmux_quick show-options -gv set-titles 2>/dev/null) || LATTICE_SET_TITLES_ORIG=''
    LATTICE_SET_TITLES_STRING_ORIG=$(lattice_tmux_quick show-options -gv set-titles-string 2>/dev/null) || LATTICE_SET_TITLES_STRING_ORIG=''
    if [[ -n "${LATTICE_ROOT:-}" ]] ; then
        lattice_tmux_quick set-option -g set-titles on 2>/dev/null || true
        lattice_tmux_quick set-option -g set-titles-string "${LATTICE_ROOT//#/##}" 2>/dev/null || true
    fi

    LATTICE_STATUS_LEFT_FILE="${TMPDIR:-/tmp}/lattice-status-left-${LATTICE_TMUX_SESSION:-$$}"
    LATTICE_STATUS_LEFT_STOP="${LATTICE_STATUS_LEFT_FILE}.stop"
    rm -f -- "$LATTICE_STATUS_LEFT_STOP"
    : > "$LATTICE_STATUS_LEFT_FILE"
    ( lattice_status_left_worker "$LATTICE_STATUS_LEFT_FILE" "$LATTICE_STATUS_LEFT_STOP" ) &
    LATTICE_STATUS_LEFT_PID=$!
}

lattice_status_left_update ()
{
    [[ -n "${TMUX:-}" ]] || return 0
    local dir=${LATTICE_DIR:-} file='' idx=${LATTICE_TREE_SELECTED:-0}
    local left

    if [[ -n "$dir" && -n "${LATTICE_ENTRIES[idx]:-}" ]] &&
       (( ${LATTICE_ENTRY_IS_DIR[idx]:-0} == 0 )) ; then
        file="${dir%/}/${LATTICE_ENTRIES[idx]}"
    fi
    left="DIR"$'\t'"$dir"$'\t'"FILE"$'\t'"$file"
    [[ "$left" == "$LATTICE_STATUS_LEFT_TEXT" ]] && return 0
    LATTICE_STATUS_LEFT_TEXT=$left

    [[ -n "$LATTICE_STATUS_LEFT_FILE" ]] || return 0
    printf '%s\n' "$left" > "$LATTICE_STATUS_LEFT_FILE" 2>/dev/null || true
}

lattice_status_left_end ()
{
    (( LATTICE_STATUS_LEFT_SAVED )) || return 0
    if [[ -n "$LATTICE_STATUS_LEFT_STOP" ]] ; then
        : > "$LATTICE_STATUS_LEFT_STOP"
    fi
    if [[ -n "$LATTICE_STATUS_LEFT_PID" ]] ; then
        kill "$LATTICE_STATUS_LEFT_PID" 2>/dev/null || true
        wait "$LATTICE_STATUS_LEFT_PID" 2>/dev/null || true
    fi
    [[ -n "$LATTICE_STATUS_LEFT_FILE" ]] && rm -f -- "$LATTICE_STATUS_LEFT_FILE" "$LATTICE_STATUS_LEFT_STOP"
    if [[ -n "$LATTICE_STATUS_LEFT_ORIG" ]] ; then
        lattice_tmux_quick set-option -g status-left "$LATTICE_STATUS_LEFT_ORIG" 2>/dev/null || true
    else
        lattice_tmux_quick set-option -gu status-left 2>/dev/null || true
    fi
    if [[ -n "$LATTICE_STATUS_LEFT_LENGTH_ORIG" ]] ; then
        lattice_tmux_quick set-option -g status-left-length "$LATTICE_STATUS_LEFT_LENGTH_ORIG" 2>/dev/null || true
    else
        lattice_tmux_quick set-option -gu status-left-length 2>/dev/null || true
    fi
    if [[ -n "$LATTICE_STATUS_FORMAT_ORIG" ]] ; then
        lattice_tmux_quick set-option -g 'status-format[0]' "$LATTICE_STATUS_FORMAT_ORIG" 2>/dev/null || true
    else
        lattice_tmux_quick set-option -gu 'status-format[0]' 2>/dev/null || true
    fi
    if [[ -n "$LATTICE_SET_TITLES_ORIG" ]] ; then
        lattice_tmux_quick set-option -g set-titles "$LATTICE_SET_TITLES_ORIG" 2>/dev/null || true
    else
        lattice_tmux_quick set-option -gu set-titles 2>/dev/null || true
    fi
    if [[ -n "$LATTICE_SET_TITLES_STRING_ORIG" ]] ; then
        lattice_tmux_quick set-option -g set-titles-string "$LATTICE_SET_TITLES_STRING_ORIG" 2>/dev/null || true
    else
        lattice_tmux_quick set-option -gu set-titles-string 2>/dev/null || true
    fi
    LATTICE_STATUS_LEFT_SAVED=0
    LATTICE_STATUS_LEFT_TEXT=''
    LATTICE_STATUS_LEFT_ORIG=''
    LATTICE_STATUS_LEFT_LENGTH_ORIG=''
    LATTICE_STATUS_LEFT_FILE=''
    LATTICE_STATUS_LEFT_STOP=''
    LATTICE_STATUS_LEFT_PID=''
    LATTICE_STATUS_FORMAT_ORIG=''
    LATTICE_SET_TITLES_ORIG=''
    LATTICE_SET_TITLES_STRING_ORIG=''
}

lattice_tmux_mouse_on ()
{
    lattice_tmux_quick set-option -g mouse on 2>/dev/null || true
    lattice_tmux_quick set-option -g set-clipboard on 2>/dev/null || true
    lattice_tmux_quick set-environment -g LATTICE_STATE_DIR "$LATTICE_STATE_DIR" 2>/dev/null || true
    lattice_tmux_quick set-environment -g LATTICE_HOME "$LATTICE_HOME" 2>/dev/null || true
    lattice_tmux_quick set-environment -g LATTICE_EDITOR "$LATTICE_EDITOR" 2>/dev/null || true
    local register_helper="$LATTICE_HOME/executor/copy-register.sh"
    local refresh_helper="$LATTICE_HOME/executor/refresh-clipboard.sh"
    local register_key
    for register_key in a b c ; do
        lattice_tmux_quick bind -T prefix "$register_key" run-shell -b \
            "\"$register_helper\" ${register_key^}" 2>/dev/null || true
    done
    lattice_tmux_quick bind -T prefix v run-shell -b \
        "\"$refresh_helper\"" 2>/dev/null || true
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

    # Alt/Ctrl + left-click on a visible executor line: extract the last
    # existing path[:line] and open it, without requiring a selection.
    local line_helper="$LATTICE_HOME/executor/open-line.sh"
    local mouse_key
    for mouse_key in M-MouseDown1Pane C-MouseDown1Pane ; do
        lattice_tmux_quick bind -n "$mouse_key" run-shell -b \
            "printf '%s' '#{q:mouse_line}' | \"$line_helper\" '#{q:pane_current_path}'" \
            2>/dev/null || true
    done

    # The supported editor action: copy a selection, then Ctrl-b e.
    lattice_tmux_quick bind -T prefix e run-shell -b \
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
    printf 'LATTICE_EDITOR=%q exec bash --noprofile --rcfile %q -i' \
        "$LATTICE_EDITOR" "$LATTICE_EXECUTOR_RC"
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

lattice_tmux_focus_executor ()
{
    lattice_tmux_select_executor || return 1
    lattice_tmux_quick select-pane -t "$LATTICE_TMUX_TARGET" 2>/dev/null || return 1
    return 0
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
    local target=$1 cmd=$2 submit=${3:-run}
    # If the executor is in copy/view mode, paste would be consumed by that
    # mode instead of reaching the shell prompt. Leave the mode first.
    lattice_tmux_quick copy-mode -q -t "$target" 2>/dev/null || true
    # A previous send or a manual line edit may have left text in the readline
    # buffer. A TUI command must replace that line, not append to it.
    lattice_tmux_quick send-keys -t "$target" C-a C-k 2>/dev/null || true
    # set-buffer + paste-buffer preserves special characters and avoids
    # send-keys interpreting them as key names. Bracketed paste is only needed
    # for embedded newlines; using it for ordinary one-line commands makes the
    # transport depend on the executor's readline setting, and a disabled
    # setting leaks ESC[200~/ESC[201~ into the command line.
    printf '%s' "$cmd" | lattice_tmux_quick load-buffer - 2>/dev/null || {
        lattice_tmux_quick set-buffer -- "$cmd" || return 1
    }
    if [[ "$cmd" == *$'\n'* ]] ; then
        lattice_tmux_quick paste-buffer -p -d -t "$target" || return 1
    else
        lattice_tmux_quick paste-buffer -d -t "$target" || return 1
    fi
    [[ "$submit" == 'insert' ]] && return 0
    # paste-buffer writes through the tmux server asynchronously; give the
    # executor pty one scheduling tick to consume the line before Enter.
    sleep 0.03
    lattice_tmux_quick send-keys -t "$target" Enter || return 1
    return 0
}
