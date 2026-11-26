# lattice/ui/event.sh 鈥?keyboard loop
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[event]++ )) && return 0

_lattice_history_prompt ()
{
    local q
    printf '\033[%d;1H\033[Ksearch: ' "$LATTICE_ROWS"
    lattice_term_restore
    IFS= read -r q || q=''
    lattice_term_raw
    lattice_history_set_query "$q"
    LATTICE_SELECTED=0
}

_lattice_select_clamp ()
{
    local max=$1
    (( max < 0 )) && max=0
    (( LATTICE_SELECTED < 0 )) && LATTICE_SELECTED=0
    (( LATTICE_SELECTED > max )) && LATTICE_SELECTED=$max
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
    if (( b == 64 )) ; then
        lattice_tree_move -3
        return 0
    elif (( b == 65 )) ; then
        lattice_tree_move 3
        return 0
    fi
    (( (b & 3) == 0 )) || return 0       # left button press only
    (( y >= 2 && y < 2 + LATTICE_TREE_BODY )) || return 0

    row=$(( LATTICE_TREE_OFFSET + y - 2 ))
    (( row >= 0 && row < ${#LATTICE_ENTRIES[@]} )) || return 0

    LATTICE_RECENT_FOCUS=0
    LATTICE_SELECTED=$row
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
        1|2|3|4|5|6|7|8)
            idx=$(( key - 1 ))
            (( idx < ${#LATTICE_RECENT_CMDS[@]} )) && lattice_recent_run_index "$idx"
            ;;
        $'\022'|$'\033'|q)
            LATTICE_RECENT_FOCUS=0
            ;;
        esac
        return 0
    fi

    case "$key" in
    j|$'\033[B'|$'\016') lattice_tree_move 1 ;;
    k|$'\033[A'|$'\020'|$'\013') lattice_tree_move -1 ;;
    $'\033[C')   lattice_tree_enter ;;
    $'\033[D'|h|$'\177'|$'\b') lattice_tree_parent ;;
    $'\r'|'')    lattice_tree_enter ;;    r)           lattice_tree_refresh ;;
    .)           lattice_tree_toggle_hidden ;;
    o)           lattice_tree_open_directory ;;
    :)           lattice_registry_open ;;
    /)           lattice_tree_search_open ;;
    H)           LATTICE_MODE='history'; LATTICE_SELECTED=0; lattice_history_rebuild_view ;;
    '?' )        LATTICE_MODE='help' ;;
    $'\022')     LATTICE_RECENT_FOCUS=1; LATTICE_RECENT_SELECTED=0
                 lattice_status "recent commands: ${#LATTICE_RECENT_CMDS[@]}  j/k Enter Esc" ;;
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
        if (( b == 64 )) ; then
            LATTICE_SELECTED=$((LATTICE_SELECTED-3))
        else
            LATTICE_SELECTED=$((LATTICE_SELECTED+3))
        fi
        (( LATTICE_SELECTED < 0 )) && LATTICE_SELECTED=0
        (( LATTICE_SELECTED >= ${#LATTICE_CMD_VIEW[@]} )) && \
            LATTICE_SELECTED=$(( ${#LATTICE_CMD_VIEW[@]} - 1 ))
        (( LATTICE_SELECTED < 0 )) && LATTICE_SELECTED=0
        return 0
    fi
    (( y >= 2 && y < 2 + LATTICE_CMD_BODY )) || return 0
    row=$(( LATTICE_CMD_OFFSET + y - 2 ))
    (( row >= 0 && row < ${#LATTICE_CMD_VIEW[@]} )) || return 0
    LATTICE_SELECTED=$row
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
    case "$key" in
    $'\033[5~') LATTICE_SELECTED=$((LATTICE_SELECTED - LATTICE_CMD_BODY)) ;;
    $'\033[6~') LATTICE_SELECTED=$((LATTICE_SELECTED + LATTICE_CMD_BODY)) ;;
    $'\033[1;3A'|$'\033[1;5A') lattice_registry_move_selected -1 ;;
    $'\033[1;3B'|$'\033[1;5B') lattice_registry_move_selected 1 ;;
    $'\033[A') LATTICE_SELECTED=$((LATTICE_SELECTED-1)) ;;
    $'\033[B') LATTICE_SELECTED=$((LATTICE_SELECTED+1)) ;;
    $'\020') LATTICE_SELECTED=$((LATTICE_SELECTED-1)) ;;
    $'\016') LATTICE_SELECTED=$((LATTICE_SELECTED+1)) ;;
    $'\013') LATTICE_SELECTED=$((LATTICE_SELECTED-1)) ;;
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
                LATTICE_SELECTED=0
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
        else
            LATTICE_CMD_SEARCH=1
        fi
        ;;
    $'\033')
        if (( LATTICE_CMD_SEARCH )) ; then
            LATTICE_CMD_SEARCH=0
            lattice_registry_set_query ''
        else
            LATTICE_MODE='tree'
            return 0
        fi
        ;;
    $'\025')
        (( LATTICE_CMD_SEARCH )) && lattice_registry_set_query ''
        ;;
    $'\177'|$'\b')
        if (( LATTICE_CMD_SEARCH )) ; then
            q=$LATTICE_CMD_QUERY
            [[ -n "$q" ]] && lattice_registry_set_query "${q%?}"
        fi
        ;;
    *)
        if (( LATTICE_CMD_SEARCH )) ; then
            case "$key" in
            [[:print:]]) lattice_registry_set_query "$LATTICE_CMD_QUERY$key" ;;
            esac
        else
            case "$key" in
            j|$'\033[B') LATTICE_SELECTED=$((LATTICE_SELECTED+1)) ;;
            k|$'\033[A') LATTICE_SELECTED=$((LATTICE_SELECTED-1)) ;;
            q) LATTICE_MODE='tree' ; return 0 ;;
            esac
        fi
        ;;
    esac
    (( LATTICE_SELECTED < 0 )) && LATTICE_SELECTED=0
    (( LATTICE_SELECTED >= ${#LATTICE_CMD_VIEW[@]} )) && \
        LATTICE_SELECTED=$(( ${#LATTICE_CMD_VIEW[@]} - 1 ))
    (( LATTICE_SELECTED < 0 )) && LATTICE_SELECTED=0
}

lattice_handle_history_key ()
{
    local key=$1
    case "$key" in
    j|$'\033[B'|$'\016') LATTICE_SELECTED=$((LATTICE_SELECTED+1)) ;;
    k|$'\033[A'|$'\020'|$'\013') LATTICE_SELECTED=$((LATTICE_SELECTED-1)) ;;
    $'\r')
        lattice_history_rerun && LATTICE_MODE='tree'
        ;;
    '/') _lattice_history_prompt ;;
    $'\033'|q) LATTICE_MODE='tree' ;;
    esac
    _lattice_select_clamp $(( ${#LATTICE_HISTORY_VIEW[@]} - 1 ))
}

lattice_handle_help_key ()
{
    LATTICE_MODE='tree'
}

lattice_handle_key ()
{
    local key=$1
    # Ctrl-g is the explicit "quit Lattice and close its session" key.
    # Ctrl-b d remains detach. Plain q is intentionally not a quit key.
    if [[ "$key" == $'\007' ]] ; then
        LATTICE_QUIT=1
        return 0
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
                lattice_handle_commands_mouse "$key"
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
    history)  lattice_handle_history_key "$key" ;;
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
