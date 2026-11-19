#!/usr/bin/env bash
# 扁平类不变量：
#   1) 扁平类对象（FLT=1）的键只能是：五个元键 + 小写/下划线开头的普通字段；
#   2) 不允许出现任何 {..}$X 形式的非元键（说明剥离漏了）；
#   3) 不允许出现 x 树内部节点（1.c.* / 1.k / 1.t / 1.s / max_index ...）。
# 这条用例是"扁平化"的守门员：以后有人往扁平类里塞树操作，这里直接红。
STRAFE_PROJ_DIR=$(cd ../../src/strafe_bash && pwd -P)
STRAFE_LIB_HOME=$(cd ../../src/bashlib && pwd -P)
export STRAFE_PROJ_DIR STRAFE_LIB_HOME
. ../libs/test_utils.sh
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/game/main.sh" >/dev/null 2>&1
xo_init >/dev/null 2>&1

CHECKS=0 FAILS=0
check ()        # $1=标签 $2=期望 $3=实际
{
    CHECKS=$((CHECKS+1))
    if [[ "$2" == "$3" ]] ; then
        log_test 1 1
        printf '  [ok]   %-52s %s\033[0m\n' "$1" "$3"
    else
        FAILS=$((FAILS+1))
        log_test 0 1
        printf '  [FAIL] %-52s 期望=[%s] 实际=[%s]\033[0m\n' "$1" "$2" "$3"
    fi
}

# 元键白名单（键名带 $X 后缀）
declare -A META_OK=( ["{CLS}$X"]=1 ["{SUP}$X"]=1 ["{MIX}$X"]=1 ["{OBJMIX}$X"]=1 ["{FLT}$X"]=1 )

# 检查一个扁平类对象
check_flat ()          # $1=对象变量名（类对象）
{
    local var=$1 bad_meta=0 bad_case=0 bad_tree=0 k
    local -n _o=$var
    for k in "${!_o[@]}" ; do
        [[ -n "${META_OK[$k]+_}" ]] && continue
        if [[ "$k" == '{'* || "$k" == *'$X' ]] ; then
            bad_meta=$((bad_meta+1))
        elif [[ "$k" =~ ^[a-z_][a-z0-9_]*$ ]] ; then
            :
        else
            bad_case=$((bad_case+1))     # 大写开头/带点/纯数字 -> 树节点或非法键
        fi
    done
    unset -n _o
    check "$var: 非元键的 {\$X} 键" 0 "$bad_meta"
    check "$var: 非法键名（树节点/大写）" 0 "$bad_case"
}

printf '\n== 扁平类不变量 ==\n'
n=0
for var in $(compgen -A variable | grep 'Obj$') ; do
    declare -n _c=$var
    flat=${_c[{FLT}$X]:-}
    unset -n _c
    [[ "$flat" == 1 ]] || continue
    check_flat "$var"
    n=$((n+1))
done
check '至少检查到一个扁平类对象' 1 "$(( n > 0 ? 1 : 0 ))"

printf '\n== Base 可实例化（语义闭环）==\n'
check 'BaseObjStr 非空' 1 "$( [[ -n "$BaseObjStr" ]] && echo 1 || echo 0 )"
xo_obj_born_named OBJ_base_inst Base >/dev/null 2>&1
check 'Base 能 born' 0 "$?"
check 'Base 实例只有元键' 4 "${#OBJ_base_inst[@]}"
nonmeta=0
for k in "${!OBJ_base_inst[@]}" ; do
    [[ -n "${META_OK[$k]+_}" ]] || nonmeta=$((nonmeta+1))
done
check 'Base 实例没有用户字段' 0 "$nonmeta"

printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
(( FAILS == 0 )) && exit 0 || exit 1
