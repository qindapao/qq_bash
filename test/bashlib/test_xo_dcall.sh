#!/usr/bin/env bash
#
# xo_dcall: 跳过当前类的透传函数，直接调用最终实现。
# 覆盖：own / inherited / class-level mixin / 参数透传。

. ../../src/bashlib/xo.sh

DBase_ping () { REPLY="base:$2" ; }
DBase_shared () { REPLY="shared:$2" ; }
DChild_own () { REPLY="own:$2" ; }
M_D_mix () { REPLY="mix:$2" ; }

readonly M_DStaticTemplate='
    M_DObj ->
        {CLS} => M_D
        {SUP} => Base
        {MIX} => 
        {FLT} => 1
'
XO_MIXIN_METHODS[M_D]='mix'

declare -gA DBaseObj=(
    [{CLS}$X]='DBase'
    [{SUP}$X]='Base'
    [{MIX}$X]=''
    [{OBJMIX}$X]=''
)
XO_CLASS_FLAT_OBJ_VARS[DBaseObj]=1
XO_CLASS_METHODS[DBase]='ping shared'

declare -gA DChildObj=(
    [{CLS}$X]='DChild'
    [{SUP}$X]='DBase'
    [{MIX}$X]='M_D'
    [{OBJMIX}$X]=''
)
XO_CLASS_FLAT_OBJ_VARS[DChildObj]=1
XO_CLASS_METHODS[DChild]='own'

xo_init || { echo 'FAIL: xo_init' ; exit 1 ; }
xo_obj_born_named OBJ_dc DChild || { echo 'FAIL: born' ; exit 1 ; }

FAILS=0
check_call () {
    local mode=$1 want=$2 method=$3 arg=$4
    REPLY=''
    "$mode" OBJ_dc "$method" "$arg" || { echo "FAIL: $mode $method status" ; FAILS=$((FAILS+1)) ; return ; }
    if [[ "$REPLY" != "$want" ]] ; then
        printf 'FAIL: %s %s want=%s got=%s\n' "$mode" "$method" "$want" "$REPLY"
        FAILS=$((FAILS+1))
    fi
}

check_call xo_call  'own:hi'    own    hi
check_call xo_dcall 'own:hi'    own    hi
check_call xo_call  'base:hi'   ping   hi
check_call xo_dcall 'base:hi'   ping   hi
check_call xo_call  'shared:hi' shared hi
check_call xo_dcall 'shared:hi' shared hi
check_call xo_call  'mix:hi'    mix    hi
check_call xo_dcall 'mix:hi'    mix    hi

if (( FAILS )) ; then
    printf '%d assertion(s) failed\n' "$FAILS"
    exit 1
fi
echo 'PASS: xo_dcall own/inherited/mixin'
