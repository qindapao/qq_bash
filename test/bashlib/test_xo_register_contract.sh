#!/usr/bin/env bash
#
# 手工注册表反例：子类只把父类方法写进自己的注册表，
# 却没有定义 Child_foo。`xo_init 1` 必须拒绝这种声明。

. ../../src/bashlib/xo.sh

declare -gA ParentObj=(
    [{CLS}$X]='Parent'
    [{SUP}$X]='Base'
    [{MIX}$X]=''
    [{OBJMIX}$X]=''
)
Parent_foo () { REPLY='parent' ; }

declare -gA ChildObj=(
    [{CLS}$X]='Child'
    [{SUP}$X]='Parent'
    [{MIX}$X]=''
    [{OBJMIX}$X]=''
)

XO_CLASS_FLAT_OBJ_VARS[ParentObj]=1
XO_CLASS_METHODS[Parent]='foo'
XO_CLASS_FLAT_OBJ_VARS[ChildObj]=1
# 错误：foo 属于 Parent，子类没有 Child_foo，不应登记。
XO_CLASS_METHODS[Child]='foo'

out=$( xo_init 1 2>&1 )
rc=$?

if (( rc == 0 )) ; then
    printf 'FAIL: xo_init 1 accepted a child registry that copies a parent method\n'
    printf 'output:\n%s\n' "$out"
    exit 1
fi

printf 'PASS: xo_init 1 rejected the copied parent method (rc=%d)\n' "$rc"
printf 'error: %s\n' "$out"
exit 0
