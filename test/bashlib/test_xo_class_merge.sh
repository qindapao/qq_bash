#!/usr/bin/env bash
#
# 树类模板合并：正反向用例。
# 模板里的值必须写转义形式：\u001c 是 X 分隔符。
# 不要在模板里裸写控制字符。

. ../../src/bashlib/xo.sh
. ../../src/bashlib/xe.sh

readonly MPStaticTemplate='
    MPObj ->
        {CLS} => MP
        {SUP} => BaseX
        {MIX} => 
        {OBJMIX} => 
        {leaf} => 1
        {empty_obj} => {}\u001c
        {empty_arr} => []\u001c
        {grow_obj} => {}\u001c
        {grow_arr} => []\u001c
        {nested}
            {p} => p
'
XO_CLASS_TREE_TMPL_VARS[MPStaticTemplate]=1
XO_CLASS_METHODS[MP]=''

readonly MCStaticTemplate='
    MCObj ->
        {CLS} => MC
        {SUP} => MP
        {MIX} => 
        {OBJMIX} => 
        {leaf} => 2
        {empty_obj} => {}\u001c
        {empty_arr} => []\u001c
        {grow_obj}
            {g} => g
        {grow_arr}
            o = g
        {nested}
            {c} => c
        {new_obj} => {}\u001c
        {new_arr} => []\u001c
        {new_nested}
            {x} => x
        {new_items}
            o = one
'
XO_CLASS_TREE_TMPL_VARS[MCStaticTemplate]=1
XO_CLASS_METHODS[MC]=''

FAILS=0
check () {
    local label=$1 want=$2 got=$3
    if [[ "$want" == "$got" ]] ; then
        printf '  ok   %-42s %s\n' "$label" "$got"
    else
        printf '  FAIL %-42s want=%s got=%s\n' "$label" "$want" "$got"
        FAILS=$((FAILS + 1))
    fi
}

xo_init || { echo 'FAIL: positive xo_init' ; exit 1 ; }

check 'same empty object survives' "$X_NODE_KIND_OBJ_EMPTY" \
    "$(x_get_node_type MCObj "{empty_obj}$X" path ; echo $?)"
check 'same empty array survives' "$X_NODE_KIND_ARR_EMPTY" \
    "$(x_get_node_type MCObj "{empty_arr}$X" path ; echo $?)"
check 'parent missing empty object created' "$X_NODE_KIND_OBJ_EMPTY" \
    "$(x_get_node_type MCObj "{new_obj}$X" path ; echo $?)"
check 'parent missing empty array created' "$X_NODE_KIND_ARR_EMPTY" \
    "$(x_get_node_type MCObj "{new_arr}$X" path ; echo $?)"
check 'empty parent object accepts child' 'g' \
    "$(x_get_leaf MCObj "{grow_obj}$X{g}$X" ; echo $REPLY)"
check 'empty parent array accepts child' 'g' \
    "$(x_get_leaf MCObj "{grow_arr}$X[0]$X" ; echo $REPLY)"
check 'nonempty object parent field kept' 'p' \
    "$(x_get_leaf MCObj "{nested}$X{p}$X" ; echo $REPLY)"
check 'nonempty object child field merged' 'c' \
    "$(x_get_leaf MCObj "{nested}$X{c}$X" ; echo $REPLY)"
check 'parent missing object created' "$X_NODE_KIND_OBJ" \
    "$(x_get_node_type MCObj "{new_nested}$X" path ; echo $?)"
check 'parent missing array created' "$X_NODE_KIND_ARR" \
    "$(x_get_node_type MCObj "{new_items}$X" path ; echo $?)"
check 'scalar child overrides parent' '2' \
    "$(x_get_leaf MCObj "{leaf}$X" ; echo $REPLY)"

# 反向：每个 case 一个独立 bash，避免一个失败污染全局。
SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/bashlib" && pwd)/xo.sh
run_negative () {
    local name=$1 pfield=$2 cfield=$3 script rc
    script=$(mktemp)
    cat > "$script" <<EOF
#!/usr/bin/env bash
. "$SOURCE"
readonly PStaticTemplate='
    PObj ->
        {CLS} => P
        {SUP} => BaseX
        {MIX} => 
        {OBJMIX} => 
$pfield
'
readonly CStaticTemplate='
    CObj ->
        {CLS} => C
        {SUP} => P
        {MIX} => 
        {OBJMIX} => 
$cfield
'
XO_CLASS_TREE_TMPL_VARS[PStaticTemplate]=1
XO_CLASS_METHODS[P]=''
XO_CLASS_TREE_TMPL_VARS[CStaticTemplate]=1
XO_CLASS_METHODS[C]=''
xo_init >/dev/null 2>&1
exit \$?
EOF
    bash "$script" >/dev/null 2>&1
    rc=$?
    rm -f "$script"
    if (( rc != 0 )) ; then
        printf '  ok   %-42s rejected\n' "$name"
    else
        printf '  FAIL %-42s accepted\n' "$name"
        FAILS=$((FAILS + 1))
    fi
}

NEG_SCALAR='        {x} => 1'
NEG_OBJ='        {x}
            {p} => 1'
NEG_ARR='        {x}
            o = p'
NEG_EMPTY_OBJ='        {x} => {}\u001c'
NEG_EMPTY_ARR='        {x} => []\u001c'

run_negative 'scalar -> nonempty object rejected' "$NEG_SCALAR" '        {x}
            {c} => 1'
run_negative 'scalar -> nonempty array rejected' "$NEG_SCALAR" '        {x}
            o = 1'
run_negative 'scalar -> empty object rejected' "$NEG_SCALAR" "$NEG_EMPTY_OBJ"
run_negative 'scalar -> empty array rejected' "$NEG_SCALAR" "$NEG_EMPTY_ARR"
run_negative 'nonempty object -> scalar rejected' "$NEG_OBJ" '        {x} => 2'
run_negative 'nonempty array -> scalar rejected' "$NEG_ARR" '        {x} => 2'
run_negative 'nonempty object -> empty object rejected' "$NEG_OBJ" "$NEG_EMPTY_OBJ"
run_negative 'nonempty array -> empty array rejected' "$NEG_ARR" "$NEG_EMPTY_ARR"
run_negative 'empty object -> empty array rejected' "$NEG_EMPTY_OBJ" "$NEG_EMPTY_ARR"
run_negative 'empty array -> empty object rejected' "$NEG_EMPTY_ARR" "$NEG_EMPTY_OBJ"

if (( FAILS )) ; then
    printf '%d assertion(s) failed\n' "$FAILS"
    exit 1
fi
echo 'PASS: tree-class merge positive/negative'
