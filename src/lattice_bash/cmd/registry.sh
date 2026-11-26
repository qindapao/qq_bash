# lattice/cmd/registry.sh — configurable command registry
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[registry]++ )) && return 0

declare -ga LATTICE_CMD_IDS=()
declare -ga LATTICE_CMD_NAMES=()
declare -ga LATTICE_CMD_SCOPES=()
declare -ga LATTICE_CMD_TARGETS=()
declare -ga LATTICE_CMD_COMMANDS=()
declare -ga LATTICE_CMD_SNAPSHOTS=()
declare -ga LATTICE_CMD_PARAMS=()
declare -ga LATTICE_CMD_ORIGINS=()
declare -gA LATTICE_CMD_DISABLED=()
declare -gA LATTICE_CMD_NAME_MAP=()
declare -ga LATTICE_CMD_ERRORS=()
declare -ga LATTICE_CMD_HAY=()
declare -ga LATTICE_CMD_VIEW=()
LATTICE_CMD_QUERY=''
LATTICE_CMD_SEARCH=0
LATTICE_CMD_OFFSET=0
LATTICE_CMD_BODY=1
LATTICE_CMD_LOAD_ORIGIN=${LATTICE_CMD_LOAD_ORIGIN:-base}

lattice_command ()
{
    lattice_command_add "$@"
}

