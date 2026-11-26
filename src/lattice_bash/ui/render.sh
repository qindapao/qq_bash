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
    printf '%s[?1049h%s[?25l%s[?1000h%s[?1006h%s[?2004h%s[2J%s[H' \
        "$LATTICE_ESC" "$LATTICE_ESC" "$LATTICE_ESC" "$LATTICE_ESC" \
        "$LATTICE_ESC" "$LATTICE_ESC" "$LATTICE_ESC"
}

lattice_screen_done ()
{
    lattice_term_restore
    printf '%s[?2004l%s[?1006l%s[?1000l%s[?25h%s[0m%s[?1049l' \
        "$LATTICE_ESC" "$LATTICE_ESC" "$LATTICE_ESC" \
        "$LATTICE_ESC" "$LATTICE_ESC" "$LATTICE_ESC"
}

_lattice_fit ()
{
    local s=$1 n=$2 width target out used ch w i
    if [[ "$s" != *[![:ascii:]]* ]] ; then
        if (( ${#s} <= n )) ; then
            REPLY=$s
        elif (( n > 3 )) ; then
            REPLY="${s:0:n-3}..."
        else
            REPLY=${s:0:n}
        fi
        return
    fi
    str_display_width "$s"; width=$REPLY
    if (( width <= n )) ; then
        REPLY=$s
        return
    fi
    if (( n > 3 )) ; then
        target=$(( n - 3 ))
    else
        target=$n
    fi
    out=''
    used=0
    for ((i=0;i<${#s};i++)); do
        ch=${s:i:1}
        case "$ch" in
        [[:ascii:]]) w=1 ;;
        *) str_display_width "$ch"; w=$REPLY ;;
        esac
        (( used + w > target )) && break
        out+=$ch
        (( used += w ))
    done
    if (( n > 3 )) ; then
        REPLY="$out..."
    else
        REPLY=$out
    fi
}

_lattice_pad ()
{
    local s=$1 width=$2 used spaces
    if [[ "$s" != *[![:ascii:]]* ]] ; then
        used=${#s}
    else
        str_display_width "$s"; used=$REPLY
    fi
    if (( used >= width )) ; then
        _lattice_fit "$s" "$width"
        return
    fi
    printf -v spaces '%*s' "$((width - used))" ''
    REPLY="$s$spaces"
}

_lattice_row ()
{
    local text=$1
    _lattice_fit "$text" "$LATTICE_COLS"
    LATTICE_FRAME+=("$LATTICE_C_RESET$REPLY$LATTICE_C_RESET"$'\033[K\r\n')
}

_lattice_blank ()
{
    LATTICE_FRAME+=($'\033[K\r\n')
}

_lattice_footer ()
{
    local left=$1 right=$2 pad max_left lw rw

    # Reserve the shortcut block first. A long status/path must never push the
    # key help off the row; only the left side gets ellipsized.
    str_display_width "$right"; rw=$REPLY
    if (( rw >= LATTICE_COLS )) ; then
        _lattice_fit "$right" "$LATTICE_COLS"
        right=$REPLY
        str_display_width "$right"; rw=$REPLY
    fi
    max_left=$(( LATTICE_COLS - rw - 1 ))
    (( max_left < 0 )) && max_left=0
    _lattice_fit "$left" "$max_left"
    left=$REPLY
    str_display_width "$left"; lw=$REPLY

    pad=$(( LATTICE_COLS - lw - rw ))
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
    local recent_h=${LATTICE_RECENT_LIMIT:-8}
    (( recent_h > LATTICE_ROWS - 3 )) && recent_h=$(( LATTICE_ROWS - 3 ))
    (( recent_h < 1 )) && recent_h=1
    local title=" ${LATTICE_NAME}  ${LATTICE_DIR} "
    (( LATTICE_TREE_SEARCH )) && title+="  /${LATTICE_TREE_FILTER}"
    _lattice_row "${LATTICE_C_BOLD}${LATTICE_C_CYAN}${title}${LATTICE_C_RESET}"

    local body=$(( LATTICE_ROWS - 2 - recent_h ))
    (( body < 1 )) && body=1
    local offset=${LATTICE_TREE_OFFSET:-0}
    local total=${#LATTICE_ENTRIES[@]}
    (( offset < 0 )) && offset=0
    (( offset > total - body )) && offset=$(( total - body ))
    (( offset < 0 )) && offset=0
    if (( LATTICE_SELECTED < offset )) ; then
        offset=$LATTICE_SELECTED
    elif (( LATTICE_SELECTED >= offset + body )) ; then
        offset=$(( LATTICE_SELECTED - body + 1 ))
    fi
    LATTICE_TREE_OFFSET=$offset
    LATTICE_TREE_BODY=$body

    for ((row=0;row<body;row++)); do
        i=$(( offset + row ))
        if (( i < ${#LATTICE_ENTRIES[@]} )) ; then
            entry=${LATTICE_ENTRIES[i]}
            mark=' '
            (( i == LATTICE_SELECTED )) && mark='>'
            [[ "${LATTICE_ENTRY_IS_DIR[i]}" == 1 ]] && entry="$entry/"
            _lattice_fit "$mark $entry" "$LATTICE_COLS"
            if (( i == LATTICE_SELECTED )) ; then
                _lattice_pad "$REPLY" "$LATTICE_COLS"
                line="$LATTICE_C_REV$REPLY$LATTICE_C_RESET"
            else
                line=$REPLY
            fi
            LATTICE_FRAME+=("$LATTICE_C_RESET$line"$'\033[K\r\n')
        else
            _lattice_blank
        fi
    done

    # Left-bottom recent-command snapshot. Ctrl-r focuses it; 1-8 rerun.
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
        "[$mode] j/k Enter / r . o h : H ^R ? ^G "
}

lattice_render_commands ()
{
    local i row idx pos name scope target snapshot cmd line mode_label footer total start snapmark usermark
    local preview_h=1
    local body=$(( LATTICE_ROWS - 3 - preview_h ))
    (( body < 1 )) && body=1
    local total=${#LATTICE_CMD_VIEW[@]}
    local offset=${LATTICE_CMD_OFFSET:-0}
    (( offset < 0 )) && offset=0
    (( offset > total - body )) && offset=$(( total - body ))
    (( offset < 0 )) && offset=0
    if (( LATTICE_SELECTED < offset )) ; then
        offset=$LATTICE_SELECTED
    elif (( LATTICE_SELECTED >= offset + body )) ; then
        offset=$(( LATTICE_SELECTED - body + 1 ))
    fi
    LATTICE_CMD_OFFSET=$offset
    LATTICE_CMD_BODY=$body
    start=$(( total ? offset + 1 : 0 ))

    if (( LATTICE_CMD_SEARCH )) ; then
        mode_label="search /${LATTICE_CMD_QUERY}"
        footer='type filter ↑↓ select / Alt-↑↓ move Ctrl-t top Enter run p preview Esc back '
    else
        mode_label='list'
        footer='j/k ↑↓ PgUp/PgDn / p D del R reload Alt-↑↓ Ctrl-t Enter Esc '
    fi
    if (( LATTICE_CMD_SEARCH )) ; then
        local q=${LATTICE_CMD_QUERY}
        local maxq=$(( LATTICE_COLS - 16 ))
        (( maxq < 8 )) && maxq=8
        if (( ${#q} > maxq )) ; then
            q="...${q: -maxq}"
        fi
        _lattice_row " search> ${q}_"
    else
        _lattice_row "${LATTICE_C_BOLD}${LATTICE_C_CYAN} quick commands  [${mode_label}]  ${start}-$(( offset + body < total ? offset + body : total ))/${total}  * snapshot  + user ${LATTICE_C_RESET}"
    fi

    for ((row=0;row<body;row++)); do
        pos=$(( offset + row ))
        if (( pos < total )) ; then
            idx=${LATTICE_CMD_VIEW[pos]}
            key="${idx}:${LATTICE_COLS}"
            if (( ${#LATTICE_CMD_ROW_CACHE[@]} >= 4096 )) ; then
                LATTICE_CMD_ROW_CACHE=()
            fi
            if [[ -n "${LATTICE_CMD_ROW_CACHE[$key]+x}" ]] ; then
                base=${LATTICE_CMD_ROW_CACHE[$key]}
            else
                name=${LATTICE_CMD_NAMES[idx]}
                scope=${LATTICE_CMD_SCOPES[idx]}
                target=${LATTICE_CMD_TARGETS[idx]}
                snapshot=${LATTICE_CMD_SNAPSHOTS[idx]:-}
                snapmark=' '
                usermark=' '
                [[ -n "$snapshot" ]] && snapmark='*'
                [[ "${LATTICE_CMD_ORIGINS[idx]:-base}" == 'user' ]] && usermark='+'
                _lattice_pad "$name" 28 ; name=$REPLY
                _lattice_pad "$scope" 6 ; scope=$REPLY
                _lattice_pad "$target" 8 ; target=$REPLY
                printf -v line '%s%s %s %s %s' \
                    "$snapmark" "$usermark" "$name" "$scope" "$target"
                _lattice_fit "$line" "$LATTICE_COLS"
                base=$REPLY
                LATTICE_CMD_ROW_CACHE[$key]=$base
            fi
            if (( pos == LATTICE_SELECTED )) ; then
                _lattice_pad "$base" "$LATTICE_COLS"
                line="$LATTICE_C_REV$REPLY$LATTICE_C_RESET"
            else
                line=$base
            fi
            LATTICE_FRAME+=("$LATTICE_C_RESET$line"$'\033[K\r\n')
        else
            _lattice_blank
        fi
    done

    # Preview area: only the selected command body, no labels or snapshot.
    if (( total > 0 )) && (( LATTICE_SELECTED >= 0 && LATTICE_SELECTED < total )) ; then
        idx=${LATTICE_CMD_VIEW[LATTICE_SELECTED]}
        cmd=${LATTICE_CMD_COMMANDS[idx]:-}
        cmd=${cmd%%$'\n'*}
        _lattice_fit "$cmd" "$LATTICE_COLS"
        LATTICE_FRAME+=("$REPLY"$'\033[K\r\n')
    else
        _lattice_blank
    fi
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
            LATTICE_FRAME+=("$LATTICE_C_RESET$line"$'\033[K\r\n')
        else
            _lattice_blank
        fi
    done
    _lattice_footer " ${LATTICE_STATUS} " '[HISTORY] j/k Enter / Esc '
}

_lattice_wrap_line ()
{
    local text=$1 width=$2 line='' used=0 ch w i
    for ((i=0;i<${#text};i++)); do
        ch=${text:i:1}
        str_display_width "$ch"; w=$REPLY
        if (( ${#line} > 0 && used + w > width )) ; then
            LATTICE_SNAPSHOT_WRAP+=("$line")
            line=$ch
            used=$w
        else
            line+=$ch
            (( used += w ))
        fi
    done
    LATTICE_SNAPSHOT_WRAP+=("$line")
}

lattice_snapshot_layout ()
{
    local text=$LATTICE_SNAPSHOT_TEXT
    local -a raw=()
    local line maxw width inner w
    while IFS= read -r line ; do
        raw+=("$line")
    done <<< "$text"

    maxw=24
    for line in "${raw[@]}" ; do
        str_display_width "$line"; width=$REPLY
        (( width > maxw )) && maxw=$width
    done
    w=$(( maxw + 4 ))
    (( w > LATTICE_COLS - 2 )) && w=$(( LATTICE_COLS - 2 ))
    (( w < 20 )) && w=20
    inner=$(( w - 4 ))
    LATTICE_SNAPSHOT_INNER=$inner

    LATTICE_SNAPSHOT_WRAP=()
    for line in "${raw[@]}" ; do
        _lattice_wrap_line "$line" "$inner"
    done
    LATTICE_SNAPSHOT_TOTAL=${#LATTICE_SNAPSHOT_WRAP[@]}
    LATTICE_SNAPSHOT_CAP=$(( LATTICE_ROWS - 4 ))
    (( LATTICE_SNAPSHOT_CAP < 1 )) && LATTICE_SNAPSHOT_CAP=1
    (( LATTICE_SNAPSHOT_SCROLL > LATTICE_SNAPSHOT_TOTAL - LATTICE_SNAPSHOT_CAP )) && \
        LATTICE_SNAPSHOT_SCROLL=$(( LATTICE_SNAPSHOT_TOTAL - LATTICE_SNAPSHOT_CAP ))
    (( LATTICE_SNAPSHOT_SCROLL < 0 )) && LATTICE_SNAPSHOT_SCROLL=0
}

lattice_snapshot_scroll ()
{
    lattice_snapshot_layout
    LATTICE_SNAPSHOT_SCROLL=$(( LATTICE_SNAPSHOT_SCROLL + $1 ))
    (( LATTICE_SNAPSHOT_SCROLL < 0 )) && LATTICE_SNAPSHOT_SCROLL=0
    (( LATTICE_SNAPSHOT_SCROLL > LATTICE_SNAPSHOT_TOTAL - LATTICE_SNAPSHOT_CAP )) && \
        LATTICE_SNAPSHOT_SCROLL=$(( LATTICE_SNAPSHOT_TOTAL - LATTICE_SNAPSHOT_CAP ))
    (( LATTICE_SNAPSHOT_SCROLL < 0 )) && LATTICE_SNAPSHOT_SCROLL=0
}

lattice_render_snapshot_popup ()
{
    lattice_snapshot_layout
    local line row visible h top left horiz inner
    local w=$(( LATTICE_SNAPSHOT_INNER + 4 ))
    inner=$LATTICE_SNAPSHOT_INNER
    visible=$LATTICE_SNAPSHOT_TOTAL
    (( visible > LATTICE_SNAPSHOT_CAP )) && visible=$LATTICE_SNAPSHOT_CAP
    h=$(( visible + 2 ))
    (( h > LATTICE_ROWS - 2 )) && h=$(( LATTICE_ROWS - 2 ))
    top=$(( (LATTICE_ROWS - h) / 2 + 1 ))
    left=$(( (LATTICE_COLS - w) / 2 + 1 ))

    printf -v horiz '%*s' "$((w-2))" ''
    horiz=${horiz// /─}

    for ((row=0;row<h;row++)); do
        if (( row == 0 )) ; then
            line="┌${horiz}┐"
        elif (( row == h-1 )) ; then
            line="└${horiz}┘"
        else
            _lattice_fit "${LATTICE_SNAPSHOT_WRAP[LATTICE_SNAPSHOT_SCROLL + row - 1]:-}" "$inner"
            _lattice_pad "$REPLY" "$inner"
            line="│ $REPLY │"
        fi
        printf -v line '\033[%d;%dH%s\033[0m' "$((top+row))" "$left" "$line"
        LATTICE_FRAME+=("$line")
    done
}

lattice_render_form_popup ()
{
    local title=$LATTICE_FORM_TITLE
    local -a rows=()
    local i label value line maxw=24 width w h top left horiz inner
    for ((i=0;i<${#LATTICE_FORM_LABELS[@]};i++)); do
        label=${LATTICE_FORM_LABELS[i]}
        value=${LATTICE_FORM_VALUES[i]:-}
        if (( i == LATTICE_FORM_INDEX )) ; then
            local cursor=${LATTICE_FORM_CURSORS[i]:-${#value}}
            rows+=("${label}: ${value:0:cursor}_${value:cursor}")
        else
            rows+=("${label}: ${value}")
        fi
    done

    str_display_width "$title"; width=$REPLY
    (( width > maxw )) && maxw=$width
    str_display_width 'Enter next · Esc cancel'; width=$REPLY
    (( width > maxw )) && maxw=$width
    for line in "${rows[@]}" ; do
        str_display_width "$line"; width=$REPLY
        (( width > maxw )) && maxw=$width
    done
    w=$(( maxw + 4 ))
    (( w > LATTICE_COLS - 2 )) && w=$(( LATTICE_COLS - 2 ))
    (( w < 20 )) && w=20
    inner=$(( w - 4 ))
    h=$(( ${#rows[@]} + 4 ))
    (( h > LATTICE_ROWS - 2 )) && h=$(( LATTICE_ROWS - 2 ))
    (( h < 4 )) && h=4
    top=$(( (LATTICE_ROWS - h) / 2 + 1 ))
    left=$(( (LATTICE_COLS - w) / 2 + 1 ))

    printf -v horiz '%*s' "$((w-2))" ''
    horiz=${horiz// /─}

    for ((i=0;i<h;i++)); do
        if (( i == 0 )) ; then
            line="┌${horiz}┐"
        elif (( i == h-1 )) ; then
            line="└${horiz}┘"
        elif (( i == 1 )) ; then
            _lattice_fit "$title" "$inner"
            _lattice_pad "$REPLY" "$inner"
            line="│ $REPLY │"
        elif (( i == h-2 )) ; then
            _lattice_fit 'Enter next · ^D default · Esc cancel' "$inner"
            _lattice_pad "$REPLY" "$inner"
            line="│ $REPLY │"
        else
            _lattice_fit "${rows[i-2]:-}" "$inner"
            _lattice_pad "$REPLY" "$inner"
            line="│ $REPLY │"
            if (( i - 2 == LATTICE_FORM_INDEX )) ; then
                line="$LATTICE_C_REV$line$LATTICE_C_RESET"
            fi
        fi
        printf -v line '\033[0m\033[%d;%dH%s\033[0m' "$((top+i))" "$left" "$line"
        LATTICE_FRAME+=("$line")
    done
}

lattice_render_help ()
{
    _lattice_row "${LATTICE_C_BOLD}${LATTICE_C_CYAN} lattice help ${LATTICE_C_RESET}"
    local -a lines=(
        'j/k or arrows   move'
        'Home / End      first / last entry'
        'Ctrl-n/p move even while searching'
        '/               filter file and directory names'
        'Enter           enter directory / open file in gvim'
        'h / Backspace   parent directory'
        'r               refresh tree'
        '.               toggle hidden files'
        'o               open selected directory in the file manager'
        ':               quick command palette'
        '/               search commands in palette'
        '↑/↓             select command'
        'Alt-↑/↓         move command in the palette order'
        'Ctrl-t          pin selected command to the top'
        'Enter           send command; palette stays open'
        'Esc             exit palette (no direct command keys)'
        'H               command history'
        'Ctrl-r          focus recent commands (then 1-8 or Enter)'
        '/               search history (inside history)'
        'R               reload commands.conf'
        'Ctrl-g          quit and close the Lattice session'
    )
    local line
    for line in "${lines[@]}"; do
        _lattice_row "  $line"
    done
    local body=$(( LATTICE_ROWS - 3 - ${#lines[@]} ))
    while (( body-- > 0 )); do _lattice_blank; done
    _lattice_footer " Lattice ${LATTICE_VERSION} " '[HELP] any key '
}

lattice_render ()
{
    # Build the whole frame and write it once. Many small writes make tmux /
    # WinTerm visibly repaint between lines.
    LATTICE_FRAME=()
    LATTICE_FRAME+=($'\033[0m\033[?25l\033[H')
    case "$LATTICE_MODE" in
    commands) lattice_render_commands ;;
    history)  lattice_render_history ;;
    help)     lattice_render_help ;;
    *)        lattice_render_tree ;;
    esac
    (( LATTICE_FORM_OPEN )) && lattice_render_form_popup
    (( LATTICE_SNAPSHOT_OPEN )) && lattice_render_snapshot_popup
    printf '%s' "${LATTICE_FRAME[@]}"
}
