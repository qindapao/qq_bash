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

# Originally, the sorting function does not need to be serialized into a Q
# string. The reason why it is retained is because the sort command requires
# is to keep the sorting algorithm consistent
array_qsort ()
{
    local LC_ALL=C
    (($# < 1)) && return 1
    local -n a_arr=$1
    local a_rule=${2:-">"}

    local -i a_n=${#a_arr[@]}
    ((a_n)) || return 2

    ((a_n>100)) && {
        _array_sort_cmd "$1" "$a_rule"
        return $?
    }

    local -a a_a
    case "$a_rule" in
        '>'|'<') a_a=("${a_arr[@]@Q}") ;;
        -[gl]t)  a_a=("${a_arr[@]}") ;;
        *) return 3 ;;
    esac

    local -a a_stack
    local -i a_top=-1 a_left=0 a_right=$((a_n-1))
    local -i a_i a_j a_mid
    local a_pivot a_tmp

    a_stack[++a_top]=$a_left
    a_stack[++a_top]=$a_right

    while ((a_top >= 0)); do
        a_right=${a_stack[a_top--]}
        a_left=${a_stack[a_top--]}

        a_i=$a_left ; a_j=$a_right
        a_mid=$(( (a_left + a_right) / 2 ))
        a_pivot="${a_a[a_mid]}"

        while ((a_i <= a_j)); do
            # ---- Left pointer moves ----
            while ((a_i <= a_j)); do
                case "$a_rule" in
                    '>')   [[ "${a_a[a_i]}" < "$a_pivot" ]] || break ;;
                    '<')   [[ "${a_a[a_i]}" > "$a_pivot" ]] || break ;;
                    '-lt') [[ "${a_a[a_i]}" -gt "$a_pivot" ]] || break ;;
                    '-gt') [[ "${a_a[a_i]}" -lt "$a_pivot" ]] || break ;;
                esac
                ((a_i++))
            done

            # ---- Right pointer moves ----
            while ((a_i <= a_j)); do
                case "$a_rule" in
                    '>')   [[ "${a_a[a_j]}" > "$a_pivot" ]] || break ;;
                    '<')   [[ "${a_a[a_j]}" < "$a_pivot" ]] || break ;;
                    '-lt') [[ "${a_a[a_j]}" -lt "$a_pivot" ]] || break ;;
                    '-gt') [[ "${a_a[a_j]}" -gt "$a_pivot" ]] || break ;;
                esac
                ((a_j--))
            done

            # ---- Swip ----
            if ((a_i <= a_j)); then
                a_tmp="${a_a[a_i]}" ; a_a[a_i]="${a_a[a_j]}" ; a_a[a_j]="$a_tmp"
                ((a_i++, a_j--))
            fi
        done

        # ---- Push subrange onto stack ----
        if ((a_left < a_j)); then
            a_stack[++a_top]=$a_left
            a_stack[++a_top]=$a_j
        fi
        if ((a_i < a_right)); then
            a_stack[++a_top]=$a_i
            a_stack[++a_top]=$a_right
        fi
    done

    case "$a_rule" in
        -[gl]t) a_arr=("${a_a[@]}") ;;
        '>'|'<') eval a_arr=("${a_a[@]}") ;;
    esac
}

_array_sort_cmd ()
{
    local -n a_arr="$1"
    local a_rule="${2}"
    local a_str= a_sorted_str=

    case "$a_rule" in
         -[gl]t) printf -v a_str "%s\n" "${a_arr[@]}" ;;&
            -gt) local -a a_cmd_p=(-n) ;;
            -lt) local -a a_cmd_p=(-rn) ;;
        '>'|'<') printf -v a_str "%s\n" "${a_arr[@]@Q}" ;;&
            '>') local -a a_cmd_p=() ;;
            '<') local -a a_cmd_p=(-r) ;;
    esac

    a_sorted_str=${ sort "${a_cmd_p[@]}" <<<"$a_str";}
    case "$a_rule" in
        -[gl]t)
        a_arr=(${a_sorted_str}) ;;
        '>'|'<')
        eval -- a_arr=(${a_sorted_str}) ;;
    esac
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

return 0

