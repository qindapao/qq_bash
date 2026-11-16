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

# 注意：下面「{OBJMIX} => 」这一行行尾有一个空格，这是本仓库模板空值的写法。
# 对象级 Mixin 要求类模板声明该字段，运行时直接赋值才与对象树保持一致。
TestObjStaticTemplate='
    TestObj ->
        {CLS} => TestObj
        {SUP} => Base
        {OBJMIX} => 
'

# 故意不声明 {OBJMIX}：验证 add 的契约守卫会拒绝，而不是写一个野字段
TestNoFieldStaticTemplate='
    TestNoField ->
        {CLS} => TestNoField
        {SUP} => Base
'

TestObj_hello () { REPLY='hello' ; }

xo_init

# 每次用例开头都从干净对象开始，避免用例间互相污染
reset_obj ()
{
    local obj=$1
    if [[ -n "${XO_OBJ_POOL[$obj]+_}" ]] ; then
        xo_obj_kill "$obj" >/dev/null 2>&1
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

# 6) 具名句柄重用：kill 后重新 born（表项残留），再注入别的 Mixin 时不得串味
test_case6 ()
{
    reset_obj OBJ_m6
    xo_obj_mixin_add OBJ_m6 M_T1 || { log_test 0 6 ; return 1 ; }
    xo_obj_kill OBJ_m6 >/dev/null 2>&1 || { log_test 0 6 ; return 1 ; }

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
        xo_obj_kill OBJ_nf >/dev/null 2>&1
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

eval -- "$(AS_RUN_TEST_CASES)"
