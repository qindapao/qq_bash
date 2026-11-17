#!/usr/bin/env bash
#
# hire（返聘）/ fire（解聘）的测试。
#
# 语义：born/bury 是生命；hire/fire 只是存储复用。本文件验证：
#   - 空市场时 hire 与 born 完全等价；
#   - fire 会调 <cls>_retire、清 Mixin、重置易变字段、把对象放进市场；
#   - hire 拿回同一个句柄、重新进池、按 born 钩子恢复出生状态；
#   - 没声明 <cls>ResetFields 的类走"全字段重置"的安全路径；
#   - 市场容量上限、批量返聘、错误路径。

. ../../src/bashlib/xo.sh
. ../libs/test_utils.sh

# ---------------------------------------------------------------------------
# 测试类
# ---------------------------------------------------------------------------
HireObjStaticTemplate='
    HireObj ->
        {CLS} => HireObj
        {SUP} => Base
        {MIX} => 
        {OBJMIX} => 
        {a} => 0
        {b} => 0
        {hits} => 0
'
# 易变字段：只有 a / hits 需要在解聘时回默认；b 由 born 钩子每次重设
readonly HireObjResetFields='a hits'

RETIRE_LOG=()
HireObj_retire () { RETIRE_LOG+=("$1") ; }
HireObj_born () {
    local -n _s=$1
    _s["{a}$X"]=$2
    _s["{b}$X"]=${3:-7}
}

# 没声明 ResetFields 的类：走全字段重置的安全路径
PlainObjStaticTemplate='
    PlainObj ->
        {CLS} => PlainObj
        {SUP} => Base
        {MIX} => 
        {OBJMIX} => 
        {v} => 5
'
PlainObj_born () { local -n _s=$1 ; _s["{v}$X"]=${2:-5} ; }

# ResetFields 写了不存在的字段：预处理阶段必须报错
BadObjStaticTemplate='
    BadObj ->
        {CLS} => BadObj
        {SUP} => Base
        {MIX} => 
        {x} => 0
'
readonly BadObjResetFields='no_such_field'

# retire 失败的类：fire 必须中止
FailObjStaticTemplate='
    FailObj ->
        {CLS} => FailObj
        {SUP} => Base
        {MIX} => 
        {x} => 0
'
FailObj_retire () { return 1 ; }

M_TX_ping () { REPLY='TX' ; }

xo_init

reset_market ()
{
    RES_MARKET=() ; RES_COUNT=() ; RES_LIMIT=() ; RETIRE_LOG=()
}

