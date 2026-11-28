# lattice/ui/event.sh 鈥?keyboard loop
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[event]++ )) && return 0

_lattice_history_prompt ()
{
    LATTICE_HISTORY_SEARCH=1
    lattice_history_set_query ''
    LATTICE_HISTORY_SELECTED=0
}

_lattice_select_clamp ()
{
    local max=$1
    (( max < 0 )) && max=0
    (( LATTICE_HISTORY_SELECTED < 0 )) && LATTICE_HISTORY_SELECTED=0
    (( LATTICE_HISTORY_SELECTED > max )) && LATTICE_HISTORY_SELECTED=$max
}

lattice_tree_scroll ()
{
    local delta=$1 offset=${LATTICE_TREE_OFFSET:-0}
    local max=$(( ${#LATTICE_ENTRIES[@]} - LATTICE_TREE_BODY ))
    (( max < 0 )) && max=0
    offset=$(( offset + delta ))
    (( offset < 0 )) && offset=0
    (( offset > max )) && offset=$max
    LATTICE_TREE_OFFSET=$offset
    LATTICE_TREE_MANUAL_SCROLL=1
}

lattice_handle_tree_mouse ()
{
    local seq=${1:3}
    [[ "${1: -1}" == 'M' ]] || return 0
    seq=${seq%[Mm]}
    local b x y row now path
    IFS=';' read -r b x y <<< "$seq"
    [[ "$b" =~ ^[0-9]+$ && "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || return 0
    (( b & 32 )) && return 0

    local recent_h=${LATTICE_RECENT_LIMIT:-10}
    (( recent_h > LATTICE_ROWS - 3 )) && recent_h=$(( LATTICE_ROWS - 3 ))
    (( recent_h < 1 )) && recent_h=1
    local body_h=$(( LATTICE_ROWS - 2 - recent_h ))
    (( body_h < 1 )) && body_h=1
    local recent_row=$(( y - 2 - body_h ))
    if (( recent_row >= 0 && recent_row < recent_h )) ; then
        if (( b >= 64 )) ; then
            # The recent panel is fully visible; the wheel must not change
            # the selected recent entry.
            return 0
        fi
        LATTICE_RECENT_FOCUS=1
        LATTICE_RECENT_SELECTED=$recent_row
        if (( (b & 3) == 2 )) ; then
            lattice_recent_show_preview
            return 0
        fi
        (( (b & 3) == 0 )) || return 0
        now=${EPOCHREALTIME:-0}
        now=${now//[!0-9]/}
        if [[ "${LATTICE_MOUSE_LAST_MODE:-}" == 'recent' ]] &&
           (( LATTICE_MOUSE_LAST_TS > 0 &&
              LATTICE_MOUSE_LAST_ROW == recent_row &&
              now - LATTICE_MOUSE_LAST_TS <= 900000 )) ; then
            LATTICE_MOUSE_LAST_TS=0
            LATTICE_MOUSE_LAST_ROW=-1
            lattice_recent_run_index "$recent_row"
        else
            LATTICE_MOUSE_LAST_TS=$now
            LATTICE_MOUSE_LAST_ROW=$recent_row
            LATTICE_MOUSE_LAST_MODE='recent'
            lattice_status "recent: ${LATTICE_RECENT_CMDS[recent_row]:-}"
        fi
        return 0
    fi

    if (( b == 64 )) ; then
        lattice_tree_scroll -3
        return 0
    elif (( b == 65 )) ; then
        lattice_tree_scroll 3
        return 0
    fi
    (( (b & 3) == 0 )) || return 0       # left button press only
    (( y >= 2 && y < 2 + LATTICE_TREE_BODY )) || return 0

    row=$(( LATTICE_TREE_OFFSET + y - 2 ))
    (( row >= 0 && row < ${#LATTICE_ENTRIES[@]} )) || return 0

    LATTICE_TREE_MANUAL_SCROLL=0
    LATTICE_RECENT_FOCUS=0
    LATTICE_TREE_SELECTED=$row
    lattice_selected_path
    path=$REPLY
    lattice_status "$path"

    now=${EPOCHREALTIME:-0}
    now=${now//[!0-9]/}
    if [[ "${LATTICE_MOUSE_LAST_MODE:-}" == 'tree' ]] &&
       (( LATTICE_MOUSE_LAST_TS > 0 &&
          LATTICE_MOUSE_LAST_ROW == row &&
          now - LATTICE_MOUSE_LAST_TS <= 900000 )) ; then
        LATTICE_MOUSE_LAST_TS=0
        LATTICE_MOUSE_LAST_ROW=-1
        if [[ -d "$path" ]] ; then
            lattice_tree_enter
        elif [[ -f "$path" ]] ; then
            lattice_executor_open_file "$path"
        fi
    else
        LATTICE_MOUSE_LAST_TS=$now
        LATTICE_MOUSE_LAST_ROW=$row
        LATTICE_MOUSE_LAST_MODE='tree'
    fi
}

lattice_handle_tree_key ()
{
    local key=$1 idx q
    if [[ "$key" == $'\033[<'* ]] ; then
        lattice_handle_tree_mouse "$key"
        return 0
    fi
    LATTICE_TREE_MANUAL_SCROLL=0
    if (( LATTICE_TREE_SEARCH )) ; then
        case "$key" in
        $'\033[A'|$'\020') lattice_tree_move -1 ;;
        $'\033[B'|$'\016') lattice_tree_move 1 ;;
        $'\013')   lattice_tree_move -1 ;;
        $'\r')
            lattice_tree_enter
            ;;
        $'\033')
            lattice_tree_search_close
            ;;
        $'\025')
            lattice_tree_set_filter ''
            ;;
        $'\177'|$'\b')
            q=$LATTICE_TREE_FILTER
            lattice_tree_set_filter "${q%?}"
            ;;
        [[:print:]])
            lattice_tree_set_filter "$LATTICE_TREE_FILTER$key"
            ;;
        esac
        return 0
    fi

    if (( LATTICE_RECENT_FOCUS )) ; then
        case "$key" in
        j|$'\033[B'|$'\016')
            ((LATTICE_RECENT_SELECTED++))
            (( LATTICE_RECENT_SELECTED >= ${#LATTICE_RECENT_CMDS[@]} )) && \
                LATTICE_RECENT_SELECTED=$(( ${#LATTICE_RECENT_CMDS[@]} - 1 ))
            (( LATTICE_RECENT_SELECTED < 0 )) && LATTICE_RECENT_SELECTED=0
            ;;
        k|$'\033[A'|$'\020'|$'\013')
            ((LATTICE_RECENT_SELECTED--))
            (( LATTICE_RECENT_SELECTED < 0 )) && LATTICE_RECENT_SELECTED=0
            ;;
        $'\r')
            lattice_recent_run_index "$LATTICE_RECENT_SELECTED"
            ;;
        p) lattice_recent_show_preview ;;
        @)
            LATTICE_RECENT_FOCUS=0
            LATTICE_TREE_AT_PENDING=1
            lattice_status 'register: press a, b or c'
            ;;
        0|1|2|3|4|5|6|7|8|9)
            idx=$key
            (( idx < ${#LATTICE_RECENT_CMDS[@]} )) && lattice_recent_run_index "$idx"
            ;;
        $'\022'|$'\033'|q)
            LATTICE_RECENT_FOCUS=0
            ;;
        *)
            # Any other key is a tree action: leave recent focus and let the
            # normal tree handler process it (r refreshes, : opens palette...).
            LATTICE_RECENT_FOCUS=0
            lattice_handle_tree_key "$key"
            ;;
        esac
        return 0
    fi

    if (( LATTICE_TREE_AT_PENDING )) ; then
        LATTICE_TREE_AT_PENDING=0
        case "$key" in
        a|A) lattice_tree_register A ;;
        b|B) lattice_tree_register B ;;
        c|C) lattice_tree_register C ;;
        *)   lattice_status 'register: use @a, @b or @c' error ;;
        esac
        return 0
    fi

    case "$key" in
    j|$'\033[B'|$'\016') lattice_tree_move 1 ;;
    k|$'\033[A'|$'\020'|$'\013') lattice_tree_move -1 ;;
    $'\033[H'|$'\033[1~'|$'\033[7~'|$'\033OH')
        LATTICE_TREE_SELECTED=0
        LATTICE_TREE_OFFSET=0
        ;;
    $'\033[F'|$'\033[4~'|$'\033[8~'|$'\033OF')
        LATTICE_TREE_SELECTED=$(( ${#LATTICE_ENTRIES[@]} - 1 ))
        (( LATTICE_TREE_SELECTED < 0 )) && LATTICE_TREE_SELECTED=0
        ;;
    $'\033[C')   lattice_tree_enter ;;
    $'\033[D'|h|$'\177'|$'\b') lattice_tree_parent ;;
    $'\r'|'')    lattice_tree_enter ;;    r)           lattice_tree_refresh ;;
    .)           lattice_tree_toggle_hidden ;;
    o)           lattice_tree_open_directory ;;
    y)           lattice_tree_yank_path ;;
    @)           LATTICE_TREE_AT_PENDING=1; lattice_status 'register: press a, b or c' ;;
    :)           lattice_registry_open ;;
    /)           lattice_tree_search_open ;;
    H)           LATTICE_HISTORY_SEARCH=0; LATTICE_MODE='history'; lattice_history_set_query ''; lattice_history_rebuild_view ;;
    '?' )        LATTICE_MODE='help' ;;
    $'\022')     LATTICE_RECENT_FOCUS=1; LATTICE_RECENT_SELECTED=0
                 lattice_status "recent commands: ${#LATTICE_RECENT_CMDS[@]}  j/k 0-9 Enter Esc" ;;
    R)           lattice_registry_reload; lattice_reload_all ;;
    q)           lattice_status 'Ctrl-g quits; q is disabled to avoid accidental exit' ;;
    esac
}

