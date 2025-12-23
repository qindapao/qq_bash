((_ARRAY_IMPORTED++)) && return 0

# a_ as a reserved prefix
array_sorted_insert ()
{
    local -n a_arr=$1
    local a_value=$2
    # 默认升序
    local a_rule=${3:-">"}

    local a_left=0
    local a_right=${#a_arr[@]}

    # 二分查找插入位置
    case "$a_rule" in
        ">")  # 升序
            while ((a_left < a_right)); do
                local a_mid=$(((a_left + a_right) / 2))
                if [[ "${a_arr[a_mid]}" < "$a_value" ]] ; then
                    a_left=$((a_mid + 1))
                else
                    a_right=$a_mid
                fi
            done
            ;;
        "<")  # 降序
            while ((a_left < a_right)); do
                local a_mid=$(((a_left + a_right) / 2))
                if [[ "${a_arr[a_mid]}" > "$a_value" ]] ; then
                    a_left=$((a_mid + 1))
                else
                    a_right=$a_mid
                fi
            done
            ;;
        "-gt")  # 升序
            while ((a_left < a_right)); do
                local a_mid=$(((a_left + a_right) / 2))
                if [[ "${a_arr[a_mid]}" -lt "$a_value" ]] ; then
                    a_left=$((a_mid + 1))
                else
                    a_right=$a_mid
                fi
            done
            ;;
        "-lt")  # 降序
            while ((a_left < a_right)); do
                local a_mid=$(((a_left + a_right) / 2))
                if [[ "${a_arr[a_mid]}" -gt "$a_value" ]] ; then
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

    # 插入
    a_arr=("${a_arr[@]:0:$a_left}" "$a_value" "${a_arr[@]:$a_left}")
}

array_qsort ()
{
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

return 0


