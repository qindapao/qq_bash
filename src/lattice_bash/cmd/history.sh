# lattice/cmd/history.sh — manual command history
# Only commands dispatched by the Lattice UI are recorded here. Commands run
# inside another pane by other scripts are intentionally not captured.
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[history]++ )) && return 0

declare -ga LATTICE_HISTORY_CMDS=()
declare -ga LATTICE_HISTORY_TIMES=()
declare -ga LATTICE_HISTORY_DIRS=()
declare -ga LATTICE_HISTORY_IDS=()
declare -ga LATTICE_HISTORY_VIEW=()
declare -ga LATTICE_RECENT_CMDS=()
LATTICE_HISTORY_QUERY=''
declare -i LATTICE_HISTORY_NEXT=1
declare -i LATTICE_RECENT_SELECTED=0
LATTICE_RECENT_LIMIT=${LATTICE_RECENT_LIMIT:-8}
LATTICE_HISTORY_LIMIT=${LATTICE_HISTORY_LIMIT:-1000}
(( LATTICE_HISTORY_LIMIT < 1 )) && LATTICE_HISTORY_LIMIT=1

lattice_history_rewrite ()
{
    local i tmp
    [[ -d "$LATTICE_STATE_DIR" ]] || return 1
    tmp=$(mktemp "$LATTICE_HISTORY_FILE.XXXXXX") || return 1
    for ((i=0;i<${#LATTICE_HISTORY_CMDS[@]};i++)); do
        printf '%s\t%s\t%s\t%s\n' \
            "${LATTICE_HISTORY_IDS[i]}" \
            "${LATTICE_HISTORY_TIMES[i]}" \
            "${LATTICE_HISTORY_DIRS[i]}" \
            "${LATTICE_HISTORY_CMDS[i]}" >> "$tmp" || {
                rm -f -- "$tmp"
                return 1
            }
    done
    mv -f -- "$tmp" "$LATTICE_HISTORY_FILE"
}

lattice_history_trim ()
{
    local total=${#LATTICE_HISTORY_CMDS[@]} drop
    (( total <= LATTICE_HISTORY_LIMIT )) && return 0
    drop=$(( total - LATTICE_HISTORY_LIMIT ))
    LATTICE_HISTORY_IDS=("${LATTICE_HISTORY_IDS[@]:drop}")
    LATTICE_HISTORY_TIMES=("${LATTICE_HISTORY_TIMES[@]:drop}")
    LATTICE_HISTORY_DIRS=("${LATTICE_HISTORY_DIRS[@]:drop}")
    LATTICE_HISTORY_CMDS=("${LATTICE_HISTORY_CMDS[@]:drop}")
    lattice_history_rewrite
}

lattice_history_init ()
{
    [[ -d "$LATTICE_STATE_DIR" ]] || mkdir -p -- "$LATTICE_STATE_DIR" || return 1
    [[ -f "$LATTICE_HISTORY_FILE" ]] || : > "$LATTICE_HISTORY_FILE"

    local line id ts dir cmd
    while IFS=$'\t' read -r id ts dir cmd ; do
        [[ -n "$id" ]] || continue
        LATTICE_HISTORY_IDS+=("$id")
        LATTICE_HISTORY_TIMES+=("$ts")
        LATTICE_HISTORY_DIRS+=("$dir")
        LATTICE_HISTORY_CMDS+=("$cmd")
        (( LATTICE_HISTORY_NEXT <= id )) && LATTICE_HISTORY_NEXT=$((id + 1))
    done < "$LATTICE_HISTORY_FILE"
    lattice_history_trim
    lattice_history_rebuild_view
    lattice_recent_refresh
    return 0
}

lattice_history_add ()
{
    local cmd=$1 dir=${2:-$LATTICE_DIR} id ts
    id=$LATTICE_HISTORY_NEXT
    ((LATTICE_HISTORY_NEXT++))
    ts=$(date +%s)

    # Keep the file human-readable and easy to grep; tabs are the only
    # separator. Commands containing tabs are rare and are normalized.
    cmd=${cmd//$'\t'/ }
    cmd=${cmd//$'\n'/ }
    printf '%s\t%s\t%s\t%s\n' "$id" "$ts" "$dir" "$cmd" >> "$LATTICE_HISTORY_FILE"

    LATTICE_HISTORY_IDS+=("$id")
    LATTICE_HISTORY_TIMES+=("$ts")
    LATTICE_HISTORY_DIRS+=("$dir")
    LATTICE_HISTORY_CMDS+=("$cmd")
    lattice_history_trim
    lattice_history_rebuild_view
    lattice_recent_refresh
    return 0
}

lattice_recent_refresh ()
{
    local i cmd
    local -A seen=()
    LATTICE_RECENT_CMDS=()
    for ((i=${#LATTICE_HISTORY_CMDS[@]}-1;i>=0;i--)); do
        cmd=${LATTICE_HISTORY_CMDS[i]}
        [[ -n "$cmd" && -z "${seen[$cmd]+_}" ]] || continue
        seen[$cmd]=1
        LATTICE_RECENT_CMDS+=("$cmd")
        (( ${#LATTICE_RECENT_CMDS[@]} >= LATTICE_RECENT_LIMIT )) && break
    done
    (( LATTICE_RECENT_SELECTED >= ${#LATTICE_RECENT_CMDS[@]} )) && \
        LATTICE_RECENT_SELECTED=$(( ${#LATTICE_RECENT_CMDS[@]} - 1 ))
    (( LATTICE_RECENT_SELECTED < 0 )) && LATTICE_RECENT_SELECTED=0
}

lattice_recent_selected ()
{
    REPLY=${LATTICE_RECENT_CMDS[LATTICE_RECENT_SELECTED]:-}
    [[ -n "$REPLY" ]]
}

lattice_recent_run_index ()
{
    local idx=$1 cmd
    cmd=${LATTICE_RECENT_CMDS[idx]:-}
    [[ -n "$cmd" ]] || return 1
    lattice_executor_send "$cmd" || return $?
    lattice_history_add "$cmd" "$LATTICE_DIR"
    LATTICE_MODE='tree'
    LATTICE_RECENT_FOCUS=0
    lattice_status "rerun: $cmd" ok
    return 0
}

lattice_history_rebuild_view ()
{
    local i s
    LATTICE_HISTORY_VIEW=()
    for ((i=${#LATTICE_HISTORY_CMDS[@]}-1;i>=0;i--)); do
        s=${LATTICE_HISTORY_CMDS[i]}
        if [[ -n "$LATTICE_HISTORY_QUERY" ]] ; then
            [[ "${s,,}" == *"${LATTICE_HISTORY_QUERY,,}"* ]] || continue
        fi
        LATTICE_HISTORY_VIEW+=("$i")
    done
}

lattice_history_set_query ()
{
    LATTICE_HISTORY_QUERY=$1
    lattice_history_rebuild_view
}

lattice_history_selected ()
{
    local vi=${LATTICE_HISTORY_SELECTED:-0} idx
    idx=${LATTICE_HISTORY_VIEW[vi]:-}
    [[ -n "$idx" ]] || return 1
    REPLY=${LATTICE_HISTORY_CMDS[idx]}
    return 0
}

lattice_history_rerun ()
{
    local cmd
    lattice_history_selected || {
        lattice_status 'no history entry selected' error
        return 1
    }
    cmd=$REPLY
    lattice_executor_send "$cmd" || return $?
    lattice_history_add "$cmd" "$LATTICE_DIR"
    lattice_status "sent from history: $cmd" ok
    return 0
}
