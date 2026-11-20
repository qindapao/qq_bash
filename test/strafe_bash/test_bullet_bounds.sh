#!/usr/bin/env bash
# 敌弹出生坐标越界的回归测试。
# 背景：Boss 的巨型弹幕 pattern 按 cx±11 / cy±6 生成坐标；Boss 停在顶部时
# cy=7，偏移 -6 会算到第 1 行。eb_add 原来不校验坐标，于是：
#   - 子弹被写进第 1 行（边框）的帧缓冲格 —— 看起来"子弹卡在边栏"；
#   - 它死亡/移动时清格又把边框擦出缺口。
# 现在 eb_add 把出生坐标夹到可玩区，这个用例盯死"帧缓冲里没有任何区外格"。
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
        printf '  [ok]   %-46s %s\033[0m\n' "$1" "$3"
    else
        FAILS=$((FAILS+1))
        log_test 0 1
        printf '  [FAIL] %-46s 期望=[%s] 实际=[%s]\033[0m\n' "$1" "$2" "$3"
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

# 帧缓冲里是否有"可玩区之外"的格
count_outside ()
{
    local idx row col n=0
    for idx in "${!FB_CELL[@]}" ; do
        [[ -n "${FB_CELL[idx]}" ]] || continue
        row=$(( idx / FB_W + 1 )) ; col=$(( idx % FB_W + 1 ))
        if (( row < GAME_TOP || row > SCREEN_H - 2 || col < 2 || col > SCREEN_W - 2 )) ; then
            ((n++))
        fi
    done
    REPLY=$n
}

fresh_game
printf '\n== 出生坐标夹取 ==\n'

# 左上角外：x=1, y=0
enemy_bullet_spawn BossBullet 1 0 0 1 x 1 2 >/dev/null 2>&1
check '越界出生 x 夹到 2'           2 "${EB_X[0]}"
check '越界出生 y 夹到 GAME_TOP'   "$GAME_TOP" "${EB_Y[0]}"
count_outside ; check '帧缓冲无区外格（左上越界）' 0 "$REPLY"

# 右下角外
fresh_game
enemy_bullet_spawn BossBullet $(( SCREEN_W + 10 )) $(( SCREEN_H + 10 )) 0 1 x 1 2 >/dev/null 2>&1
check '越界出生 x 夹到右边界'     "$(( SCREEN_W - 2 ))" "${EB_X[0]}"
check '越界出生 y 夹到下边界'     "$(( SCREEN_H - 2 ))" "${EB_Y[0]}"
count_outside ; check '帧缓冲无区外格（右下越界）' 0 "$REPLY"

# Boss 弹幕 pattern 的真实坐标：模拟 cy=7 的 ±6 偏移
fresh_game
enemy_bullet_spawn BossBullet 40 1 0 1 x 1 2 >/dev/null 2>&1
check 'pattern 顶部弹 y 夹到 GAME_TOP' "$GAME_TOP" "${EB_Y[0]}"
count_outside ; check '帧缓冲无区外格（pattern 顶部）' 0 "$REPLY"

printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
(( FAILS == 0 )) && exit 0 || exit 1
