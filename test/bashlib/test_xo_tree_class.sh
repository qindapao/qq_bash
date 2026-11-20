#!/usr/bin/env bash
# 树类（BaseX 血统）的回归测试。
#
# 扁平化改造后，树类这条路径必须完全不受影响：
#   - 键保持 {字段}$X 形式，x 树内部节点照旧；
#   - 继承（树父类 -> 树子类）字段正常合并；
#   - born / hire / fire 的 ResetFields 用树键读写；
#   - x_insert 等树操作在对象上仍然可用；
#   - Mixin 的 FLT 声明与树类匹配（FLT=0 允许，FLT=1 拒绝）；
#   - "扁平父类含用户字段 -> 树子类" 必须被拒绝（禁止扁平升变为树）。
. ../../src/bashlib/xo.sh
. ../libs/test_utils.sh

CHECKS=0 FAILS=0
check ()        # $1=标签 $2=期望 $3=实际
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

# ---- 树类：TNode(BaseX) -> TChild(TNode) ----
readonly TNodeStaticTemplate='
    TNodeObj ->
        {CLS} => TNode
        {SUP} => BaseX
        {MIX} => 
        {OBJMIX} => 
        {name} => unnamed
        {v} => 0
    '
TNode_born () { local -n _s=$1 ; _s["{name}$X"]=${2:-unnamed} ; }
readonly TNodeResetFields='v'

readonly TChildStaticTemplate='
    TChildObj ->
        {CLS} => TChild
        {SUP} => TNode
        {MIX} => 
        {OBJMIX} => 
        {extra} => 0
    '

# ---- 扁平类，用来和树类做对照 ----
declare -gA FlatRefObj=(
    [{CLS}$X]='FlatRef'
    [{SUP}$X]='Base'
    [{MIX}$X]=''
    [{OBJMIX}$X]=''
    [hp]='10'
)

# ---- tree-only mixin，用来验证 FLT 校验 ----
readonly M_TreeOnlyStaticTemplate='
    M_TreeOnly ->
        {CLS} => M_TreeOnly
        {REQUIRES} => FLT=0
    '
M_TreeOnly_ping () { REPLY=pong ; }

xo_init

printf '\n== 树类：类对象形态 ==\n'
check 'BaseXObj 有树节点 max_index' 1 "$( [[ -n "${BaseXObj[max_index]+_}" ]] && echo 1 || echo 0 )"
check 'BaseXObj 保留 1.c.{CLS} 节点' 1 "$( [[ -n "${BaseXObj[1.c.{CLS}]+_}" ]] && echo 1 || echo 0 )"
check 'BaseXObj 的 {FLT}$X=0' '0' "${BaseXObj["{FLT}$X"]:-}"
check 'BaseXObj 没有扁平键 cls' 0 "$( [[ -n "${BaseXObj[cls]+_}" ]] && echo 1 || echo 0 )"

# 这条分支（树类 + 扁平父类）当前只有 Base -> BaseX；BaseX 本身必须能实例化
xo_obj_born_named OBJ_bx BaseX >/dev/null 2>&1
check 'BaseX 能 born' 0 "$?"
check 'BaseX 实例是树键（有 max_index）' 1 "$( [[ -n "${OBJ_bx[max_index]+_}" ]] && echo 1 || echo 0 )"
check 'BaseX 实例 {CLS}$X=BaseX' 'BaseX' "${OBJ_bx["{CLS}$X"]:-}"
check 'BaseX 实例 {FLT}$X=0' '0' "${OBJ_bx["{FLT}$X"]:-}"
check 'BaseX 实例没有扁平键 cls' 0 "$( [[ -n "${OBJ_bx[cls]+_}" ]] && echo 1 || echo 0 )"

check 'TNodeObj 保留 {name}$X 树键' 'unnamed' "${TNodeObj["{name}$X"]:-}"
check 'TNodeObj 保留树节点 1.c.*' 1 "$( [[ -n "${TNodeObj[1.c.{name}]+_}" ]] && echo 1 || echo 0 )"
check 'TNodeObj 没有扁平键 name' 0 "$( [[ -n "${TNodeObj[name]+_}" ]] && echo 1 || echo 0 )"
check 'TChildObj 继承 {name}$X' 'unnamed' "${TChildObj["{name}$X"]:-}"
check 'TChildObj 继承 {v}$X' '0' "${TChildObj["{v}$X"]:-}"
check 'TChildObj 自有 {extra}$X' '0' "${TChildObj["{extra}$X"]:-}"

printf '\n== 树类：实例与树操作 ==\n'
xo_obj_born_named OBJ_tn TChild alice >/dev/null 2>&1
check 'born 实例 {name}$X' 'alice' "${OBJ_tn["{name}$X"]:-}"
check 'born 实例没有扁平键 name' 0 "$( [[ -n "${OBJ_tn[name]+_}" ]] && echo 1 || echo 0 )"
x_insert OBJ_tn "{nested}$X" 5
check 'x_insert 在树实例上可用' '5' "${OBJ_tn["{nested}$X"]:-}"

printf '\n== 树类：hire/fire 的 ResetFields 走树键 ==\n'
OBJ_tn["{v}$X"]=9
xo_obj_fire OBJ_tn >/dev/null 2>&1
check 'fire 返回 0' 0 "$?"
xo_obj_hire TChild alice >/dev/null 2>&1
check 'hire 返回 0' 0 "$?"
check 'hire 后 v 回到模板默认值' '0' "${OBJ_tn["{v}$X"]:-}"
check 'hire 后 name 由 born 钩子重设' 'alice' "${OBJ_tn["{name}$X"]:-}"

printf '\n== Mixin 的 FLT 校验（树类）==\n'
xo_obj_mixin_add OBJ_tn M_TreeOnly >/dev/null 2>&1
check '树类 + FLT=0 mixin 接受' 0 "$?"
xo_obj_mixin_add OBJ_tn M_Blink >/dev/null 2>&1
check '树类 + FLT=1 mixin 拒绝' 1 "$?"

printf '\n== 扁平类仍然扁平（同一次 init）==\n'
xo_obj_born_named OBJ_fr FlatRef >/dev/null 2>&1
check '扁实例没有 {hp}$X 树键' 0 "$( [[ -n "${OBJ_fr[{hp}$X]+_}" ]] && echo 1 || echo 0 )"
check '扁实例有扁平键 hp' '10' "${OBJ_fr[hp]:-}"

printf '\n== 禁止扁平升变为树 ==\n'
guard_script=$(mktemp)
cat > "$guard_script" <<'EOS'
. "$1" >/dev/null 2>&1
declare -gA FlatDadObj=(
    [{CLS}$X]='FlatDad'
    [{SUP}$X]='Base'
    [{MIX}$X]=''
    [hp]='5'
)
readonly BadTreeStaticTemplate='
    BadTreeObj ->
        {CLS} => BadTree
        {SUP} => FlatDad
        {MIX} => 
        {FLT} => 0
    '
xo_init >/dev/null 2>&1
echo "rc=$?"
xo_init 2>&1 | head -2
EOS
guard_out=$(bash "$guard_script" "$PWD/../../src/bashlib/xo.sh" 2>&1)
rm -f "$guard_script"
check '守卫拒绝扁平升变为树' 1 "$(printf '%s' "$guard_out" | grep -c '禁止扁平升变为树')"
check '守卫返回非零' 1 "$(printf '%s' "$guard_out" | grep -c 'rc=1')"

printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
(( FAILS == 0 )) && exit 0 || exit 1
