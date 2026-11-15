# classes/projectiles/enemy_bullet.sh — EnemyBullet
[[ -n "${_STRAFE_ENEMY_BULLET_SH:-}" ]] && return 0
_STRAFE_ENEMY_BULLET_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"

# 所有敌方单格弹的唯一生成入口。
# 达到 ENEMY_BULLET_LIMIT 时只抑制“新弹”，已有弹照常飞行/命中；
# 这样上限只削极端峰值，不会让场上弹幕突然消失。
enemy_bullet_spawn () {
    (( ${#ENEMY_BULLETS[@]} >= ENEMY_BULLET_LIMIT )) && return 1
    local cls=$1
    shift
    xo_obj_born "$cls" "$@" || return 1
    ENEMY_BULLETS+=("$REPLY")
    return 0
}

readonly EnemyBulletStaticTemplate='
    EnemyBulletObj ->
        {CLS} => EnemyBullet
        {SUP} => Entity
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => .
        {damage} => 1
        {cd} => 0
        {color} => 
    '
EnemyBullet_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{symbol}$X"]=$4
    self["{damage}$X"]=$5
    self["{cd}$X"]=0
}
EnemyBullet_move () {
    local -n self=$1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 4 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    self["{y}$X"]=$(( ${self["{y}$X"]} + 1 ))
    (( ${self["{y}$X"]} >= SCREEN_H - 1 )) && return 1
    return 0
}
