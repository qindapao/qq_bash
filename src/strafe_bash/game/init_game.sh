# game/init_game.sh — 每局初始化（重置玩家状态、清理所有对象）
[[ -n "${_STRAFE_INIT_GAME_SH:-}" ]] && return 0
_STRAFE_INIT_GAME_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"

init_game () {
    local -n p=$PLAYER
    p["{x}$X"]=$(( SCREEN_W / 2 ))
    p["{y}$X"]=$(( SCREEN_H - 2 ))
    p["{hp}$X"]=${p["{maxhp}$X"]:-20}
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
    p["{blink}$X"]=0
    p["{ram_cd}$X"]=0
    p["{prev_shield}$X"]=0
    p["{art}$X"]=${p["{base_art}$X"]}
    p["{al}$X"]=${p["{base_al}$X"]:-1}

    # ---- 本局武器：默认 tier0 + 每档随机抽一个 tier2..5 ----
    # 先清掉上一局留下的具名武器对象
    local _wi _wn
    for _wi in 1 2 3 4 5 ; do
        _wn="OBJ_wpn$_wi"
        [[ -n "${XO_OBJ_POOL[$_wn]+_}" ]] && xo_obj_kill "$_wn"
    done

    # 默认子弹（tier 0，独立于 1..5 号库，不参与随机）
    xo_obj_born_named OBJ_wpn1 BulletTypeDefault || { unset -n p ; return 1 ; }
    p["{w1}$X"]=$REPLY
    p["{bullet}$X"]=$REPLY

    # tier 2..5：每档从自己的库里随机抽一个类，组成本局可掉落的 4 种武器
    local _tier _cls _libname _n
    for _tier in 2 3 4 5 ; do
        _libname="BULLET_LIB_$_tier"
        local -n _lib=$_libname
        _n=${#_lib[@]}
        if (( _n == 0 )) ; then
            unset -n _lib
            unset -n p
            die ERR "BULLET_LIB_$_tier is empty"
            return 1
        fi
        _cls=${_lib[RANDOM % _n]}
        unset -n _lib
        xo_obj_born_named "OBJ_wpn$_tier" "$_cls" || { unset -n p ; return 1 ; }
        p["{w$_tier}$X"]=$REPLY
    done
    unset -n p

    local b e d eb m w
    for b in "${BULLETS[@]}" ; do [[ -n "${XO_OBJ_POOL[$b]+_}" ]] && xo_obj_kill "$b" ; done
    for e in "${ENEMIES[@]}" ; do [[ -n "${XO_OBJ_POOL[$e]+_}" ]] && xo_obj_kill "$e" ; done
    for d in "${DROPS[@]}" ; do [[ -n "${XO_OBJ_POOL[$d]+_}" ]] && xo_obj_kill "$d" ; done
    for eb in "${ENEMY_BULLETS[@]}" ; do [[ -n "${XO_OBJ_POOL[$eb]+_}" ]] && xo_obj_kill "$eb" ; done
    for m in "${MISSILES[@]}" ; do [[ -n "${XO_OBJ_POOL[$m]+_}" ]] && xo_obj_kill "$m" ; done
    for w in "${WORDS[@]}" ; do [[ -n "${XO_OBJ_POOL[$w]+_}" ]] && xo_obj_kill "$w" ; done
    BULLETS=() ENEMIES=() DROPS=() ENEMY_BULLETS=() MISSILES=()
    BOMB_FX_POS=() HIT_FX=() BOSS_DEATH_POS=() CLEAR_BATCH=() WORDS=()
    BOSS_DEATH_TICK=0
    BOSS_DEATH_STYLE=0
    BOSS_DEATH_CX=0
    BOSS_DEATH_CY=0
    BOSS_DEATH_WAVE=0
    CLEAR_BANNER_TICK=0
    CLEAR_BANNER_FRAME=0
    CLEAR_BANNER_TEXT=''

    G_FIRE_CD=0
    G_MISSILE_CD=0
    G_MISSILE_SIDE=0
    G_INV=0
    G_ENEMY_TICK=0
    G_DROP_TICK=0
    G_WORD_TICK=0
    G_B_DRY=0
    G_BOSS_DRY=0
    G_DX=0
    G_DY=0
    G_WANT_BOMB=0
    G_GAME_OVER=0
    G_RUN_TICKS=0
    G_KILLS=0
    G_BOSS_KILLS=0

    # 同步 prev = cur（避免首帧擦 (0,0)）
    local _sync_obj
    for _sync_obj in "$PLAYER" "${BULLETS[@]}" "${MISSILES[@]}" \
                     "${ENEMY_BULLETS[@]}" "${ENEMIES[@]}" \
                     "${DROPS[@]}" "${WORDS[@]}" ; do
        [[ -n "$_sync_obj" && -n "${XO_OBJ_POOL[$_sync_obj]+_}" ]] || continue
        local -n _so=$_sync_obj
        if [[ -n "${_so[{x}$X]+_}" ]] ; then
            _so["{prev_x}$X"]=${_so["{x}$X"]}
            _so["{prev_y}$X"]=${_so["{y}$X"]}
        fi
        if [[ -n "${_so[{shield}$X]+_}" ]] ; then
            _so["{prev_shield}$X"]=${_so["{shield}$X"]}
        fi
        if [[ -n "${_so[{art}$X]+_}" && -n "${_so[{al}$X]+_}" ]] ; then
            _so["{prev_art}$X"]=${_so["{art}$X"]}
            _so["{prev_al}$X"]=${_so["{al}$X"]}
        fi
        unset -n _so
    done
}
