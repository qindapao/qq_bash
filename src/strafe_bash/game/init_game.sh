# game/init_game.sh — 每局初始化（重置玩家状态、清理所有对象）
[[ -n "${_STRAFE_INIT_GAME_SH:-}" ]] && return 0
_STRAFE_INIT_GAME_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../config/const.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../config/art.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../config/globals.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../classes/base_types.sh"

init_game () {
    local -n p=$PLAYER
    p["{x}$X"]=$(( SCREEN_W / 2 ))
    p["{y}$X"]=$(( SCREEN_H - 2 ))
    p["{hp}$X"]=20
    p["{score}$X"]=0
    p["{bombs}$X"]=0
    p["{t2}$X"]=0
    p["{t3}$X"]=0
    p["{t4}$X"]=0
    p["{t5}$X"]=0
    p["{mt}$X"]=0
    p["{lanes}$X"]=0
    p["{lanes_side}$X"]=0
    p["{lt}$X"]=0
    p["{shield}$X"]=0
    p["{st}$X"]=0
    p["{art}$X"]="$PLANE_ART_BASE"
    p["{al}$X"]=1

    local old_bt=${p["{bullet}$X"]}
    [[ -n "$old_bt" && -n "${XO_OBJ_POOL[$old_bt]+_}" ]] && xo_obj_kill "$old_bt"
    xo_obj_born BulletType '.' 1
    p["{bullet}$X"]=$REPLY
    unset -n p

    local b e d eb m w
    for b in "${BULLETS[@]}" ; do [[ -n "${XO_OBJ_POOL[$b]+_}" ]] && xo_obj_kill "$b" ; done
    for e in "${ENEMIES[@]}" ; do [[ -n "${XO_OBJ_POOL[$e]+_}" ]] && xo_obj_kill "$e" ; done
    for d in "${DROPS[@]}" ; do [[ -n "${XO_OBJ_POOL[$d]+_}" ]] && xo_obj_kill "$d" ; done
    for eb in "${ENEMY_BULLETS[@]}" ; do [[ -n "${XO_OBJ_POOL[$eb]+_}" ]] && xo_obj_kill "$eb" ; done
    for m in "${MISSILES[@]}" ; do [[ -n "${XO_OBJ_POOL[$m]+_}" ]] && xo_obj_kill "$m" ; done
    for w in "${WORDS[@]}" ; do [[ -n "${XO_OBJ_POOL[$w]+_}" ]] && xo_obj_kill "$w" ; done
    BULLETS=() ; ENEMIES=() ; DROPS=() ; ENEMY_BULLETS=() ; MISSILES=() ; BOMB_FX_POS=() ; BOSS_DEATH_POS=() ; CLEAR_BATCH=() ; WORDS=()
    BOSS_DEATH_TICK=0
}
