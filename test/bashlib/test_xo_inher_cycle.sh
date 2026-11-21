#!/usr/bin/env bash
#
# 继承树正/反用例：
#   正向：多子类、多级继承都能插入并实例化
#   反向：纯环、自环、悬空 SUPER 都必须拒绝

. ../../src/bashlib/xo.sh

FAILS=0

pass () { printf 'PASS: %s\n' "$1" ; }
fail () { printf 'FAIL: %s\n' "$1" ; FAILS=$((FAILS + 1)) ; }

make_class () {
    local cls=$1 sup=$2
    eval "declare -gA ${cls}Obj=(
        [{CLS}\$X]='$cls'
        [{SUP}\$X]='$sup'
        [{MIX}\$X]=''
    )"
    XO_CLASS_FLAT_OBJ_VARS["${cls}Obj"]=1
    XO_CLASS_METHODS[$cls]=''
}

case_positive () (
    make_class LeafA Mid
    make_class LeafB Mid
    make_class Mid Root
    make_class Root Base

    xo_init 1 >/dev/null 2>&1 || { fail 'positive: xo_init failed' ; exit 1 ; }

    xo_obj_born LeafA >/dev/null 2>&1 || { fail 'positive: LeafA born' ; exit 1 ; }
    xo_obj_born LeafB >/dev/null 2>&1 || { fail 'positive: LeafB born' ; exit 1 ; }
    xo_obj_born Mid   >/dev/null 2>&1 || { fail 'positive: Mid born' ; exit 1 ; }
    xo_obj_born Root  >/dev/null 2>&1 || { fail 'positive: Root born' ; exit 1 ; }

    pass 'positive: multi-child inheritance initializes and instantiates'
)

case_cycle () (
    make_class A B
    make_class B A
    out=$(xo_init 1 2>&1)
    rc=$?
    if (( rc == 0 )) ; then
        fail 'negative: pure cycle was accepted'
        exit 1
    fi
    pass 'negative: pure cycle rejected'
    printf '%s\n' "$out" | grep -q 'circular' || fail 'negative: cycle error message'
)

case_self_cycle () (
    make_class Self Self
    out=$(xo_init 1 2>&1)
    rc=$?
    if (( rc == 0 )) ; then
        fail 'negative: self cycle was accepted'
        exit 1
    fi
    pass 'negative: self cycle rejected'
    printf '%s\n' "$out" | grep -q 'circular' || fail 'negative: self cycle error message'
)

case_dangling () (
    make_class A Missing
    out=$(xo_init 1 2>&1)
    rc=$?
    if (( rc == 0 )) ; then
        fail 'negative: dangling SUPER was accepted'
        exit 1
    fi
    pass 'negative: dangling SUPER rejected'
    printf '%s\n' "$out" | grep -q 'undefined' || fail 'negative: dangling error message'
)

case_positive
case_cycle
case_self_cycle
case_dangling

if (( FAILS )) ; then
    printf '%d assertion(s) failed\n' "$FAILS"
    exit 1
fi
exit 0
