#!/usr/bin/env bash
# 掉落物 / 增益计时器的回归测试。
# 背景：扁平化迁移漏了 3 处"动态拼出来的树键"（"{t$_tier}$X" 等），
# 表现为：吃了武器掉落，下一 tick 就退回默认子弹；所有增益计时器不递减。
# 这个用例专门盯死这类"键名是拼出来的"场景。
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
        printf '  [ok]   %-44s %s\033[0m\n' "$1" "$3"
    else
        FAILS=$((FAILS+1))
        log_test 0 1
        printf '  [FAIL] %-44s 期望=[%s] 实际=[%s]\033[0m\n' "$1" "$2" "$3"
    fi
}

# 每个 case 都从干净的一局开始
fresh_game ()
{
    local e
    for e in "${ENEMIES[@]}" ; do [[ -n "${XO_OBJ_POOL[$e]+_}" ]] && xo_obj_bury "$e" ; done
    ENEMIES=() BULLETS=() DROPS=() WORDS=() MISSILES=() HIT_FX=()
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && xo_obj_bury OBJ_player
    xo_obj_born_named OBJ_player PlaneBee >/dev/null 2>&1
    init_game >/dev/null 2>&1
}

# 在玩家身上放一个掉落，跑一个 tick 让它被拾取
pickup_drop ()         # $1 = dtype
{
    xo_obj_born Drop "$1" >/dev/null 2>&1
    local d=$REPLY
    declare -n _dp=$d
    _dp[x]=${OBJ_player[x]}
    _dp[y]=${OBJ_player[y]}
    unset -n _dp
    DROPS+=("$d")
    G_INV=999999
    _play_game_tick >/dev/null 2>&1
}

tick_n ()              # $1 = 次数
{
    local i
    for (( i=0 ; i<$1 ; i++ )) ; do
        G_INV=999999
        _play_game_tick >/dev/null 2>&1
    done
}

printf '\n== 武器掉落：吃到后要保持，不能下一 tick 就掉回去 ==\n'
fresh_game
pickup_drop 3
check '吃完武器 3 档' "${OBJ_player[w3]}" "${OBJ_player[bullet]}"
check 't3 计时器已挂上' 1500 "${OBJ_player[t3]:-0}"
tick_n 1
check '下一 tick 武器仍是 3 档' "${OBJ_player[w3]}" "${OBJ_player[bullet]}"
check 't3 开始递减' 1499 "${OBJ_player[t3]:-0}"
tick_n 10
check '再跑 10 tick 武器仍是 3 档' "${OBJ_player[w3]}" "${OBJ_player[bullet]}"

printf '\n== 武器到期：t3 归零后回默认 ==\n'
OBJ_player[t3]=1
tick_n 2
check 't3 到期回默认武器 w1' "${OBJ_player[w1]}" "${OBJ_player[bullet]}"

printf '\n== 其它增益计时器也要递减 ==\n'
fresh_game
pickup_drop m
check 'm 挂上导弹计时' 1 "$( (( ${OBJ_player[mt]:-0} > 0 )) && echo 1 || echo 0 )"
_mt0=${OBJ_player[mt]}
tick_n 3
check 'mt 递减了' "$(( _mt0 - 3 ))" "${OBJ_player[mt]:-0}"
pickup_drop L
check 'L 挂上弹道计时' 1 "$( (( ${OBJ_player[lt]:-0} > 0 )) && echo 1 || echo 0 )"
_lt0=${OBJ_player[lt]}
tick_n 2
check 'lt 递减了' "$(( _lt0 - 2 ))" "${OBJ_player[lt]:-0}"

printf '\n== H / b 掉落仍然有效 ==\n'
fresh_game
OBJ_player[hp]=5
pickup_drop H
check 'H 回血 +3' 8 "${OBJ_player[hp]}"
fresh_game
OBJ_player[bombs]=0
pickup_drop b
check 'b 加一颗炸弹' 1 "${OBJ_player[bombs]}"

printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
(( FAILS == 0 )) && exit 0 || exit 1
