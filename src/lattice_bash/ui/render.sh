# lattice/ui/render.sh — ANSI TUI renderer
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[render]++ )) && return 0

declare -ga LATTICE_FRAME=()
LATTICE_STTY_SAVE=${LATTICE_STTY_SAVE:-}

lattice_term_raw ()
{
    [[ -n "$LATTICE_STTY_SAVE" ]] || return 0
    stty -icanon -echo -icrnl min 1 time 0 2>/dev/null || true
}

lattice_term_restore ()
{
    [[ -n "$LATTICE_STTY_SAVE" ]] || return 0
    stty "$LATTICE_STTY_SAVE" 2>/dev/null || true
}

lattice_screen_init ()
{
    lattice_term_size
    LATTICE_STTY_SAVE=$(stty -g 2>/dev/null || true)
    lattice_term_raw
    printf '%s[?1049h%s[?25l%s[2J%s[H' \
        "$LATTICE_ESC" "$LATTICE_ESC" "$LATTICE_ESC" "$LATTICE_ESC"
}

lattice_screen_done ()
{
    lattice_term_restore
    printf '%s[0m%s[?25h%s[?1049l' \
        "$LATTICE_ESC" "$LATTICE_ESC" "$LATTICE_ESC"
}

_lattice_fit ()
{
    local s=$1 n=$2
    if (( ${#s} > n )) ; then
        REPLY=${s:0:n}
    else
        REPLY=$s
    fi
}

_lattice_row ()
{
    local text=$1
    _lattice_fit "$text" "$LATTICE_COLS"
    LATTICE_FRAME+=("$REPLY"$'\033[K\r\n')
}

_lattice_blank ()
{
    LATTICE_FRAME+=($'\033[K\r\n')
}

_lattice_footer ()
{
    local left=$1 right=$2 pad
    pad=$(( LATTICE_COLS - ${#left} - ${#right} - 1 ))
    (( pad < 0 )) && pad=0
    _lattice_fit "$left" "$(( LATTICE_COLS - ${#right} - 1 ))"
    left=$REPLY
    pad=$(( LATTICE_COLS - ${#left} - ${#right} ))
    (( pad < 0 )) && pad=0
    printf -v pad '%*s' "$pad" ''
    # The footer is the last physical row. Do not emit a newline here: a
    # trailing CRLF on the last row scrolls the terminal up by one line, which
    # pushes the header off screen on every redraw.
    LATTICE_FRAME+=("$LATTICE_C_REV$left$pad$right$LATTICE_C_RESET"$'\033[K')
}

lattice_render_tree ()
{
    local i row entry mark line
    local recent_h=3
    local title=" ${LATTICE_NAME}  ${LATTICE_DIR} "
    (( LATTICE_TREE_SEARCH )) && title+="  /${LATTICE_TREE_FILTER}"
    _lattice_row "${LATTICE_C_BOLD}${LATTICE_C_CYAN}${title}${LATTICE_C_RESET}"

    local body=$(( LATTICE_ROWS - 2 - recent_h ))
    (( body < 1 )) && body=1
    local offset=0
    (( LATTICE_SELECTED >= body )) && offset=$(( LATTICE_SELECTED - body + 1 ))

    for ((row=0;row<body;row++)); do
        i=$(( offset + row ))
        if (( i < ${#LATTICE_ENTRIES[@]} )) ; then
            entry=${LATTICE_ENTRIES[i]}
            mark=' '
            (( i == LATTICE_SELECTED )) && mark='>'
            [[ "${LATTICE_ENTRY_IS_DIR[i]}" == 1 ]] && entry="$entry/"
            _lattice_fit "$mark $entry" "$LATTICE_COLS"
            LATTICE_FRAME+=("$REPLY"$'\033[K\r\n')
        else
            _lattice_blank
        fi
    done

    # Left-bottom recent-command snapshot. Ctrl-r focuses it; 1/2/3 can rerun
    # directly from tree mode.
    local r cmd
    for ((r=0;r<recent_h;r++)); do
        cmd=${LATTICE_RECENT_CMDS[r]:-}
        if [[ -z "$cmd" ]] ; then
            if (( r == 0 )) ; then
                _lattice_fit "recent  (none)  [Ctrl-r]" "$LATTICE_COLS"
                line="$LATTICE_C_DIM$REPLY$LATTICE_C_RESET"
            else
                line=''
            fi
        else
            _lattice_fit "recent  $((r+1))  $cmd" "$LATTICE_COLS"
            if (( LATTICE_RECENT_FOCUS && r == LATTICE_RECENT_SELECTED )) ; then
                line="$LATTICE_C_REV$REPLY$LATTICE_C_RESET"
            else
                line=$REPLY
            fi
        fi
        LATTICE_FRAME+=("$line"$'\033[K\r\n')
    done

    local mode='TREE'
    [[ "$LATTICE_MODE" == 'commands' ]] && mode='COMMANDS'
    [[ "$LATTICE_MODE" == 'history' ]] && mode='HISTORY'
    _lattice_footer " ${LATTICE_STATUS:-${LATTICE_DIR}} " \
        "[$mode] j/k Ctrl-n/p Enter / : H Ctrl-r ? q/Ctrl-g "
}

lattice_render_commands ()
{
    local i row idx pos name scope target cmd line mode_label footer
    if (( LATTICE_CMD_SEARCH )) ; then
        mode_label="search /${LATTICE_CMD_QUERY}"
        footer='type filter  ↑↓/Ctrl-n/p select  Alt-↑↓ move  Ctrl-t top  Enter run  Esc back '
    else
        mode_label='list'
        footer='j/k ↑↓/Ctrl-n/p select  / search  Alt-↑↓ move  Ctrl-t top  Enter run  Esc exit '
    fi
    _lattice_row "${LATTICE_C_BOLD}${LATTICE_C_CYAN} quick commands  [${mode_label}] ${LATTICE_C_RESET}"
    local body=$(( LATTICE_ROWS - 3 ))
    (( body < 1 )) && body=1
    local offset=0
    (( LATTICE_SELECTED >= body )) && offset=$(( LATTICE_SELECTED - body + 1 ))

    for ((row=0;row<body;row++)); do
        pos=$(( offset + row ))
        if (( pos < ${#LATTICE_CMD_VIEW[@]} )) ; then
            idx=${LATTICE_CMD_VIEW[pos]}
            name=${LATTICE_CMD_NAMES[idx]}
            scope=${LATTICE_CMD_SCOPES[idx]}
            target=${LATTICE_CMD_TARGETS[idx]}
            cmd=${LATTICE_CMD_COMMANDS[idx]}
            printf -v line '%-30s %-6s %-8s %s' \
                "$name" "$scope" "$target" "$cmd"
            _lattice_fit "$line" "$LATTICE_COLS"
            if (( pos == LATTICE_SELECTED )) ; then
                line="$LATTICE_C_REV$REPLY$LATTICE_C_RESET"
            else
                line=$REPLY
            fi
            LATTICE_FRAME+=("$line"$'\033[K\r\n')
        else
            _lattice_blank
        fi
    done
    _lattice_footer " ${LATTICE_STATUS} " "$footer"
}

lattice_render_history ()
{
    local i row idx cmd line
    _lattice_row "${LATTICE_C_BOLD}${LATTICE_C_CYAN} history  /${LATTICE_HISTORY_QUERY} ${LATTICE_C_RESET}"
    local body=$(( LATTICE_ROWS - 3 ))
    (( body < 1 )) && body=1
    local offset=0
    (( LATTICE_SELECTED >= body )) && offset=$(( LATTICE_SELECTED - body + 1 ))

    for ((row=0;row<body;row++)); do
        idx=$(( offset + row ))
        if (( idx < ${#LATTICE_HISTORY_VIEW[@]} )) ; then
            i=${LATTICE_HISTORY_VIEW[idx]}
            cmd=${LATTICE_HISTORY_CMDS[i]}
            _lattice_fit "  $cmd" "$LATTICE_COLS"
            line=$REPLY
            if (( idx == LATTICE_SELECTED )) ; then
                line="$LATTICE_C_REV> ${line:2}$LATTICE_C_RESET"
            fi
            LATTICE_FRAME+=("$line"$'\033[K\r\n')
        else
            _lattice_blank
        fi
    done
    _lattice_footer " ${LATTICE_STATUS} " '[HISTORY] j/k Enter / Esc '
}

lattice_render_help ()
{
    _lattice_row "${LATTICE_C_BOLD}${LATTICE_C_CYAN} lattice help ${LATTICE_C_RESET}"
    local -a lines=(
        'j/k or arrows   move'
        'Ctrl-n/p move even while searching'
        '/               filter file and directory names'
        'Enter           enter directory / open file in gvim'
        'h / Backspace   parent directory'
        'r               refresh tree'
        '.               toggle hidden files'
        ':               quick command palette'
        '/               search commands in palette'
        '↑/↓             select command'
        'Alt-↑/↓         move command in the palette order'
        'Ctrl-t          pin selected command to the top'
        'Enter           send command; palette stays open'
        'Esc             exit palette (no direct command keys)'
        'H               command history'
        'Ctrl-r          focus recent commands (then 1/2/3 or Enter)'
        '/               search history (inside history)'
        'R               reload commands.conf'
        'q / Ctrl-g      quit and close the Lattice session'
    )
    local line
    for line in "${lines[@]}"; do
        _lattice_row "  $line"
    done
    local body=$(( LATTICE_ROWS - 3 - ${#lines[@]} ))
    while (( body-- > 0 )); do _lattice_blank; done
    _lattice_footer ' Lattice 0.1 ' '[HELP] any key '
}

lattice_render ()
{
    # Build the whole frame and write it once. Many small writes make tmux /
    # WinTerm visibly repaint between lines.
    LATTICE_FRAME=()
    LATTICE_FRAME+=($'\033[?25l\033[H')
    case "$LATTICE_MODE" in
    commands) lattice_render_commands ;;
    history)  lattice_render_history ;;
    help)     lattice_render_help ;;
    *)        lattice_render_tree ;;
    esac
    printf '%s' "${LATTICE_FRAME[@]}"
}
