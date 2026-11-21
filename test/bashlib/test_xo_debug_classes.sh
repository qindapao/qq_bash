#!/usr/bin/env bash
#
# xo_debug_classes：flat/tree/Mixin 合并调试树。
# 只验证结构，不依赖游戏类。

. ../../src/bashlib/xo.sh

readonly TDNodeStaticTemplate='
    TDNodeObj ->
        {CLS} => TDNode
        {SUP} => BaseX
        {MIX} => 
        {OBJMIX} => 
        {FLT} => 0
        {name} => unnamed
        {v} => 0
        {nested}
            {child} => deep
            {grand}
                {leaf} => grand
        {arr}
            o = zero
            o = one
            o
                {name} => third
                {items}
                    o = nested
'
TDNode_born () { REPLY='ok' ; }
XO_CLASS_TREE_TMPL_VARS[TDNodeStaticTemplate]=1
XO_CLASS_METHODS[TDNode]='born'

readonly TDebugChildStaticTemplate='
    TDebugChildObj ->
        {CLS} => TDebugChild
        {SUP} => TDNode
        {MIX} => 
        {OBJMIX} => 
        {FLT} => 0
        {child_only} => child
        {child_nested}
            {child_leaf} => child
'
XO_CLASS_TREE_TMPL_VARS[TDebugChildStaticTemplate]=1
XO_CLASS_METHODS[TDebugChild]=''

readonly M_DebugStaticTemplate='
    M_DebugObj ->
        {CLS} => M_Debug
        {SUP} => Base
        {MIX} => 
        {FLT} => 1
'
M_Debug_burn () { REPLY='burn' ; }
XO_MIXIN_METHODS[M_Debug]='burn'

declare -gA FlatDebugObj=(
    [{CLS}$X]='FlatDebug'
    [{SUP}$X]='Base'
    [{MIX}$X]='M_Debug'
    [{OBJMIX}$X]=''
    [hp]=10
    [tag]='flat'
)
FlatDebug_hello () { REPLY='hello' ; }
XO_CLASS_FLAT_OBJ_VARS[FlatDebugObj]=1
XO_CLASS_METHODS[FlatDebug]='hello'

xo_init 1 || { echo 'FAIL: xo_init' ; exit 1 ; }

before=$(x_dump XO_CLASS_INHER_TREE '' 4 2) || { echo 'FAIL: dump before' ; exit 1 ; }
xo_debug_classes 5 > /tmp/qq_debug_classes_test.txt || { echo 'FAIL: xo_debug_classes' ; exit 1 ; }
after=$(x_dump XO_CLASS_INHER_TREE '' 4 2) || { echo 'FAIL: dump after' ; exit 1 ; }

[[ "$before" == "$after" ]] || { echo 'FAIL: canonical inheritance tree was modified' ; exit 1 ; }

grep -Fq '{FlatDebug}' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing FlatDebug' ; exit 1 ; }
grep -Fq '{hp} => 10' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing flat attribute hp' ; exit 1 ; }
grep -Fq '{tag} => flat' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing flat attribute tag' ; exit 1 ; }
grep -Fq '{hello} => own' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing flat method hello' ; exit 1 ; }
grep -Fq '{burn} => M_Debug' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing mixin method burn source' ; exit 1 ; }
grep -Fq '{retire} => Base' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing inherited method retire source' ; exit 1 ; }
grep -Fq '{M_Debug} => 1' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing class mixin M_Debug' ; exit 1 ; }

grep -Fq '{TDNode}' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing TDNode' ; exit 1 ; }
grep -Fq '{CLS} => TDNode' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing meta CLS' ; exit 1 ; }
grep -Fq '{FLT} => 0' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing meta FLT' ; exit 1 ; }
grep -Fq '{SUP} => BaseX' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing meta SUP' ; exit 1 ; }
if grep -Fq '{kind} =>' /tmp/qq_debug_classes_test.txt ; then echo 'FAIL: old kind meta remains' ; exit 1 ; fi
grep -Fq '{name} => unnamed' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing tree attribute name' ; exit 1 ; }
grep -Fq '{v} => 0' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing tree attribute v' ; exit 1 ; }
grep -Fq '{child} => deep' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing nested object child' ; exit 1 ; }
grep -Fq 'o = zero' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing nested array element 0' ; exit 1 ; }
grep -Fq 'o = one' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing nested array element 1' ; exit 1 ; }
grep -Fq '{born} => own' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing tree method born' ; exit 1 ; }
grep -Fq '{print} => BaseX' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing tree inherited method source' ; exit 1 ; }

grep -Fq '{TDebugChild}' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing TDebugChild' ; exit 1 ; }
grep -Fq '{child_only} => child' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing child-only field' ; exit 1 ; }
grep -Fq '{child_leaf} => child' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing child nested field' ; exit 1 ; }
if (( $(grep -Fc '{child} => deep' /tmp/qq_debug_classes_test.txt) < 2 )) ; then
    echo 'FAIL: nested parent field not inherited by child'
    exit 1
fi

grep -Fq '{__MIXINS}' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing root mixins' ; exit 1 ; }
grep -Fq '{burn} => own' /tmp/qq_debug_classes_test.txt || { echo 'FAIL: missing mixin method burn' ; exit 1 ; }

echo 'PASS: xo_debug_classes flat/tree/mixin structure'
