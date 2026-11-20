#!/usr/bin/env bash
# 帧缓冲"退役清格"回归测试。
#   - 我方子弹被 fire（电网扫掉 / 打中敌人）或 bury 时，必须清掉它占的格子；
#     否则 fb 里会留下"死子弹"的幽灵格，之后该格被标脏时会被重画出来。
#   - 掉落物被 bury（拾取 / 到底）时，必须清掉顶层格子，否则留下静止残影。
STRAFE_PROJ_DIR=$(cd ../../src/strafe_bash && pwd -P)
STRAFE_LIB_HOME=$(cd ../../src/bashlib && pwd -P)
export STRAFE_PROJ_DIR STRAFE_LIB_HOME
. ../libs/test_utils.sh
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/game/main.sh" >/dev/null 2>&1
xo_init >/dev/null 2>&1 || { echo 'xo_init failed' ; exit 1 ; }
fb_init

CHECKS=0
FAILS=0

check ()        # $1=标签 $2=期望 $3=实际
{
    local label=$1 want=$2 got=$3
    CHECKS=$((CHECKS+1))
    if [[ "$want" == "$got" ]] ; then
        log_test 1 1
        printf '  [ok]   %-46s %s\033[0m\n' "$label" "$got"
    else
        FAILS=$((FAILS+1))
        log_test 0 1
        printf '  [FAIL] %-46s 期望=[%s] 实际=[%s]\033[0m\n' "$label" "$want" "$got"
    fi
}

dirty_has ()    # $1=idx，其余=列表；返回 0 表示包含
{
    local want=$1 i
    shift
    for i in "$@" ; do [[ "$i" == "$want" ]] && return 0 ; done
    return 1
}

idx_of () { REPLY=$(( ($1 - 1) * FB_W + ($2 - 1) )) ; }

printf '\n== 子弹：fire / bury 必须清格 ==\n'

# 1) bury 路径
xo_obj_born Bullet 10 20 '|' 1 0 -1 >/dev/null 2>&1 || { check 'Bullet born' 1 0 ; exit 1 ; }
b=$REPLY
idx_of 20 10 ; fi=$REPLY
check '子弹出生：owner 是自己' "$b" "${FB_OWNER[$fi]}"
check '子弹出生：有字符' 1 "$([[ -n "${FB_CELL[$fi]}" ]] && echo 1 || echo 0)"
FB_DIRTY=()
xo_obj_bury "$b"
check 'bury 后：格清空' '' "${FB_CELL[$fi]}"
check 'bury 后：owner 清空' '' "${FB_OWNER[$fi]}"
check 'bury 后：格子标脏' 0 "$(dirty_has "$fi" "${FB_DIRTY[@]}" ; echo $?)"

# 2) fire 路径（电网扫掉 / 打中敌人都是 fire）
xo_obj_hire Bullet 12 21 '|' 1 0 -1 >/dev/null 2>&1 ; b=$REPLY
idx_of 21 12 ; fi=$REPLY
FB_DIRTY=()
xo_obj_fire "$b"
check 'fire 后：格清空' '' "${FB_CELL[$fi]}"
check 'fire 后：owner 清空' '' "${FB_OWNER[$fi]}"
check 'fire 后：格子标脏' 0 "$(dirty_has "$fi" "${FB_DIRTY[@]}" ; echo $?)"

printf '\n== 掉落物：拾取 / 到底 bury 必须清顶层格 ==\n'

xo_obj_born Drop 1 >/dev/null 2>&1 || { check 'Drop born' 1 0 ; exit 1 ; }
d=$REPLY
declare -n _d=$d
dx=${_d[x]} dy=${_d[y]}
unset -n _d
idx_of "$dy" "$dx" ; di=$REPLY
check '掉落物出生：顶层有字符' 1 "$([[ -n "${FB_DROP[$di]}" ]] && echo 1 || echo 0)"
check '掉落物出生：downer 是自己' "$d" "${FB_DOWNER[$di]}"
FB_TOP=()
xo_obj_bury "$d"
check 'bury 后：顶层清空' '' "${FB_DROP[$di]}"
check 'bury 后：downer 清空' '' "${FB_DOWNER[$di]}"
check 'bury 后：顶层标脏' 0 "$(dirty_has "$di" "${FB_TOP[@]}" ; echo $?)"

printf '\n== 掉落物盖在子弹上：吃掉掉落物不能动子弹格 ==\n'

xo_obj_hire Bullet 30 21 '|' 1 0 -1 >/dev/null 2>&1 ; b=$REPLY
idx_of 21 30 ; bi=$REPLY
xo_obj_born Drop 1 >/dev/null 2>&1 ; d=$REPLY
declare -n _d2=$d
_d2[x]=30 _d2[y]=21
FB_DROP[$bi]=${_d2[glyph]} FB_DOWNER[$bi]=$d
unset -n _d2
xo_obj_bury "$d"
check '掉落物清空后：子弹格仍在' "$b" "${FB_OWNER[$bi]}"
check '掉落物清空后：子弹字符仍在' 1 "$([[ -n "${FB_CELL[$bi]}" ]] && echo 1 || echo 0)"

printf '\n== 掉落物指定位置出生：不能留下出生格残影 ==\n'

# Boss 死亡掉落走 "born 时就指定坐标" 的路径；旧实现是先 born 再改 x/y，
# 出生格（HUD 下面那行）会留下一个永不消失的字符。
xo_obj_born Drop 1 30 10 >/dev/null 2>&1 ; d=$REPLY
idx_of 10 30 ; di=$REPLY
check '指定位置：该格有字符' 1 "$([[ -n "${FB_DROP[$di]}" ]] && echo 1 || echo 0)"
check '指定位置：downer 是自己' "$d" "${FB_DOWNER[$di]}"
n=0
for k in "${!FB_DROP[@]}" ; do
    [[ "${FB_DOWNER[k]:-}" == "$d" ]] && (( n++ ))
done
check '指定位置：整张掉落层只有一格属于它' 1 "$n"

printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
(( FAILS == 0 )) && exit 0 || exit 1
