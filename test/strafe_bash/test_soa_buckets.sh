#!/usr/bin/env bash
# 敌弹相位分桶的回归测试。
# 背景：直下敌弹（type 0）原来每 tick 都要全表扫 110 个槽位，其实 3/4 这一 tick
# 不动。改成按出生相位（G_RUN_TICKS & 3）分 4 桶，每 tick 只处理该动的一桶。
# 这个用例盯死三件事：节奏仍然是每 4 tick 一格、不同相位的弹互不干扰、
# 桶不会随刷弹/死亡无限增长（死槽要压掉）。
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

fresh_game ()
{
    local e
    for e in "${ENEMIES[@]}" ; do [[ -n "${XO_OBJ_POOL[$e]+_}" ]] && xo_obj_bury "$e" ; done
    ENEMIES=() BULLETS=() DROPS=() WORDS=() MISSILES=() HIT_FX=()
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && xo_obj_bury OBJ_player
    xo_obj_born_named OBJ_player PlaneBee >/dev/null 2>&1
    init_game >/dev/null 2>&1
    G_INV=99999999
}

# ---- 1. 节奏：出生后第 4 tick 移动一格，再 4 tick 再一格 ----
fresh_game
enemy_bullet_spawn EnemyBullet 30 10 x 1 >/dev/null 2>&1
for _i in 1 2 3 ; do _play_game_tick >/dev/null 2>&1 ; done
check '第 3 tick 还没动' 10 "${EB_Y[0]}"
_play_game_tick >/dev/null 2>&1
check '第 4 tick 动一格' 11 "${EB_Y[0]}"
for _i in 1 2 3 ; do _play_game_tick >/dev/null 2>&1 ; done
check '第 7 tick 仍停在 11' 11 "${EB_Y[0]}"
_play_game_tick >/dev/null 2>&1
check '第 8 tick 再动一格' 12 "${EB_Y[0]}"

# ---- 2. 不同相位互不干扰：t=0 与 t=1 出生的两发各走各的 ----
fresh_game
enemy_bullet_spawn EnemyBullet 20 10 x 1 >/dev/null 2>&1   # a，相位 0
_play_game_tick >/dev/null 2>&1
enemy_bullet_spawn EnemyBullet 40 10 x 1 >/dev/null 2>&1   # b，相位 1
for _i in 1 2 3 ; do _play_game_tick >/dev/null 2>&1 ; done
# 此时 a 已动过一格（t=4），b 还没动（下一次 t=5）
check 'a 先动一格' 11 "${EB_Y[0]}"
check 'b 尚未动'   10 "${EB_Y[1]}"
_play_game_tick >/dev/null 2>&1
check 'b 随后也动一格' 11 "${EB_Y[1]}"

# ---- 3. 强制移动入口：下一个 tick 一定动 ----
fresh_game
enemy_bullet_spawn EnemyBullet 50 10 x 1 >/dev/null 2>&1
eb_force_move_now 0
check '强制入口返回成功' 0 "$?"
_play_game_tick >/dev/null 2>&1
check '强制后移动一格' 11 "${EB_Y[0]}"

# ---- 4. 出界回收：贴底弹两格内必死 ----
fresh_game
enemy_bullet_spawn EnemyBullet 30 $(( SCREEN_H - 2 )) x 1 >/dev/null 2>&1
eb_force_move_now 0
_play_game_tick >/dev/null 2>&1
check '出界即回收' 0 "${EB_ALIVE[0]}"
check 'EB_LIVE 归零' 0 "$EB_LIVE"

# ---- 5. 桶不泄漏：狂刷 2000 tick，桶总长 = 活着的 type-0 数 ----
fresh_game
for (( _t=0 ; _t<2000 ; _t++ )) ; do
    enemy_bullet_spawn EnemyBullet $(( 5 + RANDOM % 90 )) $(( 6 + RANDOM % 5 )) x 1 >/dev/null 2>&1
    _play_game_tick >/dev/null 2>&1
done
live0=0
for (( _i=0 ; _i<EB_N ; _i++ )) ; do
    [[ "${EB_ALIVE[$_i]}" == 1 && "${EB_TYPE[$_i]}" == 0 ]] && (( live0++ ))
done
bucket_len=$(( ${#EB_BK0[@]} + ${#EB_BK1[@]} + ${#EB_BK2[@]} + ${#EB_BK3[@]} ))
check '桶总长等于存活直下弹数' "$live0" "$bucket_len"
check '槽位没被撑爆（EB_N 有上限）' 1 "$(( EB_N <= ENEMY_BULLET_LIMIT ))"

echo
if (( FAILS )) ; then
    printf '%s\n' "---- ${FAILS} 项失败 / 共 ${CHECKS} 项 ----"
    exit 1
fi
printf '%s\n' "---- 共断言 ${CHECKS} 项，失败 0 项 ----"
