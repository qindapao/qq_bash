((_TEST_UTILS_IMPORTED++)) && return 0

# as_ 为保留前缀
AS_OK=0
AS_FAIL=1
AS_NORMAL_CHARS=({a..z} {A..Z} {0..9})
AS_NORMAL_CHARS_LEN=${#AS_NORMAL_CHARS[@]}

# 用于测试的复杂关联数组
readonly -A AS_DICT_TEMP=(
    ["(xx:yy)"]="6" ["xxx->xxx->xxx->xx:xx.x-/dev/fd/61-/dev/fd/60"]="1"
    ["xxx xxx->xxx->xxx->xx:xx.x-/dev/fd/61-/dev/fd/60"]="1"
    ["xxx xxx->xxx->xxx->xx:xx.x->(xxx:xx)->(xxxxx:xxxx)"]="2"
    ["zy 
geg 
"]=" gge geg(xx)[ggel

]ggeeg")


AS_RUN_TEST_CASES='
echo "=== Running tests from script: $0 ==="
echo "=== Start time: $(date "+%Y-%m-%d %H:%M:%S") ==="

for fn in ${ compgen -A function | grep "^test_case" | sort;}; do
    echo "-------- Running $fn ----------"
    "$fn" || exit 1
done
'


# 函数还原后会导致行号等调用栈混乱，慎用
# extdebug 也救不了(只是说 declare -F 可以获取元信息)
# 有什么魔法方法可以让函数恢复元数据的？
save_func ()
{
    declare -F "$1" && {
        REPLY=${ declare -f "$1";}
        return 0
    }
    return 1
}

# 1: 成功
# 0: 失败
log_test ()
{
    local status=$1 num=$2
    local the_caller=${FUNCNAME[1]}
    if ((status)) ; then
        echo "$the_caller $num test pass."
    else
        echo "$the_caller $num test fail."
    fi
}

rand_str ()
{
    local len=${1:-40}
    local i
    for ((i=0; i<len; i++)); do
        REPLY+="${AS_NORMAL_CHARS[RANDOM % AS_NORMAL_CHARS_LEN]}"
    done
}

assert_array ()
{
    if (($#<3)) ; then
        echo "param num:${#}, need >= 3" >&2
        return ${AS_FAIL}
    fi

    # 如果参数任意一个为空都失败
    local _assert_array_param=''
    for _assert_array_param in "${@}" ; do
        if [[ -z "$_assert_array_param" ]] ; then
            echo "param can not be null" >&2
            return ${AS_FAIL}
        fi
    done
    
    # a or A
    local as_type="${1}"
    local -n as_first="${2}"
    shift 2
    local as_index
    while (($#)) ; do
        local -n as_second="${1}"

        # 判断元素数量
        if [[ "${#as_first[@]}" != "${#as_second[@]}" ]] ; then
            return ${AS_FAIL}
        fi

        # 判断类型(防止只读变量的影响)
        if [[ "${as_first@a}" != "$as_type" && "${as_first@a}" != "${as_type}r" ]] ||
            [[ "${as_second@a}" != "$as_type" && "${as_second@a}" != "${as_type}r" ]] ; then
            return ${AS_FAIL}
        fi

        for as_index in "${!as_second[@]}" ; do
            # 判断索引
            if [[ ! -v 'as_first[$as_index]' ]] ; then
                return ${AS_FAIL}1
            fi

            # 判断值
            if [[ "${as_first["$as_index"]}" != "${as_second["$as_index"]}" ]] ; then
                return ${AS_FAIL}
            fi
        done

        # 双向判断
        for as_index in "${!as_first[@]}" ; do
            # 判断索引
            if [[ ! -v 'as_second[$as_index]' ]] ; then
                return ${AS_FAIL}
            fi

            # 判断值
            if [[ "${as_first["$as_index"]}" != "${as_second["$as_index"]}" ]] ; then
                return ${AS_FAIL}
            fi
        done

        shift
    done
    return ${AS_OK}
}

diff_two_str_side_by_side ()
{
    local str1="$1" str2="$2"
    local title1="$4" title2="$5"
    local ret_code=0
    local max1=$(printf "%s" "$str1" | display_max)
    local max2=$(printf "%s" "$str2" | display_max)
    local max=$(( max1 > max2 ? max1 : max2 ))
    local width=$(( max * 2 + 4 ))

    printf '%.0s-' $(seq 1 "$width") ; echo ""
    printf "%-*s    %-*s\n" "$max" "$title1" "$max" "$title2"
    printf '%.0s-' $(seq 1 "$width") ; echo ""
    diff --minimal --side-by-side --expand-tabs --tabsize=4 --color --width=${width} -y <(printf "%s" "$str1") <(printf "%s" "$str2")

    ret_code=${PIPESTATUS[0]}
    echo ""
    return $ret_code
}

display_max()
{
awk '
	BEGIN {
		max = 0
	}
	{
		line = $0
		width = length(line)
		max = (width > max ? width : max)
	}
	END {
		print max
	}'
}

return 0