lattice_command_add ()
{
    local name=${1:-} scope=${2:-dir} target=${3:-pane} cmd=${4:-} snapshot=${5:-}
    local params='' arg
    for arg in "${@:6}" ; do
        params+="${params:+ }$arg"
    done
    local id i
    [[ -n "$name" && -n "$cmd" ]] || {
        lattice_status "bad command definition (name/cmd required)" error
        return 1
    }
    [[ -n "${LATTICE_CMD_DISABLED[$name]:-}" ]] && return 0
    if [[ -n "${LATTICE_CMD_NAME_MAP[$name]+x}" ]] ; then
        i=${LATTICE_CMD_NAME_MAP[$name]}
        if [[ "${LATTICE_CMD_LOAD_ORIGIN:-base}" == 'user' &&
              "${LATTICE_CMD_ORIGINS[i]:-base}" == 'base' ]] ; then
            # A user command intentionally overrides a shipped command.
            LATTICE_CMD_SCOPES[i]=$scope
            LATTICE_CMD_TARGETS[i]=$target
            LATTICE_CMD_COMMANDS[i]=$cmd
            LATTICE_CMD_SNAPSHOTS[i]=$snapshot
            LATTICE_CMD_PARAMS[i]=$params
            LATTICE_CMD_ORIGINS[i]='user'
            return 0
        fi
        LATTICE_CMD_ERRORS+=("duplicate command: $name")
        return 0
    fi
    id=${#LATTICE_CMD_IDS[@]}
    LATTICE_CMD_IDS+=("$id")
    LATTICE_CMD_NAMES+=("$name")
    LATTICE_CMD_SCOPES+=("$scope")
    LATTICE_CMD_TARGETS+=("$target")
    LATTICE_CMD_COMMANDS+=("$cmd")
    LATTICE_CMD_SNAPSHOTS+=("$snapshot")
    LATTICE_CMD_PARAMS+=("$params")
    LATTICE_CMD_ORIGINS+=("${LATTICE_CMD_LOAD_ORIGIN:-base}")
    LATTICE_CMD_NAME_MAP[$name]=$id
    return 0
}

lattice_registry_reset ()
{
    LATTICE_CMD_ROW_CACHE=()
    LATTICE_CMD_NAME_MAP=()
    LATTICE_CMD_ERRORS=()
    LATTICE_CMD_IDS=()
    LATTICE_CMD_NAMES=()
    LATTICE_CMD_SCOPES=()
    LATTICE_CMD_TARGETS=()
    LATTICE_CMD_COMMANDS=()
    LATTICE_CMD_SNAPSHOTS=()
    LATTICE_CMD_PARAMS=()
    LATTICE_CMD_ORIGINS=()
    LATTICE_CMD_HAY=()
    LATTICE_CMD_VIEW=()
    LATTICE_CMD_QUERY=''
    LATTICE_CMD_SEARCH=0
}

lattice_registry_build_hay ()
{
    local i hay
    LATTICE_CMD_HAY=()
    for ((i=0;i<${#LATTICE_CMD_NAMES[@]};i++)); do
        hay="${LATTICE_CMD_NAMES[i]} ${LATTICE_CMD_SCOPES[i]} ${LATTICE_CMD_TARGETS[i]} ${LATTICE_CMD_COMMANDS[i]} ${LATTICE_CMD_SNAPSHOTS[i]} ${LATTICE_CMD_PARAMS[i]}"
        LATTICE_CMD_HAY+=(" ${hay,,} ")
    done
}

# Build an ordered-subsequence glob once per query term:
#   gst -> *g*s*t*
# Matching is then done by Bash's C-level [[ ... == pattern ]].
_lattice_fuzzy_pattern ()
{
    local term=$1 pat='' ch i
    for ((i=0;i<${#term};i++)); do
        ch=${term:i:1}
        case "$ch" in
        '*'|'?'|'['|']'|'\\') ch="\\$ch" ;;
        esac
        pat+="*$ch"
    done
    REPLY="$pat*"
}

lattice_registry_rebuild_view ()
{
    local i ok term
    local -a terms=() patterns=()
    LATTICE_CMD_VIEW=()

    (( ${#LATTICE_CMD_HAY[@]} == ${#LATTICE_CMD_NAMES[@]} )) || \
        lattice_registry_build_hay

    [[ -n "$LATTICE_CMD_QUERY" ]] && read -ra terms <<< "${LATTICE_CMD_QUERY,,}"

    if (( ${#terms[@]} == 0 )) ; then
        LATTICE_CMD_VIEW=("${!LATTICE_CMD_NAMES[@]}")
    else
        for term in "${terms[@]}" ; do
            _lattice_fuzzy_pattern "$term"
            patterns+=("$REPLY")
        done
        for ((i=0;i<${#LATTICE_CMD_NAMES[@]};i++)); do
            ok=1
            for term in "${patterns[@]}" ; do
                [[ ${LATTICE_CMD_HAY[i]} == $term ]] || { ok=0 ; break ; }
            done
            ((ok)) && LATTICE_CMD_VIEW+=("$i")
        done
    fi
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
    local -A index_of=() used=()
    local -a new_ids=() new_names=() new_scopes=() new_targets=() new_commands=() new_snapshots=() new_params=() new_origins=()
    local name i idx

    for ((i=0;i<${#LATTICE_CMD_NAMES[@]};i++)); do
        index_of[${LATTICE_CMD_NAMES[i]}]=$i
    done
    while IFS= read -r name ; do
        [[ -n "$name" ]] || continue
        [[ -n "${used[$name]:-}" ]] && continue
        idx=${index_of[$name]:-}
        [[ -n "$idx" ]] || continue
        new_ids+=("${LATTICE_CMD_IDS[idx]}")
        new_names+=("${LATTICE_CMD_NAMES[idx]}")
        new_scopes+=("${LATTICE_CMD_SCOPES[idx]}")
        new_targets+=("${LATTICE_CMD_TARGETS[idx]}")
        new_commands+=("${LATTICE_CMD_COMMANDS[idx]}")
        new_snapshots+=("${LATTICE_CMD_SNAPSHOTS[idx]}")
        new_params+=("${LATTICE_CMD_PARAMS[idx]}")
        new_origins+=("${LATTICE_CMD_ORIGINS[idx]}")
        used[$name]=1
    done < "$LATTICE_ORDER_FILE"

    for ((i=0;i<${#LATTICE_CMD_NAMES[@]};i++)); do
        name=${LATTICE_CMD_NAMES[i]}
        [[ -n "${used[$name]:-}" ]] && continue
        new_ids+=("${LATTICE_CMD_IDS[i]}")
        new_names+=("${LATTICE_CMD_NAMES[i]}")
        new_scopes+=("${LATTICE_CMD_SCOPES[i]}")
        new_targets+=("${LATTICE_CMD_TARGETS[i]}")
        new_commands+=("${LATTICE_CMD_COMMANDS[i]}")
        new_snapshots+=("${LATTICE_CMD_SNAPSHOTS[i]}")
        new_params+=("${LATTICE_CMD_PARAMS[i]}")
        new_origins+=("${LATTICE_CMD_ORIGINS[i]}")
        used[$name]=1
    done

    LATTICE_CMD_IDS=("${new_ids[@]}")
    LATTICE_CMD_NAMES=("${new_names[@]}")
    LATTICE_CMD_SCOPES=("${new_scopes[@]}")
    LATTICE_CMD_TARGETS=("${new_targets[@]}")
    LATTICE_CMD_COMMANDS=("${new_commands[@]}")
    LATTICE_CMD_SNAPSHOTS=("${new_snapshots[@]}")
    LATTICE_CMD_PARAMS=("${new_params[@]}")
    LATTICE_CMD_ORIGINS=("${new_origins[@]}")
    LATTICE_CMD_ROW_CACHE=()
    lattice_registry_build_hay

    # Loading is also the cleanup point: drop names that no longer exist in
    # commands.conf and persist newly added commands at the end. This keeps
    # command-order.tsv free of deleted-command residue.
    lattice_registry_save_order 2>/dev/null || true
}

lattice_registry_save_order ()
{
    local tmp expected current
    printf -v expected '%s\n' "${LATTICE_CMD_NAMES[@]}"
    current=$(<"$LATTICE_ORDER_FILE") 2>/dev/null || current=''
    [[ "${current%$'\n'}" == "${expected%$'\n'}" ]] && return 0

    [[ -d "$LATTICE_STATE_DIR" ]] || mkdir -p -- "$LATTICE_STATE_DIR" || return 1
    tmp=$(mktemp "$LATTICE_ORDER_FILE.XXXXXX") || return 1
    printf '%s' "$expected" > "$tmp" || {
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
    tmp=${LATTICE_CMD_SNAPSHOTS[raw_a]} ; LATTICE_CMD_SNAPSHOTS[raw_a]=${LATTICE_CMD_SNAPSHOTS[raw_b]} ; LATTICE_CMD_SNAPSHOTS[raw_b]=$tmp
    tmp=${LATTICE_CMD_PARAMS[raw_a]} ; LATTICE_CMD_PARAMS[raw_a]=${LATTICE_CMD_PARAMS[raw_b]} ; LATTICE_CMD_PARAMS[raw_b]=$tmp
    tmp=${LATTICE_CMD_ORIGINS[raw_a]} ; LATTICE_CMD_ORIGINS[raw_a]=${LATTICE_CMD_ORIGINS[raw_b]} ; LATTICE_CMD_ORIGINS[raw_b]=$tmp
    tmp=${LATTICE_CMD_HAY[raw_a]} ; LATTICE_CMD_HAY[raw_a]=${LATTICE_CMD_HAY[raw_b]} ; LATTICE_CMD_HAY[raw_b]=$tmp

    lattice_registry_save_order || return 1
    LATTICE_CMD_ROW_CACHE=()
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
    local snapshot=${LATTICE_CMD_SNAPSHOTS[raw]}
    local params=${LATTICE_CMD_PARAMS[raw]}
    local origin=${LATTICE_CMD_ORIGINS[raw]}
    local hay=${LATTICE_CMD_HAY[raw]}

    for ((i=raw;i>0;i--)); do
        LATTICE_CMD_IDS[i]=${LATTICE_CMD_IDS[i-1]}
        LATTICE_CMD_NAMES[i]=${LATTICE_CMD_NAMES[i-1]}
        LATTICE_CMD_SCOPES[i]=${LATTICE_CMD_SCOPES[i-1]}
        LATTICE_CMD_TARGETS[i]=${LATTICE_CMD_TARGETS[i-1]}
        LATTICE_CMD_COMMANDS[i]=${LATTICE_CMD_COMMANDS[i-1]}
        LATTICE_CMD_SNAPSHOTS[i]=${LATTICE_CMD_SNAPSHOTS[i-1]}
        LATTICE_CMD_PARAMS[i]=${LATTICE_CMD_PARAMS[i-1]}
        LATTICE_CMD_ORIGINS[i]=${LATTICE_CMD_ORIGINS[i-1]}
        LATTICE_CMD_HAY[i]=${LATTICE_CMD_HAY[i-1]}
    done
    LATTICE_CMD_IDS[0]=$id
    LATTICE_CMD_NAMES[0]=$name
    LATTICE_CMD_SCOPES[0]=$scope
    LATTICE_CMD_TARGETS[0]=$target
    LATTICE_CMD_COMMANDS[0]=$cmd
    LATTICE_CMD_SNAPSHOTS[0]=$snapshot
    LATTICE_CMD_PARAMS[0]=$params
    LATTICE_CMD_ORIGINS[0]=$origin
    LATTICE_CMD_HAY[0]=$hay

    lattice_registry_save_order || return 1
    LATTICE_CMD_ROW_CACHE=()
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

lattice_registry_show_snapshot ()
{
    local idx name text
    lattice_registry_selected_raw_index || {
        lattice_status 'no command selected' error
        return 1
    }
    idx=$REPLY
    text=${LATTICE_CMD_SNAPSHOTS[idx]:-}
    [[ -n "$text" ]] || {
        lattice_status "no snapshot: ${LATTICE_CMD_NAMES[idx]}" error
        return 1
    }
    name=${LATTICE_CMD_NAMES[idx]}
    LATTICE_SNAPSHOT_TEXT=$text
    LATTICE_SNAPSHOT_NAME=$name
    LATTICE_SNAPSHOT_SCROLL=0
    LATTICE_SNAPSHOT_OPEN=1
    return 0
}

lattice_registry_start_params ()
{
    local idx=$1 spec name default
    local -a specs=()
    spec=${LATTICE_CMD_PARAMS[idx]:-}
    if [[ -z "$spec" ]] ; then
        lattice_registry_run_index "$idx"
        return $?
    fi
    read -ra specs <<< "$spec"
    LATTICE_FORM_LABELS=()
    LATTICE_FORM_VALUES=()
    LATTICE_FORM_DEFAULTS=()
    for spec in "${specs[@]}" ; do
        name=${spec%%=*}
        default=''
        [[ "$spec" == *=* ]] && default=${spec#*=}
        [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
            lattice_status "bad parameter name: $name" error
            return 1
        }
        LATTICE_FORM_LABELS+=("$name")
        LATTICE_FORM_VALUES+=("$default")
        LATTICE_FORM_DEFAULTS+=("$default")
    done
    LATTICE_FORM_OPEN=1
    LATTICE_FORM_KIND='params'
    LATTICE_FORM_TITLE="parameters: ${LATTICE_CMD_NAMES[idx]}"
    LATTICE_FORM_INDEX=0
    LATTICE_FORM_CMD_INDEX=$idx
    LATTICE_FORM_CURSORS=()
    local value
    for value in "${LATTICE_FORM_VALUES[@]}" ; do
        LATTICE_FORM_CURSORS+=("${#value}")
    done
    return 0
}

lattice_registry_start_delete ()
{
    local idx name
    lattice_registry_selected_raw_index || return 1
    idx=$REPLY
    name=${LATTICE_CMD_NAMES[idx]}
    LATTICE_FORM_OPEN=1
    LATTICE_FORM_KIND='delete'
    LATTICE_FORM_TITLE="delete: $name"
    LATTICE_FORM_LABELS=('Type y to confirm')
    LATTICE_FORM_VALUES=('')
    LATTICE_FORM_DEFAULTS=('')
    LATTICE_FORM_INDEX=0
    LATTICE_FORM_CMD_INDEX=-1
    LATTICE_FORM_DELETE_NAME=$name
    LATTICE_FORM_CURSORS=(0)
}

lattice_registry_load_disabled ()
{
    LATTICE_CMD_DISABLED=()
    local name
    [[ -f "$LATTICE_DISABLED_FILE" ]] || return 0
    while IFS= read -r name ; do
        [[ -n "$name" ]] && LATTICE_CMD_DISABLED[$name]=1
    done < "$LATTICE_DISABLED_FILE"
}

lattice_registry_disable_name ()
{
    local name=$1
    [[ -n "$name" ]] || return 1
    mkdir -p -- "${LATTICE_DISABLED_FILE%/*}" || return 1
    printf '%s\n' "$name" >> "$LATTICE_DISABLED_FILE" || return 1
    lattice_registry_load || return 1
    lattice_status "disabled command: $name" ok
}

lattice_registry_load ()
{
    lattice_registry_reset
    lattice_registry_load_disabled

    LATTICE_CMD_LOAD_ORIGIN=base
    if [[ -f "$LATTICE_CONFIG" ]] ; then
        # commands.conf is trusted user configuration, like a shell rc file.
        # shellcheck disable=SC1090
        . "$LATTICE_CONFIG" || {
            lattice_status "failed loading $LATTICE_CONFIG" error
            return 1
        }
    else
        lattice_command_add "list directory" "dir" "pane" 'ls -la' || return $?
    fi

    LATTICE_CMD_LOAD_ORIGIN=user
    if [[ -f "$LATTICE_USER_COMMANDS_FILE" ]] ; then
        # shellcheck source=/dev/null
        . "$LATTICE_USER_COMMANDS_FILE" || {
            lattice_status "failed loading $LATTICE_USER_COMMANDS_FILE" error
            return 1
        }
    fi
    LATTICE_CMD_LOAD_ORIGIN=base

    if (( ${#LATTICE_CMD_ERRORS[@]} )) ; then
        local err
        for err in "${LATTICE_CMD_ERRORS[@]}" ; do
            printf 'lattice: %s\n' "$err" >&2
        done
    fi

    if (( ${#LATTICE_CMD_NAMES[@]} == 0 )) ; then
        lattice_status "no commands in $LATTICE_CONFIG" error
        return 1
    fi
    lattice_registry_build_hay
    lattice_registry_apply_order
    lattice_registry_rebuild_view
    if (( ${#LATTICE_CMD_ERRORS[@]} )) ; then
        lattice_status "loaded ${#LATTICE_CMD_NAMES[@]} commands; ${#LATTICE_CMD_ERRORS[@]} duplicate(s) ignored" error
    else
        lattice_status "loaded ${#LATTICE_CMD_NAMES[@]} commands"
    fi
    return 0
}

lattice_registry_reload ()
{
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

lattice_registry_dispatch_index ()
{
    local idx=$1
    if [[ -n "${LATTICE_CMD_PARAMS[idx]:-}" ]] ; then
        lattice_registry_start_params "$idx"
    else
        lattice_registry_run_index "$idx"
    fi
}

lattice_registry_run_index ()
{
    local idx=$1 cmd
    shift
    cmd=${LATTICE_CMD_COMMANDS[idx]:-}
    [[ -n "$cmd" ]] || return 1
    lattice_executor_send "$cmd" "${LATTICE_CMD_TARGETS[idx]:-pane}" "$@" || return $?
    if (( $# == 0 )) ; then
        lattice_history_add "$cmd" "$LATTICE_DIR"
        lattice_status "sent: ${LATTICE_CMD_NAMES[idx]}" ok
    else
        lattice_status "sent with parameters: ${LATTICE_CMD_NAMES[idx]}" ok
    fi
    return 0
}
