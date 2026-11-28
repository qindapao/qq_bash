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
declare -ga LATTICE_CMD_SUBMIT=()
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
    local params='' arg submit='run'
    for arg in "${@:6}" ; do
        params+="${params:+$'\n'}$arg"
    done
    [[ "$name" == @* ]] && submit='insert'
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
            LATTICE_CMD_SUBMIT[i]=$submit
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
    LATTICE_CMD_SUBMIT+=("$submit")
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
    LATTICE_CMD_SUBMIT=()
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
    (( LATTICE_CMD_SELECTED >= ${#LATTICE_CMD_VIEW[@]} )) && \
        LATTICE_CMD_SELECTED=$(( ${#LATTICE_CMD_VIEW[@]} - 1 ))
    (( LATTICE_CMD_SELECTED < 0 )) && LATTICE_CMD_SELECTED=0
}

lattice_registry_set_query ()
{
    LATTICE_CMD_QUERY=$1
    LATTICE_CMD_SELECTED=0
    lattice_registry_rebuild_view
}

lattice_registry_apply_order ()
{
    [[ -f "$LATTICE_ORDER_FILE" ]] || return 0
    local -A index_of=() used=()
    local -a new_ids=() new_names=() new_scopes=() new_targets=() new_commands=() new_snapshots=() new_params=() new_submits=() new_origins=()
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
        new_submits+=("${LATTICE_CMD_SUBMIT[idx]:-run}")
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
        new_submits+=("${LATTICE_CMD_SUBMIT[i]:-run}")
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
    LATTICE_CMD_SUBMIT=("${new_submits[@]}")
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
    local delta=$1 view_pos=$LATTICE_CMD_SELECTED target raw_a raw_b tmp
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
    tmp=${LATTICE_CMD_SUBMIT[raw_a]} ; LATTICE_CMD_SUBMIT[raw_a]=${LATTICE_CMD_SUBMIT[raw_b]} ; LATTICE_CMD_SUBMIT[raw_b]=$tmp
    tmp=${LATTICE_CMD_ORIGINS[raw_a]} ; LATTICE_CMD_ORIGINS[raw_a]=${LATTICE_CMD_ORIGINS[raw_b]} ; LATTICE_CMD_ORIGINS[raw_b]=$tmp
    tmp=${LATTICE_CMD_HAY[raw_a]} ; LATTICE_CMD_HAY[raw_a]=${LATTICE_CMD_HAY[raw_b]} ; LATTICE_CMD_HAY[raw_b]=$tmp

    lattice_registry_save_order || return 1
    LATTICE_CMD_ROW_CACHE=()
    lattice_registry_rebuild_view
    LATTICE_CMD_SELECTED=$target
    lattice_status 'command order saved' ok
    return 0
}

lattice_registry_move_to_top ()
{
    local raw=${LATTICE_CMD_VIEW[LATTICE_CMD_SELECTED]:-} i
    [[ -n "$raw" ]] || return 0
    (( raw > 0 )) || return 0

    local id=${LATTICE_CMD_IDS[raw]}
    local name=${LATTICE_CMD_NAMES[raw]}
    local scope=${LATTICE_CMD_SCOPES[raw]}
    local target=${LATTICE_CMD_TARGETS[raw]}
    local cmd=${LATTICE_CMD_COMMANDS[raw]}
    local snapshot=${LATTICE_CMD_SNAPSHOTS[raw]}
    local params=${LATTICE_CMD_PARAMS[raw]}
    local submit=${LATTICE_CMD_SUBMIT[raw]:-run}
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
        LATTICE_CMD_SUBMIT[i]=${LATTICE_CMD_SUBMIT[i-1]}
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
    LATTICE_CMD_SUBMIT[0]=$submit
    LATTICE_CMD_ORIGINS[0]=$origin
    LATTICE_CMD_HAY[0]=$hay

    lattice_registry_save_order || return 1
    LATTICE_CMD_ROW_CACHE=()
    lattice_registry_rebuild_view
    LATTICE_CMD_SELECTED=0
    lattice_status "pinned: $name" ok
    return 0
}

lattice_registry_open ()
{
    LATTICE_MODE='commands'
    LATTICE_CMD_SEARCH=0
    LATTICE_CMD_QUERY=''
    lattice_registry_rebuild_view
}

lattice_registry_selected_raw_index ()
{
    REPLY=${LATTICE_CMD_VIEW[LATTICE_CMD_SELECTED]:-}
    [[ -n "$REPLY" ]]
}

lattice_registry_show_snapshot ()
{
    local idx cmd snapshot text
    lattice_registry_selected_raw_index || {
        lattice_status 'no command selected' error
        return 1
    }
    idx=$REPLY
    cmd=${LATTICE_CMD_COMMANDS[idx]:-}
    snapshot=${LATTICE_CMD_SNAPSHOTS[idx]:-}
    [[ -n "$cmd" ]] || {
        lattice_status "no command body: ${LATTICE_CMD_NAMES[idx]}" error
        return 1
    }

    text="COMMAND
$cmd"
    if [[ -n "$snapshot" ]] ; then
        text+=$'\n\nSNAPSHOT\n'
        text+=$snapshot
    fi
    LATTICE_SNAPSHOT_TEXT=$text
    LATTICE_SNAPSHOT_SCROLL=0
    LATTICE_SNAPSHOT_OPEN=1
    return 0
}

lattice_registry_start_params ()
{
    local idx=$1 spec name default
    spec=${LATTICE_CMD_PARAMS[idx]:-}
    if [[ -z "$spec" ]] ; then
        lattice_registry_run_index "$idx"
        return $?
    fi
    LATTICE_FORM_LABELS=()
    LATTICE_FORM_VALUES=()
    LATTICE_FORM_DEFAULTS=()
    while IFS= read -r spec ; do
        [[ -n "$spec" ]] || continue
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
    done <<< "$spec"
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

lattice_registry_check_arrays ()
{
    # Every parallel array must stay index-aligned with NAMES. This catches a
    # forgotten reset/order/swap branch after adding a registry field.
    local n=${#LATTICE_CMD_NAMES[@]} field
    local -a fields=(IDS SCOPES TARGETS COMMANDS SNAPSHOTS PARAMS SUBMIT ORIGINS)
    for field in "${fields[@]}" ; do
        local -n ref="LATTICE_CMD_$field"
        if (( ${#ref[@]} != n )) ; then
            local msg="registry array misaligned: $field=${#ref[@]} names=$n"
            printf 'lattice: %s\n' "$msg" >&2
            lattice_status "$msg" error
            return 1
        fi
    done
    return 0
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

    lattice_registry_check_arrays || return 1

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

lattice_ansi_c_word ()
{
    local v=$1 ch
    local -i i esc=0
    [[ ${v:0:2} == "\$'" ]] || return 1
    (( ${#v} >= 3 )) || return 1
    [[ ${v: -1} == "'" ]] || return 1
    for ((i=2;i<${#v}-1;i++)); do
        ch=${v:i:1}
        if (( esc )) ; then
            esc=0
            continue
        fi
        if [[ "$ch" == '\' ]] ; then
            esc=1
            continue
        fi
        [[ "$ch" == "'" ]] && return 1
    done
    (( esc == 0 ))
}

# Expand {{WB_*}} and {{PARAM}} placeholders into shell-quoted literals.
# No shell evaluation is performed; values use the @Q operator.
# A parameter that is one complete $'...' word is inserted verbatim and
# marks the command for preview-only insertion.
lattice_command_expand ()
{
    local cmd=$1
    shift
    local -A values=()
    local pair name value out='' rest prefix
    local selected file=''

    LATTICE_EXPAND_PREVIEW=0
    LATTICE_EXPAND_QUOTED_OK=0
    LATTICE_EXPAND_RAW=0
    if [[ "$cmd" == *'$WB_'* || "$cmd" == *'${WB_'* ||
          "$cmd" == *'$LP_'* || "$cmd" == *'${LP_'* ]] ; then
        lattice_status 'legacy $WB_*/$LP_* in command; use {{...}}' error
        REPLY=''
        return 1
    fi

    lattice_selected_path
    selected=$REPLY
    [[ -f "$selected" ]] && file=$selected
    values[WB_ROOT]=${LATTICE_ROOT:-}
    values[WB_DIR]=${LATTICE_DIR:-}
    values[WB_FILE]=$file
    [[ "$cmd" == *'WB_A'* ]] && { lattice_register_read A; values[WB_A]=$REPLY; }
    [[ "$cmd" == *'WB_B'* ]] && { lattice_register_read B; values[WB_B]=$REPLY; }
    [[ "$cmd" == *'WB_C'* ]] && { lattice_register_read C; values[WB_C]=$REPLY; }
    if [[ "$cmd" == *'WB_CLIP'* ]] ; then
        if ! lattice_clipboard_read ; then
            lattice_status 'clipboard read failed; command not sent' error
            REPLY=''
            return 1
        fi
        values[WB_CLIP]=$REPLY
        lattice_clipboard_cache_write "$REPLY" 2>/dev/null || true
    fi

    for pair in "$@" ; do
        name=${pair%%=*}
        value=${pair#*=}
        [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
            lattice_status "invalid parameter name: $name" error
            REPLY=''
            return 1
        }
        case "$name" in
        WB_ROOT|WB_DIR|WB_FILE|WB_CLIP|WB_A|WB_B|WB_C)
            lattice_status "reserved placeholder: $name" error
            REPLY=''
            return 1
            ;;
        esac
        values[$name]=$value
    done

    rest=$cmd
    while true ; do
        local normal_prefix=${rest%%'{{'*}
        local raw_prefix=${rest%%'[{'*}
        if [[ "$normal_prefix" == "$rest" && "$raw_prefix" == "$rest" ]] ; then
            break
        fi
        if (( ${#normal_prefix} <= ${#raw_prefix} )) ; then
            out+=$normal_prefix
            rest=${rest#*'{{'}
            if [[ "$rest" != *'}}'* ]] ; then
                lattice_status 'unclosed {{...}} in command' error
                REPLY=''
                return 1
            fi
            name=${rest%%'}}'*}
            rest=${rest#*'}}'}
            if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || [[ -z "${values[$name]+_}" ]] ; then
                lattice_status "unknown placeholder: $name" error
                REPLY=''
                return 1
            fi
            value=${values[$name]}
            case "$name" in
            WB_ROOT|WB_DIR|WB_FILE)
                # Filesystem context is trusted: always quote it, never interpret
                # a path that happens to start with $' as shell syntax.
                out+=${value@Q}
                ;;
            *)
                # Parameter/clipboard/register values are user-controlled. A
                # complete $'...' word is an explicit escape hatch; everything
                # else is quoted literally.
                if [[ "${value:0:2}" == "\$'" ]] ; then
                    LATTICE_EXPAND_PREVIEW=1
                    if lattice_ansi_c_word "$value" ; then
                        LATTICE_EXPAND_QUOTED_OK=1
                        out+=$value
                    else
                        out+=${value@Q}
                    fi
                else
                    out+=${value@Q}
                fi
                ;;
            esac
        else
            out+=$raw_prefix
            rest=${rest#*'[{'}
            if [[ ! "${rest:0:1}" =~ [A-Za-z_] ]] ; then
                # Not a raw placeholder; preserve the literal "[{".
                out+='[{'
                continue
            fi
            if [[ "$rest" != *'}]'* ]] ; then
                lattice_status 'unclosed [{...}] in command' error
                REPLY=''
                return 1
            fi
            name=${rest%%'}]'*}
            rest=${rest#*'}]'}
            if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ; then
                lattice_status "invalid raw placeholder: $name" error
                REPLY=''
                return 1
            fi
            if [[ -z "${values[$name]+_}" ]] ; then
                lattice_status "unknown raw placeholder: $name" error
                REPLY=''
                return 1
            fi
            LATTICE_EXPAND_PREVIEW=1
            LATTICE_EXPAND_RAW=1
            out+=${values[$name]}
        fi
    done
    REPLY=$out$rest
    return 0
}

lattice_registry_dispatch_index ()
{
    local idx=$1 now active
    if [[ -n "${TMUX_PANE:-}" ]] ; then
        active=$(lattice_tmux_quick display-message -p -t "$TMUX_PANE" '#{pane_active}' 2>/dev/null)
        # The TUI can still receive queued keystrokes after focus moved to the
        # executor. An inactive TUI must never open a form or dispatch.
        [[ "$active" == 1 ]] || return 0
    fi
    if (( LATTICE_SUPPRESS_DISPATCH_UNTIL )) ; then
        now=${EPOCHREALTIME:-0}
        now=${now//[!0-9]/}
        if (( now > 0 && now < LATTICE_SUPPRESS_DISPATCH_UNTIL )) ; then
            lattice_status 'input settling; try again' error
            return 1
        fi
        LATTICE_SUPPRESS_DISPATCH_UNTIL=0
    fi
    if [[ -n "${LATTICE_CMD_PARAMS[idx]:-}" ]] ; then
        lattice_registry_start_params "$idx"
    else
        lattice_registry_run_index "$idx"
    fi
}

lattice_registry_run_index ()
{
    local idx=$1 raw cmd submit
    local -i preview quoted_ok raw_ok
    shift
    raw=${LATTICE_CMD_COMMANDS[idx]:-}
    submit=${LATTICE_CMD_SUBMIT[idx]:-run}
    [[ -n "$raw" ]] || return 1
    lattice_command_expand "$raw" "$@" || return 1
    cmd=$REPLY
    preview=${LATTICE_EXPAND_PREVIEW:-0}
    quoted_ok=${LATTICE_EXPAND_QUOTED_OK:-0}
    raw_ok=${LATTICE_EXPAND_RAW:-0}
    (( preview )) && submit=insert

    # For insert-only commands, move focus to the executor before sending.
    # Otherwise a fast Enter can still be consumed by the still-active TUI and
    # re-open the parameter form.
    if [[ "$submit" == 'insert' ]] ; then
        # A form may still be the last rendered frame. Repaint without it
        # before focus moves to the executor, otherwise the left pane can keep
        # showing a stale parameter form while the user is typing on the right.
        if declare -F lattice_render >/dev/null ; then
            lattice_render
        fi
        lattice_tmux_focus_executor 2>/dev/null || true
        # Once the executor owns focus, every key already queued for the TUI
        # must be discarded, not just a command dispatch.
        [[ -n "${TMUX_PANE:-}" ]] && LATTICE_INPUT_BLOCKED=1
    fi
    lattice_executor_send "$cmd" "${LATTICE_CMD_TARGETS[idx]:-pane}" "$submit" || return $?
    if [[ "$submit" == 'insert' ]] ; then
        local now=${EPOCHREALTIME:-0}
        now=${now//[!0-9]/}
        (( now > 0 )) && LATTICE_SUPPRESS_ENTER_UNTIL=$(( now + 500000 ))
        (( now > 0 )) && LATTICE_SUPPRESS_DISPATCH_UNTIL=$(( now + 500000 ))
        if [[ "${LATTICE_CMD_NAMES[idx]}" != @* ]] &&
           (( preview )) && (( quoted_ok || raw_ok )) ; then
            lattice_history_add "$cmd" "$LATTICE_DIR"
        fi
        if (( preview )) ; then
            if (( raw_ok )) ; then
                lattice_status "raw placeholder: review; press Enter to run" error
            elif (( quoted_ok )) ; then
                lattice_status "preview: quoted parameter; press Enter to run" ok
            else
                lattice_status "preview: malformed quoted parameter; review before Enter" error
            fi
        else
            lattice_status "inserted skeleton: ${LATTICE_CMD_NAMES[idx]}  Ctrl-b → to edit" ok
        fi
    else
        lattice_history_add "$cmd" "$LATTICE_DIR"
        lattice_status "sent: ${LATTICE_CMD_NAMES[idx]}" ok
    fi
    return 0
}
