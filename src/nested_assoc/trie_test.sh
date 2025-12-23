#!/usr/bin/env bash

. trie.sh

diff_two_str_side_by_side ()
{
local str1="$1" str2="$2" result_file="$3"
local title1="$4" title2="$5"
local ret_code=0
local max1=$(printf "%s" "$str1" | display_max)
local max2=$(printf "%s" "$str2" | display_max)
local max=$(( max1 > max2 ? max1 : max2 ))
local width=$(( max * 2 + 4 ))

{
printf '%.0s-' $(seq 1 "$width") ; echo ""
printf "%-*s    %-*s\n" "$max" "$title1" "$max" "$title2"
printf '%.0s-' $(seq 1 "$width") ; echo ""
diff --minimal --side-by-side --expand-tabs --tabsize=4 --color --width=${width} -y <(printf "%s" "$str1") <(printf "%s" "$str2")
} | tee "$result_file"

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

# trie_get_subtree
test_case1 ()
{
    eval -- local -A t=(${|trie_init;})
    trie_insert t "lev1-1${S}lev2-1${S}lev3-1${S}" '1'
    trie_insert t "lev1-1${S}lev2-1${S}lev3-2${S}" '2'
    trie_insert t "lev1-1${S}lev2-1${S}lev3-3${S}" '3'
    trie_insert t "lev1-1${S}lev2-1${S}lev3-4${S}" '4'
    trie_insert t "lev1-1${S}lev2-1${S}lev3-5${S}" '5'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x1${S}" '6'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x2${S}" '7'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x3${S}" '8'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x4${S}" '9'
    trie_insert t "lev1-2${S}lev2-1${S}lev3-5${S}" '5'
    trie_insert t "lev1-2${S}lev2-2${S}lev3-x1${S}" '6'
    trie_insert t "lev1-2${S}lev2-2${S}lev3-x2${S}" '7'
    trie_insert t "lev1-2${S}lev2-2${S}lev3-x3${S}" '8'
    trie_insert t "lev1-2${S}lev2-2${S}lev3-x4${S}" '9'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x5${S}0${S}" '9'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x5${S}1${S}" '9'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x5${S}2${S}" '9'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x5${S}3${S}" '9'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x5${S}4${S}" '9'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x5${S}5${S}" '9'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x5${S}11${S}" '9'
    trie_insert t "lev1-1${S}lev2-2${S}lev3-x5${S}a${S}" '9'

    trie_dump t
    local get_str1=${ trie_dump_flat t;}

    # 1. 整颗树
    eval -- local -A sub_t=(${|trie_get_subtree t;})
    trie_dump sub_t

    # 2. 键不存在
    local sub_t_str ; sub_t_str=${|trie_get_subtree t "lev1-1${S}LEv2${S}";}
    if [[ "$?" == "$TR_RET_ENUM_KEY_IS_NOTFOUND" ]] ; then
        echo "${FUNCNAME[0]} 1 test pass."
    else
        echo "${FUNCNAME[0]} 1 test fail."
        return 1
    fi

    # 3. 键非法
    local sub_t_str ; sub_t_str=${|trie_get_subtree t "lev1-1${S}Lev2-1";}
    if [[ "$?" == "$TR_RET_ENUM_KEY_IS_NULL" ]] ; then
        echo "${FUNCNAME[0]} 2 test pass."
    else
        echo "${FUNCNAME[0]} 2 test fail."
        return 1
    fi

    # 4. 叶子键
    local sub_t_str ; sub_t_str=${|trie_get_subtree t "lev1-1${S}lev2-1${S}lev3-1${S}";}
    if [[ "$?" == "$TR_RET_ENUM_KEY_IS_LEAF" ]] ; then
        echo "${FUNCNAME[0]} 3 test pass."
    else
        echo "${FUNCNAME[0]} 3 test fail."
        return 1
    fi

    # 5.获取一级子健
    eval -- local -A sub_t=(${|trie_get_subtree t "lev1-1${S}lev2-2${S}";})
    trie_dump sub_t
    # trie_dump_flat sub_t

    # 6.获取二级子健
    eval -- local -A sub_t=(${|trie_get_subtree t "lev1-1${S}lev2-2${S}";})
    trie_dump sub_t
    # trie_dump_flat sub_t
    # diff_two_str_side_by_side "$get_str1" "$get_str2" "trie_test_test_case1.txt"
    return 0
}

test_case1

