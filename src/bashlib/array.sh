declare -gA _BASHLIB_IMPORTED
((_BASHLIB_IMPORTED[array]++)) && return 0

. "${BASH_SOURCE[0]%/*}/grammar.sh"

#-------------------------------------------------------------------------------

# a_ as a reserved prefix
# Q string wrapping is no longer used
array_sorted_insert ()
{
    local -n arr=$1
    local value=$2
    # Default ascending order
    local ar_rule=${3:-">"}

    local ar_left=0 ar_right=${#arr[@]}
    # Sort lexicographically in ASCII
    # LC_ALL
    # LC_xxx(LC_COLLATE LC_CTYPE ...)
    # LANG
    local LC_ALL=C

    # Binary search insertion position
    case "$ar_rule" in
    # Ascending order
    ">")
        while ((ar_left < ar_right)); do
            local a_mid=$(((ar_left + ar_right) / 2))
            [[ "${arr[a_mid]}" < "${value}" ]] && ar_left=$((a_mid + 1)) || ar_right=$a_mid
        done
        ;;
    # descending order
    "<")
        while ((ar_left < ar_right)); do
            local a_mid=$(((ar_left + ar_right) / 2))
            [[ "${arr[a_mid]}" > "${value}" ]] && ar_left=$((a_mid + 1)) || ar_right=$a_mid
        done
        ;;
    # Ascending order
    "-gt")
        while ((ar_left < ar_right)); do
            local a_mid=$(((ar_left + ar_right) / 2))
            (( arr[a_mid] < value )) && ar_left=$((a_mid + 1)) || ar_right=$a_mid
        done
        ;;
    # descending order
    "-lt")
        while ((ar_left < ar_right)); do
            local a_mid=$(((ar_left + ar_right) / 2))
            (( arr[a_mid] > value )) && ar_left=$((a_mid + 1)) || ar_right=$a_mid
        done
        ;;
    *)
        echo "Unsupported rule: $ar_rule" >&2
        return 1
        ;;
    esac

    arr=("${arr[@]:0:$ar_left}" "$value" "${arr[@]:$ar_left}")
}

#-------------------------------------------------------------------------------

# 只支持索引数组。关联数组的键遍历顺序未定义，"first"没有确定含义，
# 不要把它用于关联数组。
# @in  $1=数组名（索引数组）  $2=要删除的元素
array_delete_first_e ()
{
    local -n a=$1
    local i ; for i in "${!a[@]}" ; do
        [[ "$2" == "${a[$i]}" ]] && {
            unset -v 'a[$i]' ; return 0 ;
        }
    done
}

#-------------------------------------------------------------------------------

# 删除所有匹配元素；索引数组和关联数组都可以。
# @in  $1=数组名  $2=要删除的元素
array_delete_e ()
{
    local -n a=$1
    local i ; for i in "${!a[@]}" ; do
        [[ "$2" == "${a[$i]}" ]] && unset -v 'a[$i]'
    done
}

#-------------------------------------------------------------------------------

# 在值列表中查找元素位置。
# @in  $1=目标值  $2..=待查找的值列表
# @out REPLY=首个匹配位置（0 起）；未找到为 -1
# @ret 0
array_index ()
{
    local e=$1
    shift
    local item
    local -i idx=0
    for item in "$@" ; do
        [[ "$e" == "$item" ]] && { REPLY=$idx ; return 0 ; }
        ((idx++))
    done
    REPLY=-1
    return 0
}

#-------------------------------------------------------------------------------

# $1: array name
# $2: join string
# 用 printf 一次拼完：格式 "%s<sep>" 会按参数重复。
# 分隔符里的 \ 和 % 必须先转义——它们在 printf 格式串里有含义，
# 不转义时 sep='%s' / '%' / '\t' 会被当格式符（实测拼坏）。
# 不用旧 eval 写法：数组名会被拼进代码（可注入），且分隔符里的 & 会被
# patsub_replacement 当替换引用吞掉。见宪法 §6。
array_join ()
{
    local -n _aj_arr=$1
    local _aj_sep=$2
    local _aj_esc
    # 先转义反斜杠，再转义 %：顺序不能反，否则后插入的 \ 不会被处理。
    _aj_esc=${_aj_sep//'\'/'\\'}
    _aj_esc=${_aj_esc//%/%%}
    printf -v REPLY "%s$_aj_esc" "${_aj_arr[@]}"
    REPLY=${REPLY%"$_aj_sep"}
}

#-------------------------------------------------------------------------------

array_to_kv_q_str ()
{
    REPLY=
    local -n arr=$1
    local key
    local -a parts=()
    
    for key in "${!arr[@]}" ; do
        parts+=("[${key@Q}]=${arr[$key]@Q}")
    done
    REPLY="${parts[*]}"
}

#-------------------------------------------------------------------------------

return 0

