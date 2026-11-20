#!/usr/bin/env bash
#
# 对象级 Mixin（xo_obj_mixin_add/delete + xo_obj_call）的测试。
# 只测对象侧；类级 {MIX} 的注入逻辑不在本文件范围内。

. ../../src/bashlib/xo.sh
. ../libs/test_utils.sh

# ---------------------------------------------------------------------------
# 测试用 Mixin：ping 故意在两个 Mixin 里重名，用来验证「先加先赢」和「删除后回退」。
# M_T1_solo / M_T2_extra 各自独有，用来验证卸载只影响属于自己的方法。
# ---------------------------------------------------------------------------
M_T1_ping () { REPLY='T1' ; }
M_T1_solo () { REPLY='T1solo' ; }
M_T2_ping () { REPLY='T2' ; }
M_T2_extra () { REPLY='T2extra' ; }
M_T3_ping () { REPLY='T3' ; }

# 生命周期钩子测试用：_init 在注入后调用、_cleanup 在卸载前调用（bury 不调，见 case12 f）。
# 钩子方法名必须以下划线开头（完整函数名是 M_Xxx__init 这种双下划线），否则会被当成
# 公共方法注入路由（两个能力都实现 init 时会被"先加先赢"吞掉第二个）。
HOOK_LOG=()
M_H1_ping () { REPLY='H1' ; }
M_H1__init () { HOOK_LOG+=("init:${1}:H1") ; }
M_H1__cleanup () { HOOK_LOG+=("clean:${1}:H1") ; }
M_H2_ping () { REPLY='H2' ; }
M_H2__init () { HOOK_LOG+=("init:${1}:H2") ; }
M_H2__cleanup () { HOOK_LOG+=("clean:${1}:H2") ; }
# 纯钩子型能力：没有公共方法，只有状态钩子（应当允许注入）
M_H3__init () { HOOK_LOG+=("init:${1}:H3") ; }
M_H3__cleanup () { HOOK_LOG+=("clean:${1}:H3") ; }
# 一次性能力：_init 里放完就自卸（验证"同一次 add 内不复活、不重复触发"）
M_H4__init () { HOOK_LOG+=("init:${1}:H4") ; xo_obj_mixin_delete "${1}" M_H4 ; }

# 注意：下面「{OBJMIX} => 」这一行行尾有一个空格，这是本仓库模板空值的写法。
# 对象级 Mixin 要求类模板声明该字段，运行时直接赋值才与对象树保持一致。
declare -gA TestObjObj=(
    [{CLS}$X]='TestObj'
    [{SUP}$X]='Base'
    [{OBJMIX}$X]=''
)

# 故意不声明 {OBJMIX}：验证 add 的契约守卫会拒绝，而不是写一个野字段
declare -gA TestNoFieldObj=(
    [{CLS}$X]='TestNoField'
    [{SUP}$X]='Base'
)

TestObj_hello () { REPLY='hello' ; }

xo_init

# 每次用例开头都从干净对象开始，避免用例间互相污染
reset_obj ()
{
    local obj=$1
    if [[ -n "${XO_OBJ_POOL[$obj]+_}" ]] ; then
        xo_obj_bury "$obj" >/dev/null 2>&1
    fi
    xo_obj_born_named "$obj" TestObj >/dev/null 2>&1
}

