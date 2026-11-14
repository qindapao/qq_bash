# classes/projectiles/skull_bullet.sh — SkullBullet
# 骷髅王的巨型跟踪弹：3 行 × 5 列，多格子碰撞，燃料耗尽后自毁。
[[ -n "${_STRAFE_SKULL_BULLET_SH:-}" ]] && return 0
_STRAFE_SKULL_BULLET_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"

readonly SKULL_BULLET_ART=$' .-. \n(o.o)\n |=| '
readonly SkullBulletStaticTemplate='
    SkullBulletObj ->
        {CLS} => SkullBullet
        {SUP} => Entity
        {MIX} => 
        {x} => 0
        {y} => 0
        {w} => 5
        {h} => 3
        {art} => 
        {ttl} => 240
        {damage} => 5
        {cd} => 0
        {step} => 3
        {color} => 
    '
SkullBullet_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{art}$X"]=$SKULL_BULLET_ART
    self["{ttl}$X"]=${4:-240}
    self["{damage}$X"]=${5:-5}
    self["{step}$X"]=${6:-3}
    self["{color}$X"]=${7:-$C_RED}
    self["{cd}$X"]=0
}
SkullBullet_move () {
    local -n self=$1
    local -i ttl=$(( ${self["{ttl}$X"]:-0} - 1 ))
    (( ttl <= 0 )) && { unset -n self ; return 1 ; }
    self["{ttl}$X"]=$ttl
    local -i cd=$(( ${self["{cd}$X"]:-0} + 1 ))
    local -i step=${self["{step}$X"]:-2}
    (( step < 1 )) && step=1
    (( cd < step )) && { self["{cd}$X"]=$cd ; unset -n self ; return 0 ; }
    self["{cd}$X"]=0

    local -i x=${self["{x}$X"]} y=${self["{y}$X"]}
    local -i w=${self["{w}$X"]} h=${self["{h}$X"]}
    if [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] ; then
        local -n _p=$PLAYER
        local -i px=${_p["{x}$X"]} py=${_p["{y}$X"]}
        unset -n _p
        local -i cx=$(( x + w / 2 )) cy=$(( y + h / 2 ))
        (( cx < px )) && ((x++))
        (( cx > px )) && ((x--))
        (( cy < py )) && ((y++))
        (( cy > py )) && ((y--))
    fi
    self["{x}$X"]=$x
    self["{y}$X"]=$y
    (( x < 2 || x + w > SCREEN_W - 1 || y < GAME_TOP || y + h > SCREEN_H - 1 )) && {
        unset -n self ; return 1
    }
    unset -n self
    return 0
}
