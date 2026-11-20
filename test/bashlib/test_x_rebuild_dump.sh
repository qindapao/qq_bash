#!/usr/bin/env bash
# x_rebuild_from_dump 的独立回归用例。
#
# 覆盖两类输入：
#   1. 简单键值（无转义）：字典叶子、字典树、数组叶子、空字典/空数组叶子、
#      max_index 行剔除；
#   2. 一颗真实 dump 出来的复杂树：多行 key（值从下一行开始）、多行值、
#      转义 \}、控制字符/中文、嵌套数组、注释与空行。
#
# 只依赖 x.sh（x 树库），不需要 xo_init。
. ../../src/bashlib/x.sh
. ../libs/test_utils.sh

CHECKS=0 FAILS=0
check ()
{
    CHECKS=$((CHECKS+1))
    if [[ "$2" == "$3" ]] ; then
        log_test 1 1
        printf '  [ok]   %-46s %s\033[0m\n' "$1" "$3"
    else
        FAILS=$((FAILS+1))
        log_test 0 1
        printf '  [FAIL] %-46s 期望=[%s] 实际=[%s]\033[0m\n' "$1" "$2" "$3"
    fi
}

# ---------------------------------------------------------------------------
# 1. 简单键值（无转义）
# ---------------------------------------------------------------------------
simple_dump='
t1(1) ->
    {a} => 1
    {b} => 2
    {n}
        0(2) = x
        1(3) = y
    {ed} => {}\u001c
    {ea} => []\u001c
    max_index => 6
'
x_rebuild_from_dump "$simple_dump" >/dev/null 2>&1
check '简单树：重建返回 0' '0' "$?"
eval "declare -A t_simple=($REPLY)"

x_get_leaf t_simple "{a}$X" ; check '简单树：字典叶子 {a}' '1' "$REPLY"
x_get_leaf t_simple "{b}$X" ; check '简单树：字典叶子 {b}' '2' "$REPLY"
x_get_leaf t_simple "{n}$X[0]$X" ; check '简单树：数组叶子 {n}[0]' 'x' "$REPLY"
x_get_leaf t_simple "{n}$X[1]$X" ; check '简单树：数组叶子 {n}[1]' 'y' "$REPLY"
simple_out=$(x_dump t_simple '' 4 2)
check '简单树：空字典叶子' '1' "$(grep -c '{ed} => {}\\u001c' <<<"$simple_out")"
check '简单树：空数组叶子' '1' "$(grep -c '{ea} => \[\]\\u001c' <<<"$simple_out")"

x_get_leaf t_simple "max_index$X" >/dev/null 2>&1
check '简单树：max_index 已剔除' '1' "$(( $? != 0 ))"

# ---------------------------------------------------------------------------
# 2. 复杂树（真实 dump）：注意 "=> " 行尾必须有一个空格
# ---------------------------------------------------------------------------
complex_dump='
t1(1) ->
    o
        {aa ge} => value2
        {b} => value1
    o
        {c2} => []\u001c
        {c8} => strwxx
        {c7} => false\u001c
        { gge
        | gege g
        # 注释行会被跳过
        |ggegg geg\t\t\u0002\u0003\u0004ge我是中文} => 
                                                      | 响铃 geg
                                                      | gg  ee\u0001\u0002\u0003\u0004\u0005\u0006\u0007\b\t
                                                      |\u000b\f\r\u000e\u000f\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001a\u001b\u001c\u001d\u001e\u001f ;over
        {
        |key
        |} => value_line1
             |value_line2
        {c6} => true\u001c
        {c5*[]@!{\}} => 190.23*[]@!{}
        {c3} => null\u001c
        {c4} => 190.22\u001c
        {c1} => {}\u001c
        {
        | ge中各
        | ge\\g
        |}
            o = null
            o =
               |gege
               |gege
               |
            o = true\u001c
            o = 1010\u001c
            o = 1010.22
            o = gegege
    o
        {x} => value3
    o
        {y} => value4
    o
        {z} => value5
    o
        o = null\u001c
        o = null\u001c
        o = null\u001c
        o = value5
    o
        {key1ggggggggg}
            {keeeeeeeey2} => valueX
    max_index => 37
'
x_rebuild_from_dump "$complex_dump" >/dev/null 2>/tmp/test_x_rebuild.err
check '复杂树：重建返回 0' '0' "$?"
check '复杂树：无 stderr 报错' '' "$(cat /tmp/test_x_rebuild.err)"
eval "declare -A t_complex=($REPLY)"

complex_dump_out=$(x_dump t_complex '' 4 2)
check '复杂树：含 value2'  '1' "$(grep -c '{aa ge} => value2' <<<"$complex_dump_out")"
check '复杂树：含 valueX'  '1' "$(grep -c 'valueX' <<<"$complex_dump_out")"
check '复杂树：含 190.23'  '1' "$(grep -c '190.23' <<<"$complex_dump_out")"
check '复杂树：含 1010.22' '1' "$(grep -c '1010.22' <<<"$complex_dump_out")"
check '复杂树：含 gegege' '1' "$(grep -c 'gegege' <<<"$complex_dump_out")"
check '复杂树：多行 key 行1' '1' "$(grep -c '{ gge' <<<"$complex_dump_out")"
check '复杂树：多行 key 行2' '1' "$(grep -c '| gege g' <<<"$complex_dump_out")"
check '复杂树：多行 key 中文' '1' "$(grep -c 'ge我是中文' <<<"$complex_dump_out")"
check '复杂树：多行值 响铃' '1' "$(grep -c '响铃 geg' <<<"$complex_dump_out")"
check '复杂树：多行值 ;over' '1' "$(grep -c ';over' <<<"$complex_dump_out")"
check '复杂树：转义键 \}' '1' "$(grep -c 'c5\*\[\]@!{\\}' <<<"$complex_dump_out")"

# 二次重建：dump 出来的文本再喂回去，仍应成功且保留关键内容。
# 不比较整段 dump 文本：x_dump 对"首行为空的多行值"的排版本身不是稳定格式。
x_rebuild_from_dump "$complex_dump_out" >/dev/null 2>/tmp/test_x_rebuild2.err
check '复杂树：二次重建返回 0' '0' "$?"
check '复杂树：二次重建无报错' '' "$(cat /tmp/test_x_rebuild2.err)"
eval "declare -A t_complex2=($REPLY)"
complex_dump_out2=$(x_dump t_complex2 '' 4 2)
check '复杂树：二次 dump 含 响铃' '1' "$(grep -c '响铃 geg' <<<"$complex_dump_out2")"
check '复杂树：二次 dump 含 valueX' '1' "$(grep -c 'valueX' <<<"$complex_dump_out2")"
check '复杂树：二次 dump 含 190.23' '1' "$(grep -c '190.23' <<<"$complex_dump_out2")"
check '复杂树：二次 dump 含 ge我是中文' '1' "$(grep -c 'ge我是中文' <<<"$complex_dump_out2")"

# ---------------------------------------------------------------------------
# 3. 格式错误：必须整体失败，不能静默重建出一棵缺枝的树
# ---------------------------------------------------------------------------
bad_dump='
t1 ->
    {a} =>bad
'
x_rebuild_from_dump "$bad_dump" >/dev/null 2>/tmp/test_x_rebuild_bad.err
check '格式错误：重建返回非 0' '1' "$(( $? != 0 ))"
check '格式错误：有明确报错' '1' "$(grep -c 'without trailing space' /tmp/test_x_rebuild_bad.err)"

printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
(( FAILS == 0 )) && exit 0 || exit 1