lattice_form_close ()
{
    LATTICE_FORM_OPEN=0
    LATTICE_FORM_KIND=''
    LATTICE_FORM_TITLE=''
    LATTICE_FORM_LABELS=()
    LATTICE_FORM_VALUES=()
    LATTICE_FORM_DEFAULTS=()
    LATTICE_FORM_CURSORS=()
    LATTICE_FORM_INDEX=0
    LATTICE_FORM_CMD_INDEX=-1
    LATTICE_FORM_DELETE_NAME=''
}

lattice_form_commit ()
{
    local kind=$LATTICE_FORM_KIND idx=$LATTICE_FORM_CMD_INDEX
    local -a args=()
    local i

    case "$kind" in
    params)
        for ((i=0;i<${#LATTICE_FORM_LABELS[@]};i++)); do
            args+=("${LATTICE_FORM_LABELS[i]}=${LATTICE_FORM_VALUES[i]}")
        done
        lattice_form_close
        lattice_registry_run_index "$idx" "${args[@]}"
        ;;
    delete)
        local confirm=${LATTICE_FORM_VALUES[0]:-}
        local delete_name=$LATTICE_FORM_DELETE_NAME
        lattice_form_close
        if [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]] ; then
            lattice_registry_disable_name "$delete_name"
        fi
        LATTICE_MODE='commands'
        ;;
    esac
}

