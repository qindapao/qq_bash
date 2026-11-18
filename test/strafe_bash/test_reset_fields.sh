#!/usr/bin/env bash
# ResetFields 完整性测试：hire/fire 的唯一系统性风险是"某类漏登记易变字段"，
# 漏了会让返聘出来的对象带着上一任的残留值。对每个登记了 <Cls>ResetFields 的类：
#   1. born 一个对象 -> 记下所有字段（基准）
#   2. 把所有字段改成哨兵值
#   3. fire（解聘，按 ResetFields 恢复）-> hire（返聘）
#   4. 逐字段比对：必须和基准完全一致
# 漏登记一个字段，这条测试直接红。
STRAFE_PROJ_DIR=$(cd ../../src/strafe_bash && pwd -P)
STRAFE_LIB_HOME=$(cd ../../src/bashlib && pwd -P)
export STRAFE_PROJ_DIR STRAFE_LIB_HOME
. ../libs/test_utils.sh
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/game/main.sh" >/dev/null 2>&1
xo_init >/dev/null 2>&1 || { echo 'xo_init failed' ; exit 1 ; }

CHECKS=0
FAILS=0

check ()        # $1=标签 $2=期望 $3=实际
{
    local label=$1 want=$2 got=$3
    CHECKS=$((CHECKS+1))
    if [[ "$want" == "$got" ]] ; then
        log_test 1 1
        printf '  [ok]   %-46s %s\n' "$label" "$got"
    else
        FAILS=$((FAILS+1))
        log_test 0 1
        printf '  [FAIL] %-46s 期望=[%s] 实际=[%s]\n' "$label" "$want" "$got"
    fi
}

# 只关心用户字段（{...}），跳过 x-tree 的内部节点（1.c.{x} / 7.k / max_index 等）；
# CLS/SUP/MIX 是类元数据，也不参与。
is_user_field ()
{
    [[ "$1" =~ ^\{[^{}]*\}$ ]] || return 1
    case "$1" in '{CLS}'|'{SUP}'|'{MIX}') return 1 ;; esac
    return 0
}

# snapshot <obj> <out_array_name>
snapshot ()
{
    local obj=$1 out_name=$2
    local -n _o=$obj
    local -n _out=$out_name
    _out=()
    local k
    for k in "${!_o[@]}" ; do
        is_user_field "$k" || continue
        _out["$k"]=${_o["$k"]}
    done
}

# test_class <cls> <born args...>
test_class ()
{
    local cls=$1
    shift
    local -A base=() after=()
    xo_obj_born "$cls" "$@" >/dev/null 2>&1 || { check "$cls 能 born" 1 0 ; return ; }
    local h=$REPLY
    snapshot "$h" base
    local -n _m=$h
    local k
    for k in "${!_m[@]}" ; do
        is_user_field "$k" || continue
        _m["$k"]='__SENTINEL__'
    done
    unset -n _m
    xo_obj_fire "$h" >/dev/null 2>&1 || { check "$cls 能 fire" 1 0 ; return ; }
    xo_obj_hire "$cls" "$@" >/dev/null 2>&1 || { check "$cls 能 hire" 1 0 ; return ; }
    snapshot "$REPLY" after
    local -i diff=0
    for k in "${!base[@]}" ; do
        if [[ "${after[$k]-}" != "${base[$k]}" ]] ; then
            diff=$((diff+1))
            printf '  字段不一致: [%s] 期望=[%s] 实际=[%s]\n' "$k" "${base[$k]}" "${after[$k]-}"
        fi
    done
    check "$cls: 返聘后全部字段回到 born 默认值" 0 "$diff"
    xo_obj_bury "$REPLY" >/dev/null 2>&1
}

printf '\n== ResetFields 完整性 ==\n'
test_class Bullet 10 10 '.' 1 0 -1
test_class Missile 10 10 2

printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
(( FAILS == 0 )) && exit 0 || exit 1
