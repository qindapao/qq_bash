declare -gA _BASHLIB_IMPORTED
((_BASHLIB_IMPORTED[data]++)) && return 0

. "${BASH_SOURCE[0]%/*}/x.sh" || return 1

# ==============================================================================
# dataclass: lightweight external containers, not xo objects.
#
# Four kinds:
#   ARR    indexed Bash array
#   ASSOC  associative Bash array
#   DTREE  x tree with OBJ root
#   ATREE  x tree with ARR root
#
# Handles: ARR_1 ASSOC_1 DTREE_1 ATREE_1 ...
# One unified pool records handle -> kind, so liveness/type checks are O(1).
#
# Ownership contract:
#   - one handle has exactly one owner;
#   - do not put a dataclass handle inside another dataclass container;
#   - the owner must call xo_data_bury before dropping the handle;
#   - do not unset a dataclass variable directly.
# ==============================================================================

declare -gA XO_DATA_CLASS_POOL=()
declare -gi XO_DATA_CLASS_IDX=0

# Create one dataclass. $1=ARR|ASSOC|DTREE|ATREE
# @out REPLY=handle
xo_data_born ()
{
    local kind=$1 h
    case "$kind" in
        ARR|ASSOC|DTREE|ATREE) ;;
        *)
            die ERR "xo_data_born: bad kind '${kind}'"
            return 1
            ;;
    esac

    ((XO_DATA_CLASS_IDX++))
    h="${kind}_${XO_DATA_CLASS_IDX}"

    # A handle must not collide with user variables or a stale pool entry.
    if declare -p "$h" >/dev/null 2>&1 || [[ -n "${XO_DATA_CLASS_POOL[$h]+_}" ]] ; then
        die ERR "xo_data_born: handle '${h}' already exists"
        return 1
    fi

    case "$kind" in
        ARR)   declare -ga "$h" ;;
        ASSOC) declare -gA "$h" ;;
        DTREE)
            declare -gA "$h"
            x_init "$h" "$X_TYPE_OBJ" || return $?
            ;;
        ATREE)
            declare -gA "$h"
            x_init "$h" "$X_TYPE_ARR" || return $?
            ;;
    esac

    XO_DATA_CLASS_POOL[$h]=$kind
    REPLY=$h
    return 0
}

# Four explicit born entry points.
xo_data_born_arr   () { xo_data_born ARR ; }
xo_data_born_assoc () { xo_data_born ASSOC ; }
xo_data_born_dtree () { xo_data_born DTREE ; }
xo_data_born_atree () { xo_data_born ATREE ; }

# Destroy one dataclass. $1=handle
xo_data_bury ()
{
    local h=$1
    [[ -n "${XO_DATA_CLASS_POOL[$h]+_}" ]] || {
        die ERR "xo_data_bury: unknown dataclass '${h}'"
        return 1
    }

    unset -v "$h" 'XO_DATA_CLASS_POOL[$h]'
    return 0
}

# Return 0 if handle is live, 1 otherwise.
xo_data_is_live ()
{
    [[ -n "${XO_DATA_CLASS_POOL[$1]+_}" ]]
}

# @out REPLY=ARR|ASSOC|DTREE|ATREE; return 1 if not live.
xo_data_type ()
{
    REPLY=${XO_DATA_CLASS_POOL[$1]:-}
    [[ -n "$REPLY" ]]
}

# Remove every live dataclass. Intended for tests / shutdown, not hot paths.
xo_data_clear ()
{
    unset -v "${!XO_DATA_CLASS_POOL[@]}"
    XO_DATA_CLASS_POOL=()
    return 0
}

return 0