lattice_handle_form_key ()
{
    local key=$1 value cursor text
    value=${LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]:-}
    cursor=${LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]:-${#value}}
    (( cursor < 0 )) && cursor=0
    (( cursor > ${#value} )) && cursor=${#value}

    if [[ "$key" == $'\033[200~' ]] ; then
        text=${LATTICE_PASTE_TEXT:-}
        text=${text//$'\r'/ }
        text=${text//$'\n'/ }
        text=${text//$'\t'/ }
        LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]="${value:0:cursor}${text}${value:cursor}"
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=$(( cursor + ${#text} ))
        return 0
    fi

    case "$key" in
    $'\033')
        lattice_form_close
        return 0
        ;;
    $'\r'|'')
        if (( LATTICE_FORM_INDEX + 1 < ${#LATTICE_FORM_LABELS[@]} )) ; then
            ((LATTICE_FORM_INDEX++))
            LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=${#LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]}
        else
            lattice_form_commit
        fi
        return 0
        ;;
    $'\t')
        if (( LATTICE_FORM_INDEX + 1 < ${#LATTICE_FORM_LABELS[@]} )) ; then
            ((LATTICE_FORM_INDEX++))
            LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=${#LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]}
        fi
        return 0
        ;;
    $'\033[Z')
        if (( LATTICE_FORM_INDEX > 0 )) ; then
            ((LATTICE_FORM_INDEX--))
            LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=${#LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]}
        fi
        return 0
        ;;
    $'\033[D')
        (( cursor > 0 )) && ((cursor--))
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=$cursor
        return 0
        ;;
    $'\033[C')
        (( cursor < ${#value} )) && ((cursor++))
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=$cursor
        return 0
        ;;
    $'\033[H'|$'\033[1~')
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=0
        return 0
        ;;
    $'\033[F'|$'\033[4~')
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=${#value}
        return 0
        ;;
    $'\001')
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=0
        return 0
        ;;
    $'\005')
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=${#value}
        return 0
        ;;
    $'\033[3~')
        if (( cursor < ${#value} )) ; then
            LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]="${value:0:cursor}${value:cursor+1}"
        fi
        return 0
        ;;
    $'\177'|$'\b')
        if (( cursor > 0 )) ; then
            LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]="${value:0:cursor-1}${value:cursor}"
            ((cursor--))
            LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=$cursor
        fi
        return 0
        ;;
    $'\025')
        LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]=''
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=0
        return 0
        ;;
    $'\004')
        value=${LATTICE_FORM_DEFAULTS[LATTICE_FORM_INDEX]:-}
        LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]=$value
        LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=${#value}
        return 0
        ;;
    *)
        case "$key" in
        [[:print:]])
            LATTICE_FORM_VALUES[LATTICE_FORM_INDEX]="${value:0:cursor}${key}${value:cursor}"
            ((cursor++))
            LATTICE_FORM_CURSORS[LATTICE_FORM_INDEX]=$cursor
            ;;
        esac
        return 0
        ;;
    esac
}
lattice_handle_commands_mouse ()
{
    local seq=${1:3}
    [[ "${1: -1}" == 'M' ]] || return 0
    seq=${seq%[Mm]}
    local b x y row now idx
    IFS=';' read -r b x y <<< "$seq"
    [[ "$b" =~ ^[0-9]+$ && "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || return 0

    if (( b >= 64 )) ; then
        local off=${LATTICE_CMD_OFFSET:-0}
        local max=$(( ${#LATTICE_CMD_VIEW[@]} - LATTICE_CMD_BODY ))
        (( max < 0 )) && max=0
        if (( b == 64 )) ; then
            off=$(( off - 3 ))
        else
            off=$(( off + 3 ))
        fi
        (( off < 0 )) && off=0
        (( off > max )) && off=$max
        LATTICE_CMD_OFFSET=$off
        LATTICE_CMD_MANUAL_SCROLL=1
        return 0
    fi
    (( y >= 2 && y < 2 + LATTICE_CMD_BODY )) || return 0
    row=$(( LATTICE_CMD_OFFSET + y - 2 ))
    (( row >= 0 && row < ${#LATTICE_CMD_VIEW[@]} )) || return 0
    LATTICE_CMD_MANUAL_SCROLL=0
    LATTICE_CMD_SELECTED=$row
    idx=${LATTICE_CMD_VIEW[row]}

    if (( (b & 3) == 2 )) ; then
        lattice_registry_show_snapshot
        return 0
    fi
    (( (b & 3) == 0 )) || return 0

    now=${EPOCHREALTIME:-0}
    now=${now//[!0-9]/}
    if [[ "${LATTICE_MOUSE_LAST_MODE:-}" == 'commands' ]] &&
       (( LATTICE_MOUSE_LAST_TS > 0 &&
          LATTICE_MOUSE_LAST_ROW == row &&
          now - LATTICE_MOUSE_LAST_TS <= 900000 )) ; then
        LATTICE_MOUSE_LAST_TS=0
        LATTICE_MOUSE_LAST_ROW=-1
        lattice_registry_dispatch_index "$idx"
    else
        LATTICE_MOUSE_LAST_TS=$now
        LATTICE_MOUSE_LAST_ROW=$row
        LATTICE_MOUSE_LAST_MODE='commands'
        lattice_status "selected: ${LATTICE_CMD_NAMES[idx]}"
    fi
}

lattice_handle_commands_key ()
{
    local key=$1 idx q
    LATTICE_CMD_MANUAL_SCROLL=0
    if (( LATTICE_CMD_SEARCH )) ; then
        case "$key" in
        p|D|R)
            lattice_registry_set_query "$LATTICE_CMD_QUERY$key"
            lattice_search_status_update
            return 0
            ;;
        esac
    fi
    case "$key" in
    $'\033[5~') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED - LATTICE_CMD_BODY)) ;;
    $'\033[6~') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED + LATTICE_CMD_BODY)) ;;
    $'\033[1;3A'|$'\033[1;5A') lattice_registry_move_selected -1 ;;
    $'\033[1;3B'|$'\033[1;5B') lattice_registry_move_selected 1 ;;
    $'\033[A') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED-1)) ;;
    $'\033[B') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED+1)) ;;
    $'\033[H'|$'\033[1~'|$'\033[7~'|$'\033OH')
        LATTICE_CMD_SELECTED=0
        LATTICE_CMD_OFFSET=0
        ;;
    $'\033[F'|$'\033[4~'|$'\033[8~'|$'\033OF')
        LATTICE_CMD_SELECTED=$(( ${#LATTICE_CMD_VIEW[@]} - 1 ))
        (( LATTICE_CMD_SELECTED < 0 )) && LATTICE_CMD_SELECTED=0
        ;;
    $'\020') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED-1)) ;;
    $'\016') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED+1)) ;;
    $'\013') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED-1)) ;;
    $'\024')
        lattice_registry_move_to_top
        ;;
    $'\r')
        if lattice_registry_selected_raw_index ; then
            idx=$REPLY
            lattice_registry_dispatch_index "$idx"
        fi
        ;;
    p)
        (( ! LATTICE_CMD_SEARCH )) && lattice_registry_show_snapshot
        ;;
    D)
        (( ! LATTICE_CMD_SEARCH )) && lattice_registry_start_delete
        ;;
    R)
        if (( ! LATTICE_CMD_SEARCH )) ; then
            if lattice_registry_load ; then
                LATTICE_MODE='commands'
                LATTICE_CMD_SEARCH=0
                LATTICE_CMD_QUERY=''
                LATTICE_CMD_SELECTED=0
                lattice_registry_rebuild_view
                lattice_status 'commands reloaded' ok
            else
                lattice_status 'command reload failed' error
            fi
        fi
        ;;
    '/')
        if (( LATTICE_CMD_SEARCH )) ; then
            lattice_registry_set_query "$LATTICE_CMD_QUERY/"
            lattice_search_status_update
        else
            LATTICE_CMD_SEARCH=1
            lattice_search_status_start
        fi
        ;;
    $'\033')
        if (( LATTICE_CMD_SEARCH )) ; then
            LATTICE_CMD_SEARCH=0
            lattice_registry_set_query ''
            lattice_search_status_end
        else
            LATTICE_MODE='tree'
            return 0
        fi
        ;;
    $'\025')
        if (( LATTICE_CMD_SEARCH )) ; then
            lattice_registry_set_query ''
            lattice_search_status_update
        fi
        ;;
    $'\177'|$'\b')
        if (( LATTICE_CMD_SEARCH )) ; then
            q=$LATTICE_CMD_QUERY
            if [[ -n "$q" ]] ; then
                lattice_registry_set_query "${q%?}"
                lattice_search_status_update
            fi
        fi
        ;;
    *)
        if (( LATTICE_CMD_SEARCH )) ; then
            case "$key" in
            [[:print:]])
                lattice_registry_set_query "$LATTICE_CMD_QUERY$key"
                lattice_search_status_update
                ;;
            esac
        else
            case "$key" in
            j|$'\033[B') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED+1)) ;;
            k|$'\033[A') LATTICE_CMD_SELECTED=$((LATTICE_CMD_SELECTED-1)) ;;
            q) LATTICE_MODE='tree' ; return 0 ;;
            esac
        fi
        ;;
    esac
    (( LATTICE_CMD_SELECTED < 0 )) && LATTICE_CMD_SELECTED=0
    (( LATTICE_CMD_SELECTED >= ${#LATTICE_CMD_VIEW[@]} )) && \
        LATTICE_CMD_SELECTED=$(( ${#LATTICE_CMD_VIEW[@]} - 1 ))
    (( LATTICE_CMD_SELECTED < 0 )) && LATTICE_CMD_SELECTED=0
}

lattice_handle_history_mouse ()
{
    local seq=${1:3}
    [[ "${1: -1}" == 'M' ]] || return 0
    seq=${seq%[Mm]}
    local b x y row offset body total now
    IFS=';' read -r b x y <<< "$seq"
    [[ "$b" =~ ^[0-9]+$ && "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || return 0
    (( b & 32 )) && return 0

    if (( b >= 64 )) ; then
        body=$(( LATTICE_ROWS - 2 ))
        (( body < 1 )) && body=1
        total=${#LATTICE_HISTORY_VIEW[@]}
        local off=${LATTICE_HISTORY_OFFSET:-0}
        local max=$(( total - body ))
        (( max < 0 )) && max=0
        if (( b == 64 )) ; then
            off=$(( off - 3 ))
        else
            off=$(( off + 3 ))
        fi
        (( off < 0 )) && off=0
        (( off > max )) && off=$max
        LATTICE_HISTORY_OFFSET=$off
        LATTICE_HISTORY_MANUAL_SCROLL=1
        return 0
    fi

    body=$(( LATTICE_ROWS - 2 ))
    (( body < 1 )) && body=1
    (( y >= 2 && y < 2 + body )) || return 0
    total=${#LATTICE_HISTORY_VIEW[@]}
    (( total > 0 )) || return 0
    offset=${LATTICE_HISTORY_OFFSET:-0}
    (( offset < 0 )) && offset=0
    (( offset > total - body )) && offset=$(( total - body ))
    (( offset < 0 )) && offset=0
    row=$(( offset + y - 2 ))
    (( row >= 0 && row < total )) || return 0
    LATTICE_HISTORY_MANUAL_SCROLL=0
    LATTICE_HISTORY_SELECTED=$row

    if (( (b & 3) == 2 )) ; then
        lattice_history_show_preview
        return 0
    fi
    (( (b & 3) == 0 )) || return 0

    now=${EPOCHREALTIME:-0}
    now=${now//[!0-9]/}
    if [[ "${LATTICE_MOUSE_LAST_MODE:-}" == 'history' ]] &&
       (( LATTICE_MOUSE_LAST_TS > 0 &&
          LATTICE_MOUSE_LAST_ROW == row &&
          now - LATTICE_MOUSE_LAST_TS <= 900000 )) ; then
        LATTICE_MOUSE_LAST_TS=0
        LATTICE_MOUSE_LAST_ROW=-1
        lattice_history_rerun && LATTICE_MODE='tree'
    else
        LATTICE_MOUSE_LAST_TS=$now
        LATTICE_MOUSE_LAST_ROW=$row
        LATTICE_MOUSE_LAST_MODE='history'
        lattice_status "selected: ${LATTICE_HISTORY_CMDS[${LATTICE_HISTORY_VIEW[row]}]}"
    fi
}

lattice_handle_history_key ()
{
    local key=$1 q
    LATTICE_HISTORY_MANUAL_SCROLL=0
    if (( LATTICE_HISTORY_SEARCH )) ; then
        case "$key" in
        p|D|R)
            lattice_history_set_query "${LATTICE_HISTORY_QUERY}$key"
            LATTICE_HISTORY_SELECTED=0
            _lattice_select_clamp $(( ${#LATTICE_HISTORY_VIEW[@]} - 1 ))
            return 0
            ;;
        esac
    fi
    if (( LATTICE_HISTORY_SEARCH )) ; then
        case "$key" in
        $'\033[A'|$'\020') LATTICE_HISTORY_SELECTED=$((LATTICE_HISTORY_SELECTED-1)) ;;
        $'\033[B'|$'\016') LATTICE_HISTORY_SELECTED=$((LATTICE_HISTORY_SELECTED+1)) ;;
        $'\033[H'|$'\033[1~'|$'\033[7~'|$'\033OH')
            LATTICE_HISTORY_SELECTED=0
            ;;
        $'\033[F'|$'\033[4~'|$'\033[8~'|$'\033OF')
            LATTICE_HISTORY_SELECTED=$(( ${#LATTICE_HISTORY_VIEW[@]} - 1 ))
            ;;
        $'\033')
            LATTICE_HISTORY_SEARCH=0
            lattice_history_set_query ''
            LATTICE_HISTORY_SELECTED=0
            ;;
        $'\r')
            lattice_history_rerun && {
                LATTICE_HISTORY_SEARCH=0
                lattice_history_set_query ''
                LATTICE_MODE='tree'
            }
            ;;
        $'\025')
            lattice_history_set_query ''
            LATTICE_HISTORY_SELECTED=0
            ;;
        $'\177'|$'\b')
            q=${LATTICE_HISTORY_QUERY}
            if [[ -n "$q" ]] ; then
                lattice_history_set_query "${q%?}"
                LATTICE_HISTORY_SELECTED=0
            fi
            ;;
        '/')
            lattice_history_set_query "${LATTICE_HISTORY_QUERY}/"
            LATTICE_HISTORY_SELECTED=0
            ;;
        *)
            case "$key" in
            [[:print:]])
                lattice_history_set_query "${LATTICE_HISTORY_QUERY}$key"
                LATTICE_HISTORY_SELECTED=0
                ;;
            esac
            ;;
        esac
        _lattice_select_clamp $(( ${#LATTICE_HISTORY_VIEW[@]} - 1 ))
        return 0
    fi

    case "$key" in
    j|$'\033[B'|$'\016') LATTICE_HISTORY_SELECTED=$((LATTICE_HISTORY_SELECTED+1)) ;;
    k|$'\033[A'|$'\020'|$'\013') LATTICE_HISTORY_SELECTED=$((LATTICE_HISTORY_SELECTED-1)) ;;
    $'\033[H'|$'\033[1~'|$'\033[7~'|$'\033OH')
        LATTICE_HISTORY_SELECTED=0
        LATTICE_HISTORY_OFFSET=0
        ;;
    $'\033[F'|$'\033[4~'|$'\033[8~'|$'\033OF')
        LATTICE_HISTORY_SELECTED=$(( ${#LATTICE_HISTORY_VIEW[@]} - 1 ))
        ;;
    $'\r')
        lattice_history_rerun && LATTICE_MODE='tree'
        ;;
    p) lattice_history_show_preview ;;
    '/') _lattice_history_prompt ;;
    $'\033'|q)
        LATTICE_HISTORY_SEARCH=0
        lattice_history_set_query ''
        LATTICE_MODE='tree'
        ;;
    esac
    _lattice_select_clamp $(( ${#LATTICE_HISTORY_VIEW[@]} - 1 ))
}

lattice_handle_help_key ()
{
    LATTICE_MODE='tree'
}

lattice_handle_key ()
{
    local key=$1 now active
    # Focus moved to the executor: discard every key already queued for this
    # pane until the user actually returns to the TUI.
    if (( LATTICE_INPUT_BLOCKED )) ; then
        if [[ -n "${TMUX_PANE:-}" ]] ; then
            active=$(lattice_tmux_quick display-message -p -t "$TMUX_PANE" '#{pane_active}' 2>/dev/null)
            [[ "$active" == 1 ]] || return 0
        fi
        LATTICE_INPUT_BLOCKED=0
    fi
    # The insert path switches focus to the executor, but an Enter already
    # queued for this pane can still arrive afterwards and reopen the form.
    if [[ "$key" == $'\r' ]] && (( LATTICE_SUPPRESS_ENTER_UNTIL )) ; then
        now=${EPOCHREALTIME:-0}
        now=${now//[!0-9]/}
        if (( now > 0 && now < LATTICE_SUPPRESS_ENTER_UNTIL )) ; then
            return 0
        fi
        LATTICE_SUPPRESS_ENTER_UNTIL=0
    fi
    # Ctrl-g is the explicit "quit Lattice and close its session" key.
    # Ctrl-b d remains detach. Plain q is intentionally not a quit key.
    if [[ "$key" == $'\007' ]] ; then
        LATTICE_QUIT=1
        return 0
    fi
    if (( ! LATTICE_CMD_SEARCH )) ; then
        lattice_search_status_end
    fi
    if (( LATTICE_FORM_OPEN )) ; then
        lattice_handle_form_key "$key"
        return 0
    fi
    if (( LATTICE_SNAPSHOT_OPEN )) ; then
        case "$key" in
        $'\033[5~')
            lattice_snapshot_scroll -$LATTICE_SNAPSHOT_CAP
            return 0
            ;;
        $'\033[6~')
            lattice_snapshot_scroll "$LATTICE_SNAPSHOT_CAP"
            return 0
            ;;
        $'\033[<'*)
            # Mouse release must not dismiss the popup: press opens it and the
            # matching release arrives on the next read.
            [[ "${key: -1}" == 'm' ]] && return 0
            local mb mx my mbcode
            local mseq=${key:3}
            mseq=${mseq%[Mm]}
            IFS=';' read -r mb mx my <<< "$mseq"
            mbcode=${mb:-0}
            (( mbcode & 32 )) && return 0
            if (( mbcode == 64 )) ; then
                lattice_snapshot_scroll -3
            elif (( mbcode == 65 )) ; then
                lattice_snapshot_scroll 3
            elif (( (mbcode & 3) == 2 )) ; then
                LATTICE_SNAPSHOT_OPEN=0
            elif (( (mbcode & 3) == 0 )) ; then
                LATTICE_SNAPSHOT_OPEN=0
                case "$LATTICE_MODE" in
                commands) lattice_handle_commands_mouse "$key" ;;
                history) lattice_handle_history_mouse "$key" ;;
                tree) lattice_handle_tree_mouse "$key" ;;
                esac
            fi
            return 0
            ;;
        p|$'\033'|q)
            LATTICE_SNAPSHOT_OPEN=0
            return 0
            ;;
        *)
            # Moving/clicking elsewhere dismisses the preview automatically;
            # the same key is then handled by the underlying mode.
            LATTICE_SNAPSHOT_OPEN=0
            ;;
        esac
    fi
    case "$LATTICE_MODE" in
    tree)     lattice_handle_tree_key "$key" ;;
    commands)
        if [[ "$key" == $'\033[<'* ]] ; then
            lattice_handle_commands_mouse "$key"
        else
            lattice_handle_commands_key "$key"
        fi
        ;;
    history)
        if [[ "$key" == $'\033[<'* ]] ; then
            lattice_handle_history_mouse "$key"
        else
            lattice_handle_history_key "$key"
        fi
        ;;
    help)     lattice_handle_help_key "$key" ;;
    esac
}

