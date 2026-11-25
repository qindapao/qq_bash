# lattice/ui/event.sh — keyboard loop
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

lattice_handle_tree_key ()
{
    local key=$1 idx q
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
        1|2|3)
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
    :)           lattice_registry_open ;;
    /)           lattice_tree_search_open ;;
    H)           LATTICE_MODE='history'; LATTICE_SELECTED=0; lattice_history_rebuild_view ;;
    '?' )        LATTICE_MODE='help' ;;
    $'\022')     LATTICE_RECENT_FOCUS=1; LATTICE_RECENT_SELECTED=0 ;;
    R)           lattice_registry_reload; lattice_reload_all ;;
    q)           LATTICE_QUIT=1 ;;
    esac
}

lattice_handle_commands_key ()
{
    local key=$1 idx q
    case "$key" in
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
            # Keep the palette open after dispatch; the user exits explicitly.
            lattice_registry_run_index "$idx"
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
    # Ctrl-b d remains detach; q in tree mode is also a clean quit.
    if [[ "$key" == $'\007' ]] ; then
        LATTICE_QUIT=1
        return 0
    fi
    case "$LATTICE_MODE" in
    tree)     lattice_handle_tree_key "$key" ;;
    commands) lattice_handle_commands_key "$key" ;;
    history)  lattice_handle_history_key "$key" ;;
    help)     lattice_handle_help_key "$key" ;;
    esac
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
