#!/usr/bin/env bash
#
# 词库（config/words.sh）的约束测试。
#
# 为什么要测：
#   - 非 ASCII / 双宽字符会把飘字整行顶歪（宪法第 5 节）；
#   - 过长的词条会被刷字逻辑静默跳过，等于白掉一次刷新；
#   - 重复词条让"飘字"变得可预测，失去随机感；
#   - 空词条或带首尾空格的词条会让拾取包围盒算错。

STRAFE_PROJ_DIR=$(cd ../../src/strafe_bash && pwd -P)
STRAFE_LIB_HOME=$(cd ../../src/bashlib && pwd -P)
export STRAFE_PROJ_DIR STRAFE_LIB_HOME

. ../libs/test_utils.sh
. "$STRAFE_LIB_HOME/str.sh"
. "$STRAFE_PROJ_DIR/config/words.sh"

CHECKS=0
FAILS=0

check ()        # $1=标签 $2=期望 $3=实际
{
    CHECKS=$((CHECKS+1))
    if [[ "$2" == "$3" ]] ; then
        printf '  [ok]   %-40s %s\033[0m\n' "$1" "$3"
    else
        printf '  [FAIL] %-40s 期望=[%s] 实际=[%s]\033[0m\n' "$1" "$2" "$3"
        FAILS=$((FAILS+1))
    fi
}

test_case1 ()
{
    printf '\n== 词库约束 ==\n'

    local -i n=${#WORD_LIST[@]}
    check '词条数量足够多（>=30）' 1 "$(( n >= 30 ? 1 : 0 ))"

    local -i i nonascii=0 spacey=0 empty=0 dup=0 toolong=0
    local -A seen=()
    local t w maxw=$(( SCREEN_W - 4 ))

    for (( i=0 ; i<n ; i++ )) ; do
        t=${WORD_LIST[i]}

        [[ -z "$t" ]] && { empty=1 ; printf '  空词条 index %s\n' "$i" ; }
        [[ "$t" != "$(printf '%s' "$t" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" ]] && \
            { spacey=1 ; printf '  首尾空格 index %s: [%s]\n' "$i" "$t" ; }

        # 可打印 ASCII：只要出现 空格..~ 之外的字符（含中文、制表符）就算违规
        if printf '%s' "$t" | LC_ALL=C grep -q '[^ -~]' ; then
            nonascii=1
            printf '  非可打印 ASCII index %s: [%s]\n' "$i" "$t"
        fi

        str_display_width "$t" w
        (( w > maxw )) && { toolong=1 ; printf '  过长 index %s (%s > %s): [%s]\n' "$i" "$w" "$maxw" "$t" ; }

        [[ -n "${seen[$t]+_}" ]] && { dup=1 ; printf '  重复词条: [%s]\n' "$t" ; }
        seen[$t]=1
    done

    check '没有空词条' 0 "$empty"
    check '没有首尾空格' 0 "$spacey"
    check '全部是可打印 ASCII' 0 "$nonascii"
    check '全部不超过 SCREEN_W-4' 0 "$toolong"
    check '没有重复词条' 0 "$dup"

    printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
    if (( FAILS == 0 )) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
}

eval -- "$(AS_RUN_TEST_CASES)"