lattice_read_paste ()
{
    local paste='' ch
    while IFS= read -rsn1 -t 0.05 ch ; do
        paste+=$ch
        if [[ "$paste" == *$'\033[201~' ]] ; then
            paste=${paste%$'\033[201~'}
            break
        fi
    done
    LATTICE_PASTE_TEXT=$paste
    REPLY=$'\033[200~'
    return 0
}

lattice_read_key ()
{
    local key seq ch
    IFS= read -rsn1 -t 1 key || return 1

    # This terminal reports both Enter and Ctrl-J as LF/empty. Enter must win:
    # normalize both to CR so command execution always works. Search movement
    # is on Ctrl-n/Ctrl-p (Ctrl-k also moves up).
    [[ -z "$key" || "$key" == $'\n' ]] && key=$'\r'

    if [[ "$key" == $'\033' ]] ; then
        seq=$key
        while IFS= read -rsn1 -t 0.01 ch ; do
            seq+=$ch
            [[ "$ch" == [A-Za-z~] ]] && break
        done
        key=$seq
        [[ "$key" == $'\033[200~' ]] && lattice_read_paste
    fi
    REPLY=$key
    return 0
}

lattice_event_loop ()
{
    local key
    lattice_render
    while (( ! LATTICE_QUIT )) ; do
        if lattice_read_key ; then
            key=$REPLY
            lattice_handle_key "$key"
            # Render only after a key. A periodic full redraw makes the
            # cursor/frame visibly wander in WinTerm and similar terminals.
            lattice_render
        elif (( LATTICE_NEED_RENDER )) ; then
            LATTICE_NEED_RENDER=0
            lattice_render
        fi
    done
}