# 1) 空市场时 hire 与 born 等价（字段集与值完全一致）
test_case1 ()
{
    reset_market
    xo_obj_hire HireObj 11 22 ; local h1=$REPLY
    xo_obj_born HireObj 11 22 ; local h2=$REPLY

    local -n a=$h1 b=$h2
    local -i ok=1
    local k
    (( ${#a[@]} == ${#b[@]} )) || ok=0
    for k in "${!a[@]}" ; do
        [[ "${a[$k]}" == "${b[$k]}" ]] || ok=0
    done
    unset -n a b

    [[ -n "${XO_OBJ_POOL[$h1]+_}" && -n "${XO_OBJ_POOL[$h2]+_}" ]] || ok=0
    [[ "$h1" != "$h2" ]] || ok=0
    (( ${#RETIRE_LOG[@]} == 0 )) || ok=0

    if (( ok )) ; then log_test 1 1 ; else log_test 0 1 ; fi
}

# 2) fire：调 retire、出池、进市场、易变字段回默认、变量仍在
test_case2 ()
{
    reset_market
    xo_obj_hire HireObj 1 ; local h=$REPLY
    local -n o=$h
    o["{hits}$X"]=9 ; o["{a}$X"]=42
    unset -n o

    xo_obj_fire "$h" || { log_test 0 2 ; return 1 ; }

    local -i ok=1
    (( ${#RETIRE_LOG[@]} == 1 )) && [[ "${RETIRE_LOG[0]}" == "$h" ]] || ok=0
    [[ -z "${XO_OBJ_POOL[$h]+_}" ]] || ok=0          # 出池
    (( ${RES_COUNT[HireObj]:-0} == 1 )) || ok=0      # 进市场
    declare -p "$h" >/dev/null 2>&1 || ok=0          # 变量还在（肉体保留）

    local -n o2=$h
    [[ "${o2["{hits}$X"]}" == 0 ]] || ok=0           # 易变字段回默认
    [[ "${o2["{a}$X"]}" == 0 ]] || ok=0
    [[ "${o2["{b}$X"]}" == 7 ]] || ok=0              # 非易变字段保持出生值
    unset -n o2

    if (( ok )) ; then log_test 1 2 ; else log_test 0 2 ; fi
}

# 3) hire 拿回同一个句柄，重新进池并跑 born 钩子
test_case3 ()
{
    local h=${RES_MARKET["HireObj|0"]}
    xo_obj_hire HireObj 5 6
    local -i ok=1
    [[ "$REPLY" == "$h" ]] || ok=0
    [[ -n "${XO_OBJ_POOL[$h]+_}" ]] || ok=0
    (( ${RES_COUNT[HireObj]:-0} == 0 )) || ok=0
    (( ${#RETIRE_LOG[@]} == 1 )) || ok=0             # hire 不调 retire

    local -n o=$h
    [[ "${o["{a}$X"]}" == 5 ]] || ok=0               # born 钩子按参数重设
    [[ "${o["{b}$X"]}" == 6 ]] || ok=0
    [[ "${o["{hits}$X"]}" == 0 ]] || ok=0
    unset -n o

    if (( ok )) ; then log_test 1 3 ; else log_test 0 3 ; fi
}

# 4) fire 会清掉对象级动态能力，返聘后不带前任技能
test_case4 ()
{
    reset_market
    xo_obj_hire HireObj 1 ; local h=$REPLY
    xo_obj_mixin_add "$h" M_TX || { log_test 0 4 ; return 1 ; }

    xo_obj_fire "$h" || { log_test 0 4 ; return 1 ; }

    local -i ok=1
    xo_obj_mixin_list "$h"
    [[ -z "$REPLY" ]] || ok=0

    xo_obj_hire HireObj 1
    [[ "$REPLY" == "$h" ]] || ok=0
    xo_obj_mixin_list "$h"
    [[ -z "$REPLY" ]] || ok=0

    if (( ok )) ; then log_test 1 4 ; else log_test 0 4 ; fi
}

# 5) 市场容量上限：超限的对象当场销毁，不囤货
test_case5 ()
{
    reset_market
    RES_LIMIT[HireObj]=1
    # 两个对象同时在飞，再依次解聘：第一个进市场，第二个超限被销毁
    xo_obj_hire HireObj 1 ; local h1=$REPLY
    xo_obj_hire HireObj 1 ; local h2=$REPLY
    xo_obj_fire "$h1"
    xo_obj_fire "$h2"

    local -i ok=1
    (( ${RES_COUNT[HireObj]:-0} == 1 )) || ok=0
    [[ -n "${RES_MARKET["HireObj|0"]}" ]] || ok=0
    [[ "${RES_MARKET["HireObj|0"]}" == "$h1" ]] || ok=0
    declare -p "$h2" >/dev/null 2>&1 && ok=0          # 超限 → 真销毁
    RES_LIMIT[HireObj]=512

    if (( ok )) ; then log_test 1 5 ; else log_test 0 5 ; fi
}

# 6) 批量返聘：一次拿 N 个，且优先复用市场里的（LIFO）
test_case6 ()
{
    reset_market
    xo_obj_hire_n 3 HireObj 2 3
    local -a hs=( $REPLY )
    local -i ok=1
    (( ${#hs[@]} == 3 )) || ok=0
    [[ "${hs[0]}" != "${hs[1]}" && "${hs[1]}" != "${hs[2]}" ]] || ok=0
    local h
    for h in "${hs[@]}" ; do
        [[ -n "${XO_OBJ_POOL[$h]+_}" ]] || ok=0
    done
    for h in "${hs[@]}" ; do xo_obj_fire "$h" ; done
    (( ${RES_COUNT[HireObj]:-0} == 3 )) || ok=0
    xo_obj_hire_n 3 HireObj 2 3
    local -a hs2=( $REPLY )
    (( ${#hs2[@]} == 3 )) || ok=0

    if (( ok )) ; then log_test 1 6 ; else log_test 0 6 ; fi
}

# 7) 没声明 ResetFields 的类：fire 走全字段重置（安全路径）
test_case7 ()
{
    reset_market
    xo_obj_hire PlainObj 9 ; local h=$REPLY
    xo_obj_fire "$h" || { log_test 0 7 ; return 1 ; }
    local -i ok=1
    local -n o=$h
    [[ "${o["{v}$X"]}" == 5 ]] || ok=0        # 回到模板默认值
    unset -n o
    if (( ok )) ; then log_test 1 7 ; else log_test 0 7 ; fi
}

# 8) ResetFields 写了不存在的字段：fire 必须失败（不静默写野字段）
test_case8 ()
{
    reset_market
    xo_obj_hire BadObj 1 ; local h=$REPLY
    if xo_obj_fire "$h" 2>/dev/null ; then
        log_test 0 8 ; return 1
    fi
    local -i ok=1
    (( ${RES_COUNT[BadObj]:-0} == 0 )) || ok=0
    [[ -n "${XO_OBJ_POOL[$h]+_}" ]] || ok=0    # 失败后对象仍在池里
    if (( ok )) ; then log_test 1 8 ; else log_test 0 8 ; fi
}

# 9) retire 失败时 fire 中止：不进市场、对象仍在池里
test_case9 ()
{
    reset_market
    xo_obj_hire FailObj 1 ; local h=$REPLY
    if xo_obj_fire "$h" 2>/dev/null ; then
        log_test 0 9 ; return 1
    fi
    local -i ok=1
    (( ${RES_COUNT[FailObj]:-0} == 0 )) || ok=0
    [[ -n "${XO_OBJ_POOL[$h]+_}" ]] || ok=0
    if (( ok )) ; then log_test 1 9 ; else log_test 0 9 ; fi
}

# 10) fire 之后过期句柄读到"默认值"而不是空（契约文档化）
test_case10 ()
{
    reset_market
    xo_obj_hire HireObj 3 ; local h=$REPLY
    local -n o=$h ; o["{a}$X"]=99 ; unset -n o
    xo_obj_fire "$h" || { log_test 0 10 ; return 1 ; }

    local -i ok=1
    declare -p "$h" >/dev/null 2>&1 || ok=0     # 变量仍在
    local -n o2=$h
    [[ "${o2["{a}$X"]}" == 0 ]] || ok=0         # 不是空，是模板默认值
    [[ -n "${o2["{a}$X"]}" ]] || ok=0
    unset -n o2
    if (( ok )) ; then log_test 1 10 ; else log_test 0 10 ; fi
}

# 11) 具名重名必须被拒绝：解聘后同名再 born 不能覆盖待业肉体（曾静默覆盖）
test_case11 ()
{
    reset_market
    xo_obj_born_named OBJ_h11 HireObj 5
    xo_obj_fire OBJ_h11
    local -i ok=1
    (( ${RES_COUNT[HireObj]:-0} == 1 )) || ok=0
    if xo_obj_born_named OBJ_h11 HireObj 9 2>/dev/null ; then ok=0 ; fi
    (( ${RES_COUNT[HireObj]:-0} == 1 )) || ok=0          # 市场没被破坏
    [[ "${RES_MARKET["HireObj|0"]}" == 'OBJ_h11' ]] || ok=0
    xo_obj_hire HireObj                                   # 还能正常返聘回来
    [[ "$REPLY" == 'OBJ_h11' ]] || ok=0
    xo_obj_bury OBJ_h11
    if (( ok )) ; then log_test 1 11 ; else log_test 0 11 ; fi
}

eval -- "$(AS_RUN_TEST_CASES)"
