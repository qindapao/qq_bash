((_ARRAY_IMPORTED++)) && return 0


# If you need to create an empty array, you can use the following method to
# obtain it through prototype slicing
# If the prototype is not enough, expand it first, which is faster than
# directly creating an empty array.
# https://github.com/akinomyoga/ble.sh/blob/master/src/util.sh
# _ble_array_prototype=()
# function ble/array#reserve-prototype {
#   local n=$1 i
#   for ((i=${#_ble_array_prototype[@]};i<n;i++)); do
#     _ble_array_prototype[i]=
#   done
# }
# arr=("${_ble_array_prototype[@]::n}")
# replace
# for ((i=0;i<n;i++)); do arr[i]=; done
# 


# a_ as a reserved prefix
# Q string wrapping is no longer used
array_sorted_insert ()
{
    local -n a_arr=$1
    local a_value=$2
    # Default ascending order
    local a_rule=${3:-">"}

    local a_left=0
    local a_right=${#a_arr[@]}
    # Sort lexicographically in ASCII
    # LC_ALL
    # LC_xxx(LC_COLLATE LC_CTYPE ...)
    # LANG
    local LC_ALL=C

    # Binary search insertion position
    case "$a_rule" in
        ">")  # Ascending order
            while ((a_left < a_right)); do
                local a_mid=$(((a_left + a_right) / 2))
                if [[ "${a_arr[a_mid]}" < "${a_value}" ]] ; then
                    a_left=$((a_mid + 1))
                else
                    a_right=$a_mid
                fi
            done
            ;;
        "<")  # descending order
            while ((a_left < a_right)); do
                local a_mid=$(((a_left + a_right) / 2))
                if [[ "${a_arr[a_mid]}" > "${a_value}" ]] ; then
                    a_left=$((a_mid + 1))
                else
                    a_right=$a_mid
                fi
            done
            ;;
        "-gt")  # Ascending order
            while ((a_left < a_right)); do
                local a_mid=$(((a_left + a_right) / 2))
                if (( a_arr[a_mid] < a_value )) ; then
                    a_left=$((a_mid + 1))
                else
                    a_right=$a_mid
                fi
            done
            ;;
        "-lt")  # descending order
            while ((a_left < a_right)); do
                local a_mid=$(((a_left + a_right) / 2))
                if (( a_arr[a_mid] > a_value )) ; then
                    a_left=$((a_mid + 1))
                else
                    a_right=$a_mid
                fi
            done
            ;;
        *)
            echo "Unsupported rule: $a_rule" >&2
            return 1
            ;;
    esac

    a_arr=("${a_arr[@]:0:$a_left}" "$a_value" "${a_arr[@]:$a_left}")
}

_array_delete_first_e ()
{
    local a=$1 i="i_$1"
    REPLY='

    local '$i'
    for '$i' in "${!'$a'[@]}" ; do
        [[ "$2" == "${'$a'[$'$i']}" ]] && {
            unset -v '\'''$a'[$'$i']'\''
            return 0
        }
    done
    '
}

array_delete_first_e ()
{
    eval -- "${|_array_delete_first_e "$@";}"
}

_array_delete_e ()
{
    local a=$1 i="i_$1"
    REPLY='

    local '$i'
    for '$i' in "${!'$a'[@]}" ; do
        [[ "$2" == "${'$a'[$'$i']}" ]] && {
            unset -v '\'''$a'[$'$i']'\''
        }
    done
    '
}

array_delete_e ()
{
    eval -- "${|_array_delete_e "$@";}"
}


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


# # "a" is a subset of "b"
# local -a 'a=({0..5})' 'b=({0..10})'
# isSubset a b
# echo $? # true
_array_is_subset ()
{
    local a=$1 b=$2 i="item_$1$2"

    REPLY='
        ((${'$a'@a} == ${'$b'@a})) || return 1
        ((${#'$a'[@]} <= ${#'$b'[@]})) || return 1

        local '$i'
        for '$i' in "${!'$a'[@]}" ; do
            [[ -v '\'''$b'["$'$i'"]'\'' && "${'$a'[$'$i']}" == "${'$b'[$'$i']}" ]] || return 1
        done

        return 0'
}

# The writing method of dividing it into two functions is actually faster
# than writing it directly into one function!
# The reason is that the expansion rules of eval are simpler when
# written as two functions separately.
array_is_subset ()
{
    eval -- "${|_array_is_subset "$@";}"
}

# array_is_subset ()
# {
#     eval -- "${|
#     local a=$1 b=$2 i="item_$1$2"
#     REPLY='
#
#     [[ ${'$a'@a} == ${'$b'@a} ]] || return 1
#     ((${#'$a'[@]} <= ${#'$b'[@]})) || return 1
#
#     local '$i'
#     for '$i' in "${!'$a'[@]}" ; do
#         [[ -v '\'''$b'["$'$i'"]'\'' && "${'$a'[$'$i']}" == "${'$b'[$'$i']}" ]] || return 1
#     done
#
#     return 0
#
#     ';}"
# }

# $1: array name
# $2: join string
# You can do this directly
# printf -v xx "%s$sep" "${arr[@]}"
# xx=${xx%"$sep"}
array_join ()
{
    local IFS=
    eval -- 'REPLY=${'$1'[*]/%/$2} ; REPLY=${REPLY%"$2"}'
}

return 0

