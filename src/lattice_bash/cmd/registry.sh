# lattice/cmd/registry.sh — configurable quick-command registry
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[registry]++ )) && return 0

declare -ga LATTICE_CMD_IDS=()
declare -ga LATTICE_CMD_NAMES=()
declare -ga LATTICE_CMD_SCOPES=()
declare -ga LATTICE_CMD_TARGETS=()
declare -ga LATTICE_CMD_COMMANDS=()
declare -ga LATTICE_CMD_VIEW=()
LATTICE_CMD_QUERY=''
LATTICE_CMD_SEARCH=0
LATTICE_COMMAND_TREE=''

lattice_command ()
{
    lattice_command_add "$@"
}

lattice_command_add ()
{
    local name=${1:-} scope=${2:-dir} target=${3:-pane} cmd=${4:-}
    local id path
    [[ -n "$name" && -n "$cmd" ]] || {
        lattice_status "bad command definition (name/cmd required)" error
        return 1
    }
    id=${#LATTICE_CMD_IDS[@]}
    path="{cmd}$X{$id}$X"
    x_insert "$LATTICE_COMMAND_TREE" "${path}{name}$X" "$name" || return $?
    x_insert "$LATTICE_COMMAND_TREE" "${path}{scope}$X" "$scope" || return $?
    x_insert "$LATTICE_COMMAND_TREE" "${path}{target}$X" "$target" || return $?
    x_insert "$LATTICE_COMMAND_TREE" "${path}{command}$X" "$cmd" || return $?

    LATTICE_CMD_IDS+=("$id")
    LATTICE_CMD_NAMES+=("$name")
    LATTICE_CMD_SCOPES+=("$scope")
    LATTICE_CMD_TARGETS+=("$target")
    LATTICE_CMD_COMMANDS+=("$cmd")
    return 0
}

lattice_registry_reset ()
{
    LATTICE_CMD_IDS=()
    LATTICE_CMD_NAMES=()
    LATTICE_CMD_SCOPES=()
    LATTICE_CMD_TARGETS=()
    LATTICE_CMD_COMMANDS=()
    LATTICE_CMD_VIEW=()
    LATTICE_CMD_QUERY=''
    LATTICE_CMD_SEARCH=0
    [[ -n "$LATTICE_COMMAND_TREE" ]] && xo_data_bury "$LATTICE_COMMAND_TREE" 2>/dev/null
    LATTICE_COMMAND_TREE=''
}

# Case-insensitive subsequence match. "gs" matches "git status", "gst" too.
_lattice_fuzzy_match ()
{
    local q=${1,,} h=${2,,}
    local -i qi=0 hi=0
    while (( qi < ${#q} && hi < ${#h} )) ; do
        [[ "${h:hi:1}" == "${q:qi:1}" ]] && ((qi++))
        ((hi++))
    done
    (( qi == ${#q} ))
}

lattice_registry_rebuild_view ()
{
    local i hay term ok
    local -a terms=()
    LATTICE_CMD_VIEW=()
    [[ -n "$LATTICE_CMD_QUERY" ]] && read -ra terms <<< "${LATTICE_CMD_QUERY,,}"

    for ((i=0;i<${#LATTICE_CMD_IDS[@]};i++)); do
        if (( ${#terms[@]} == 0 )) ; then
            LATTICE_CMD_VIEW+=("$i")
            continue
        fi
        hay="${LATTICE_CMD_NAMES[i]} ${LATTICE_CMD_SCOPES[i]} ${LATTICE_CMD_TARGETS[i]} ${LATTICE_CMD_COMMANDS[i]}"
        hay=${hay,,}
        ok=1
        for term in "${terms[@]}" ; do
            _lattice_fuzzy_match "$term" "$hay" || { ok=0 ; break ; }
        done
        ((ok)) && LATTICE_CMD_VIEW+=("$i")
    done
    (( LATTICE_SELECTED >= ${#LATTICE_CMD_VIEW[@]} )) && \
        LATTICE_SELECTED=$(( ${#LATTICE_CMD_VIEW[@]} - 1 ))
    (( LATTICE_SELECTED < 0 )) && LATTICE_SELECTED=0
}

lattice_registry_set_query ()
{
    LATTICE_CMD_QUERY=$1
    LATTICE_SELECTED=0
    lattice_registry_rebuild_view
}

lattice_registry_apply_order ()
{
    [[ -f "$LATTICE_ORDER_FILE" ]] || return 0
    local -a new_ids=() new_names=() new_scopes=() new_targets=() new_commands=()
    local -A used=()
    local name i
    while IFS= read -r name ; do
        [[ -n "$name" ]] || continue
        [[ -n "${used[$name]:-}" ]] && continue
        for ((i=0;i<${#LATTICE_CMD_NAMES[@]};i++)); do
            [[ "${LATTICE_CMD_NAMES[i]}" == "$name" ]] || continue
            new_ids+=("${LATTICE_CMD_IDS[i]}")
            new_names+=("${LATTICE_CMD_NAMES[i]}")
            new_scopes+=("${LATTICE_CMD_SCOPES[i]}")
            new_targets+=("${LATTICE_CMD_TARGETS[i]}")
            new_commands+=("${LATTICE_CMD_COMMANDS[i]}")
            used[$name]=1
            break
        done
    done < "$LATTICE_ORDER_FILE"

    for ((i=0;i<${#LATTICE_CMD_NAMES[@]};i++)); do
        name=${LATTICE_CMD_NAMES[i]}
        [[ -n "${used[$name]:-}" ]] && continue
        new_ids+=("${LATTICE_CMD_IDS[i]}")
        new_names+=("${LATTICE_CMD_NAMES[i]}")
        new_scopes+=("${LATTICE_CMD_SCOPES[i]}")
        new_targets+=("${LATTICE_CMD_TARGETS[i]}")
        new_commands+=("${LATTICE_CMD_COMMANDS[i]}")
        used[$name]=1
    done

    LATTICE_CMD_IDS=("${new_ids[@]}")
    LATTICE_CMD_NAMES=("${new_names[@]}")
    LATTICE_CMD_SCOPES=("${new_scopes[@]}")
    LATTICE_CMD_TARGETS=("${new_targets[@]}")
    LATTICE_CMD_COMMANDS=("${new_commands[@]}")
}

lattice_registry_save_order ()
{
    local tmp
    mkdir -p -- "$LATTICE_STATE_DIR" || return 1
    tmp=$(mktemp "$LATTICE_ORDER_FILE.XXXXXX") || return 1
    printf '%s\n' "${LATTICE_CMD_NAMES[@]}" > "$tmp" || {
        rm -f -- "$tmp"
        return 1
    }
    mv -f -- "$tmp" "$LATTICE_ORDER_FILE"
}

lattice_registry_move_selected ()
{
    local delta=$1 view_pos=$LATTICE_SELECTED target raw_a raw_b tmp
    target=$(( view_pos + delta ))
    (( target < 0 )) && target=0
    (( target >= ${#LATTICE_CMD_VIEW[@]} )) && target=$(( ${#LATTICE_CMD_VIEW[@]} - 1 ))
    (( target == view_pos )) && return 0

    raw_a=${LATTICE_CMD_VIEW[view_pos]}
    raw_b=${LATTICE_CMD_VIEW[target]}

    tmp=${LATTICE_CMD_IDS[raw_a]} ; LATTICE_CMD_IDS[raw_a]=${LATTICE_CMD_IDS[raw_b]} ; LATTICE_CMD_IDS[raw_b]=$tmp
    tmp=${LATTICE_CMD_NAMES[raw_a]} ; LATTICE_CMD_NAMES[raw_a]=${LATTICE_CMD_NAMES[raw_b]} ; LATTICE_CMD_NAMES[raw_b]=$tmp
    tmp=${LATTICE_CMD_SCOPES[raw_a]} ; LATTICE_CMD_SCOPES[raw_a]=${LATTICE_CMD_SCOPES[raw_b]} ; LATTICE_CMD_SCOPES[raw_b]=$tmp
    tmp=${LATTICE_CMD_TARGETS[raw_a]} ; LATTICE_CMD_TARGETS[raw_a]=${LATTICE_CMD_TARGETS[raw_b]} ; LATTICE_CMD_TARGETS[raw_b]=$tmp
    tmp=${LATTICE_CMD_COMMANDS[raw_a]} ; LATTICE_CMD_COMMANDS[raw_a]=${LATTICE_CMD_COMMANDS[raw_b]} ; LATTICE_CMD_COMMANDS[raw_b]=$tmp

    lattice_registry_save_order || return 1
    lattice_registry_rebuild_view
    LATTICE_SELECTED=$target
    lattice_status 'command order saved' ok
    return 0
}

lattice_registry_move_to_top ()
{
    local raw=${LATTICE_CMD_VIEW[LATTICE_SELECTED]:-} i
    [[ -n "$raw" ]] || return 0
    (( raw > 0 )) || return 0

    local id=${LATTICE_CMD_IDS[raw]}
    local name=${LATTICE_CMD_NAMES[raw]}
    local scope=${LATTICE_CMD_SCOPES[raw]}
    local target=${LATTICE_CMD_TARGETS[raw]}
    local cmd=${LATTICE_CMD_COMMANDS[raw]}

    for ((i=raw;i>0;i--)); do
        LATTICE_CMD_IDS[i]=${LATTICE_CMD_IDS[i-1]}
        LATTICE_CMD_NAMES[i]=${LATTICE_CMD_NAMES[i-1]}
        LATTICE_CMD_SCOPES[i]=${LATTICE_CMD_SCOPES[i-1]}
        LATTICE_CMD_TARGETS[i]=${LATTICE_CMD_TARGETS[i-1]}
        LATTICE_CMD_COMMANDS[i]=${LATTICE_CMD_COMMANDS[i-1]}
    done
    LATTICE_CMD_IDS[0]=$id
    LATTICE_CMD_NAMES[0]=$name
    LATTICE_CMD_SCOPES[0]=$scope
    LATTICE_CMD_TARGETS[0]=$target
    LATTICE_CMD_COMMANDS[0]=$cmd

    lattice_registry_save_order || return 1
    lattice_registry_rebuild_view
    LATTICE_SELECTED=0
    lattice_status "pinned: $name" ok
    return 0
}

lattice_registry_open ()
{
    LATTICE_MODE='commands'
    LATTICE_CMD_SEARCH=0
    LATTICE_CMD_QUERY=''
    LATTICE_SELECTED=0
    lattice_registry_rebuild_view
}

lattice_registry_selected_raw_index ()
{
    REPLY=${LATTICE_CMD_VIEW[LATTICE_SELECTED]:-}
    [[ -n "$REPLY" ]]
}

lattice_registry_load ()
{
    lattice_registry_reset
    xo_data_born_dtree || return $?
    LATTICE_COMMAND_TREE=$REPLY

    if [[ -f "$LATTICE_CONFIG" ]] ; then
        # commands.conf is trusted user configuration, like a shell rc file.
        # shellcheck disable=SC1090
        . "$LATTICE_CONFIG" || {
            lattice_status "failed loading $LATTICE_CONFIG" error
            return 1
        }
    else
        lattice_command_add "list" "l" "dir" "pane" 'ls -la' || return $?
    fi

    if (( ${#LATTICE_CMD_IDS[@]} == 0 )) ; then
        lattice_status "no commands in $LATTICE_CONFIG" error
        return 1
    fi
    lattice_registry_apply_order
    lattice_registry_rebuild_view
    lattice_status "loaded ${#LATTICE_CMD_IDS[@]} commands"
    return 0
}

lattice_registry_reload ()
{
    local old_status=$LATTICE_STATUS
    if ! lattice_registry_load ; then
        LATTICE_STATUS="reload failed; previous registry may be partial"
        LATTICE_STATUS_KIND=error
        return 1
    fi
    LATTICE_MODE='tree'
    return 0
}

lattice_registry_index_for_name ()
{
    local name=$1 i
    for ((i=0;i<${#LATTICE_CMD_NAMES[@]};i++)); do
        [[ "${LATTICE_CMD_NAMES[i]}" == "$name" ]] && {
            REPLY=$i
            return 0
        }
    done
    return 1
}

# Build the command line sent to the executor. Values are injected as
# environment variables, so config commands can use "$WB_FILE" etc. without
# this function interpolating them into a shell string.
lattice_command_expand ()
{
    local cmd=$1 selected file=''
    lattice_selected_path
    selected=$REPLY
    [[ -f "$selected" ]] && file=$selected
    printf -v REPLY 'WB_ROOT=%q WB_DIR=%q WB_FILE=%q %s' \
        "$LATTICE_ROOT" "$LATTICE_DIR" "$file" "$cmd"
}

lattice_registry_run_index ()
{
    local idx=$1 cmd
    cmd=${LATTICE_CMD_COMMANDS[idx]:-}
    [[ -n "$cmd" ]] || return 1
    lattice_executor_send "$cmd" "${LATTICE_CMD_TARGETS[idx]:-pane}" || return $?
    lattice_history_add "$cmd" "$LATTICE_DIR"
    lattice_status "sent: ${LATTICE_CMD_NAMES[idx]}" ok
    return 0
}