# 1) 注入后：能力可调用，{OBJMIX} 记录正确，类方法仍可回落调用
test_case1 ()
{
    reset_obj OBJ_m1
    xo_obj_mixin_add OBJ_m1 M_T1 || { log_test 0 1 ; return 1 ; }
    xo_call OBJ_m1 hello
    local cls_r=$REPLY
    xo_obj_call OBJ_m1 hello
    local obj_r=$REPLY

    xo_obj_call OBJ_m1 ping ; local p=$REPLY
    xo_obj_call OBJ_m1 solo ; local s=$REPLY
    xo_obj_mixin_list OBJ_m1 ; local list=$REPLY

    if [[ "$p" == 'T1' && "$s" == 'T1solo' && "$list" == 'M_T1' &&
          "$cls_r" == 'hello' && "$obj_r" == 'hello' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
}

# 2) 卸载后：能力消失（调用失败），表项不残留
test_case2 ()
{
    reset_obj OBJ_m2
    xo_obj_mixin_add OBJ_m2 M_T1 || { log_test 0 2 ; return 1 ; }
    xo_obj_mixin_delete OBJ_m2 M_T1 || { log_test 0 2 ; return 1 ; }

    xo_obj_mixin_list OBJ_m2 ; local list=$REPLY

    if xo_obj_call OBJ_m2 ping 2>/dev/null ; then
        log_test 0 2 ; return 1
    fi
    if [[ -z "$list" && -z "${XO_OBJ_METHOD[OBJ_m2|ping]+_}" &&
          -z "${XO_OBJ_METHOD[OBJ_m2|solo]+_}" ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi
}

# 3) 同名方法：先加先赢；删掉先加的之后，后面的 Mixin 自动接管（回退）
test_case3 ()
{
    reset_obj OBJ_m3
    xo_obj_mixin_add OBJ_m3 M_T1 || { log_test 0 3 ; return 1 ; }
    xo_obj_mixin_add OBJ_m3 M_T2 || { log_test 0 3 ; return 1 ; }

    xo_obj_call OBJ_m3 ping  ; local first=$REPLY
    xo_obj_call OBJ_m3 extra ; local e1=$REPLY

    xo_obj_mixin_delete OBJ_m3 M_T1 || { log_test 0 3 ; return 1 ; }

    xo_obj_call OBJ_m3 ping  ; local second=$REPLY
    xo_obj_mixin_list OBJ_m3  ; local list=$REPLY
    local solo_gone=0
    xo_obj_call OBJ_m3 solo 2>/dev/null || solo_gone=1

    if [[ "$first" == 'T1' && "$e1" == 'T2extra' &&
          "$second" == 'T2' && "$list" == 'M_T2' && "$solo_gone" == 1 ]] ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi
}

# 4) 幂等：重复注入同一个 Mixin，列表只留一份
test_case4 ()
{
    reset_obj OBJ_m4
    xo_obj_mixin_add OBJ_m4 M_T1 || { log_test 0 4 ; return 1 ; }
    xo_obj_mixin_add OBJ_m4 M_T1 || { log_test 0 4 ; return 1 ; }
    xo_obj_mixin_list OBJ_m4 ; local list=$REPLY

    if [[ "$list" == 'M_T1' ]] ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi
}

# 5) 注入一个没有任何方法的 Mixin：报错返回非 0，且列表不变
test_case5 ()
{
    reset_obj OBJ_m5
    if xo_obj_mixin_add OBJ_m5 M_NoSuchMixin 2>/dev/null ; then
        log_test 0 5 ; return 1
    fi
    xo_obj_mixin_list OBJ_m5 ; local list=$REPLY

    if [[ -z "$list" ]] ; then
        log_test 1 5
    else
        log_test 0 5 ; return 1
    fi
}

# 6) 具名句柄重用：bury 后重新 born（表项残留），再注入别的 Mixin 时不得串味
test_case6 ()
{
    reset_obj OBJ_m6
    xo_obj_mixin_add OBJ_m6 M_T1 || { log_test 0 6 ; return 1 ; }
    xo_obj_bury OBJ_m6 >/dev/null 2>&1 || { log_test 0 6 ; return 1 ; }

    xo_obj_born_named OBJ_m6 TestObj >/dev/null 2>&1 || { log_test 0 6 ; return 1 ; }
    xo_obj_mixin_add OBJ_m6 M_T2 || { log_test 0 6 ; return 1 ; }

    xo_obj_call OBJ_m6 ping ; local p=$REPLY
    xo_obj_mixin_list OBJ_m6 ; local list=$REPLY

    # 残留的 M_T1 必须被清掉：ping 应该是 T2，而不是 T1
    if [[ "$p" == 'T2' && "$list" == 'M_T2' ]] ; then
        log_test 1 6
    else
        log_test 0 6 ; return 1
    fi
}

# 7) 契约：类模板没有声明 {OBJMIX} 时，add 必须拒绝（否则会写出树里看不见的野字段）
test_case7 ()
{
    if [[ -n "${XO_OBJ_POOL[OBJ_nf]+_}" ]] ; then
        xo_obj_bury OBJ_nf >/dev/null 2>&1
    fi
    xo_obj_born_named OBJ_nf TestNoField >/dev/null 2>&1 || { log_test 0 7 ; return 1 ; }

    if xo_obj_mixin_add OBJ_nf M_T1 2>/dev/null ; then
        log_test 0 7 ; return 1
    fi

    if [[ -z "${XO_OBJ_METHOD[OBJ_nf|ping]+_}" ]] ; then
        log_test 1 7
    else
        log_test 0 7 ; return 1
    fi
}

# 8) 不带参数卸载全部：只清该对象，别的对象的动态能力不受影响
test_case8 ()
{
    reset_obj OBJ_m8a
    reset_obj OBJ_m8b
    xo_obj_mixin_add OBJ_m8a M_T1 || { log_test 0 8 ; return 1 ; }
    xo_obj_mixin_add OBJ_m8b M_T2 || { log_test 0 8 ; return 1 ; }

    xo_obj_mixin_delete OBJ_m8a || { log_test 0 8 ; return 1 ; }

    xo_obj_mixin_list OBJ_m8a ; local la=$REPLY
    xo_obj_mixin_list OBJ_m8b ; local lb=$REPLY
    xo_obj_call OBJ_m8b ping ; local pb=$REPLY

    if [[ -z "$la" && "$lb" == 'M_T2' && "$pb" == 'T2' &&
          -z "${XO_OBJ_METHOD[OBJ_m8a|ping]+_}" ]] ; then
        log_test 1 8
    else
        log_test 0 8 ; return 1
    fi
}

# 9) 删一个从未加入过的 Mixin：等于没删，能力指向不变
test_case9 ()
{
    reset_obj OBJ_m9
    xo_obj_mixin_add OBJ_m9 M_T1 || { log_test 0 9 ; return 1 ; }

    xo_obj_mixin_delete OBJ_m9 M_T2 || { log_test 0 9 ; return 1 ; }

    xo_obj_mixin_list OBJ_m9 ; local list=$REPLY
    xo_obj_call OBJ_m9 ping ; local p=$REPLY

    if [[ "$list" == 'M_T1' && "$p" == 'T1' ]] ; then
        log_test 1 9
    else
        log_test 0 9 ; return 1
    fi
}

# 10) 一次删两个（同名方法都来自它们）：全部路由清空，能力彻底消失
test_case10 ()
{
    reset_obj OBJ_m10
    xo_obj_mixin_add OBJ_m10 M_T1 || { log_test 0 10 ; return 1 ; }
    xo_obj_mixin_add OBJ_m10 M_T2 || { log_test 0 10 ; return 1 ; }

    xo_obj_mixin_delete OBJ_m10 M_T1 M_T2 || { log_test 0 10 ; return 1 ; }

    xo_obj_mixin_list OBJ_m10 ; local list=$REPLY

    local gone_ping=0 gone_extra=0
    xo_obj_call OBJ_m10 ping  2>/dev/null || gone_ping=1
    xo_obj_call OBJ_m10 extra 2>/dev/null || gone_extra=1

    if [[ -z "$list" && "$gone_ping" == 1 && "$gone_extra" == 1 &&
          -z "${XO_OBJ_METHOD[OBJ_m10|ping]+_}" ]] ; then
        log_test 1 10
    else
        log_test 0 10 ; return 1
    fi
}

# 11) 接任者再被删：路由沿名单一路往后走，直到没人接任才消失
test_case11 ()
{
    reset_obj OBJ_m11
    xo_obj_mixin_add OBJ_m11 M_T1 || { log_test 0 11 ; return 1 ; }
    xo_obj_mixin_add OBJ_m11 M_T2 || { log_test 0 11 ; return 1 ; }
    xo_obj_mixin_add OBJ_m11 M_T3 || { log_test 0 11 ; return 1 ; }

    xo_obj_call OBJ_m11 ping ; local r1=$REPLY     # M_T1 在名单最前
    xo_obj_mixin_delete OBJ_m11 M_T1
    xo_obj_call OBJ_m11 ping ; local r2=$REPLY     # 删 T1 后 → T2 接任
    xo_obj_mixin_delete OBJ_m11 M_T2
    xo_obj_call OBJ_m11 ping ; local r3=$REPLY     # 再接任者 T2 被删 → T3 接任
    xo_obj_mixin_delete OBJ_m11 M_T3
    local gone=0
    xo_obj_call OBJ_m11 ping 2>/dev/null || gone=1 # 没人接任 → 路由消失

    if [[ "$r1" == 'T1' && "$r2" == 'T2' && "$r3" == 'T3' && "$gone" == 1 ]] ; then
        log_test 1 11
    else
        log_test 0 11 ; return 1
    fi
}

# 12) 生命周期钩子：_init 注入后自动跑、_cleanup 卸载前跑、bury 不跑；
#     幂等 add 不重复 init；列表形式一次加多个；纯钩子型能力可注入
test_case12 ()
{
    local -i bad=0
    local joined

    # a) 注入后立刻 init
    reset_obj OBJ_h1
    HOOK_LOG=()
    xo_obj_mixin_add OBJ_h1 M_H1 || bad=1
    joined="${HOOK_LOG[*]}"
    [[ "$joined" == 'init:OBJ_h1:H1' ]] || bad=1

    # b) 幂等：已持有不重复 init（否则会把正在倒计时的状态重置）
    HOOK_LOG=()
    xo_obj_mixin_add OBJ_h1 M_H1 || bad=1
    (( ${#HOOK_LOG[@]} == 0 )) || bad=1

    # c) 列表形式：已持有的跳过、新的 init；顺序与参数一致；先加先赢不变
    HOOK_LOG=()
    xo_obj_mixin_add OBJ_h1 M_H1 M_H2 || bad=1
    joined="${HOOK_LOG[*]}"
    [[ "$joined" == 'init:OBJ_h1:H2' ]] || bad=1
    xo_obj_mixin_list OBJ_h1
    [[ "$REPLY" == 'M_H1 M_H2' ]] || bad=1
    xo_obj_call OBJ_h1 ping
    [[ "$REPLY" == 'H1' ]] || bad=1

    # d) 卸载前 cleanup，且只对"确实持有"的能力调用
    HOOK_LOG=()
    xo_obj_mixin_delete OBJ_h1 M_H1 || bad=1
    joined="${HOOK_LOG[*]}"
    [[ "$joined" == 'clean:OBJ_h1:H1' ]] || bad=1

    HOOK_LOG=()
    xo_obj_mixin_delete OBJ_h1 M_H1 || bad=1          # 已经不持有
    (( ${#HOOK_LOG[@]} == 0 )) || bad=1

    # e) 不给参数 = 全部卸载，每个仍持有的能力各 cleanup 一次
    HOOK_LOG=()
    xo_obj_mixin_delete OBJ_h1 || bad=1
    joined="${HOOK_LOG[*]}"
    [[ "$joined" == 'clean:OBJ_h1:H2' ]] || bad=1

    # f) bury 不调 cleanup：整个对象变量被销毁，状态随对象消失，无需清理
    reset_obj OBJ_h2
    xo_obj_mixin_add OBJ_h2 M_H1 || bad=1
    HOOK_LOG=()
    xo_obj_bury OBJ_h2 >/dev/null 2>&1 || bad=1
    (( ${#HOOK_LOG[@]} == 0 )) || bad=1

    # g) 纯钩子型能力（无公共方法）允许注入，且 init/cleanup 都跑
    reset_obj OBJ_h3
    HOOK_LOG=()
    xo_obj_mixin_add OBJ_h3 M_H3 || bad=1
    xo_obj_mixin_delete OBJ_h3 || bad=1
    joined="${HOOK_LOG[*]}"
    [[ "$joined" == 'init:OBJ_h3:H3 clean:OBJ_h3:H3' ]] || bad=1

    # h) 同一次调用里重复列同一个一次性能力：只触发一次（去重），且不会复活
    reset_obj OBJ_h4
    HOOK_LOG=()
    xo_obj_mixin_add OBJ_h4 M_H4 M_H4 || bad=1
    joined="${HOOK_LOG[*]}"
    [[ "$joined" == 'init:OBJ_h4:H4' ]] || bad=1
    xo_obj_mixin_list OBJ_h4
    [[ -z "$REPLY" ]] || bad=1

    # i) 自卸能力 + 普通能力同批：普通能力留在名单里，自卸的不会复活
    HOOK_LOG=()
    xo_obj_mixin_add OBJ_h4 M_H4 M_H1 || bad=1
    joined="${HOOK_LOG[*]}"
    [[ "$joined" == 'init:OBJ_h4:H4 init:OBJ_h4:H1' ]] || bad=1
    xo_obj_mixin_list OBJ_h4
    [[ "$REPLY" == 'M_H1' ]] || bad=1

    # j) 另一次调用可以再次拿到一次性能力（它已不在名单里）
    HOOK_LOG=()
    xo_obj_mixin_add OBJ_h4 M_H4 || bad=1
    joined="${HOOK_LOG[*]}"
    [[ "$joined" == 'init:OBJ_h4:H4' ]] || bad=1

    if (( bad )) ; then log_test 0 12 ; return 1 ; fi
    log_test 1 12
}

eval -- "$(AS_RUN_TEST_CASES)"
