((_ARRAY_IMPORTED++)) && return 0

# ar_ is a reserved prefix. The incoming reference string cannot use variable
#   names with this prefix.

#-------------------------------------------------------------------------------

# a_ as a reserved prefix
# Q string wrapping is no longer used
array_sorted_insert ()
{
    local -n ar_arr=$1
    local ar_value=$2
    # Default ascending order
    local ar_rule=${3:-">"}

    local ar_left=0 ar_right=${#ar_arr[@]}
    # Sort lexicographically in ASCII
    # LC_ALL
    # LC_xxx(LC_COLLATE LC_CTYPE ...)
    # LANG
    local LC_ALL=C

    # Binary search insertion position
    case "$ar_rule" in
    ">")  # Ascending order
        while ((ar_left < ar_right)); do
            local a_mid=$(((ar_left + ar_right) / 2))
            [[ "${ar_arr[a_mid]}" < "${ar_value}" ]] && ar_left=$((a_mid + 1)) || ar_right=$a_mid
        done
        ;;
    "<")  # descending order
        while ((ar_left < ar_right)); do
            local a_mid=$(((ar_left + ar_right) / 2))
            [[ "${ar_arr[a_mid]}" > "${ar_value}" ]] && ar_left=$((a_mid + 1)) || ar_right=$a_mid
        done
        ;;
    "-gt")  # Ascending order
        while ((ar_left < ar_right)); do
            local a_mid=$(((ar_left + ar_right) / 2))
            (( ar_arr[a_mid] < ar_value )) && ar_left=$((a_mid + 1)) || ar_right=$a_mid
        done
        ;;
    "-lt")  # descending order
        while ((ar_left < ar_right)); do
            local a_mid=$(((ar_left + ar_right) / 2))
            (( ar_arr[a_mid] > ar_value )) && ar_left=$((a_mid + 1)) || ar_right=$a_mid
        done
        ;;
    *)
        echo "Unsupported rule: $ar_rule" >&2
        return 1
        ;;
    esac

    ar_arr=("${ar_arr[@]:0:$ar_left}" "$ar_value" "${ar_arr[@]:$ar_left}")
}

#-------------------------------------------------------------------------------

# $1: array
# $2: the element need to be deleted
array_delete_first_e ()
{
    local -n ar_a=$1
    local ar_del_e=$2
    local ar_i ; for ar_i in "${!ar_a[@]}" ; do
        [[ "$ar_del_e" == "${ar_a[$ar_i]}" ]] && {
            unset -v 'ar_a[$ar_i]' ; return 0 ;
        }
    done
}

#-------------------------------------------------------------------------------

# $1: array
# $2: the element need to be deleted
array_delete_e ()
{
    local -n ar_a=$1
    local ar_del_e=$2
    local ar_i ; for ar_i in "${!ar_a[@]}" ; do
        [[ "$ar_del_e" == "${ar_a[$ar_i]}" ]] && unset -v 'ar_a[$ar_i]'
    done
}

#-------------------------------------------------------------------------------

array_index ()
{
    local element=$1 item
    local -i index=0
    for item in "${@:2}" ; do
        [[ "$element" == "$item" ]] && { REPLY=$index ; return ; }
        ((index++))
    done
    REPLY=-1
}

#-------------------------------------------------------------------------------

# $1: array name
# $2: join string
# You can do this directly
# printf -v xx "%s$sep" "${arr[@]}"
# xx=${xx%"$sep"}
array_join () { local IFS= ; eval -- 'REPLY=${'$1'[*]/%/$2} ; REPLY=${REPLY%"$2"}' ; }

#-------------------------------------------------------------------------------

return 0

