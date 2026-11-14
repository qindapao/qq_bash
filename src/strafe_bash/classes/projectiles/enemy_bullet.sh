# classes/projectiles/enemy_bullet.sh — EnemyBullet
[[ -n "${_STRAFE_ENEMY_BULLET_SH:-}" ]] && return 0
_STRAFE_ENEMY_BULLET_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"

readonly EnemyBulletStaticTemplate='
    EnemyBulletObj ->
        {CLS} => EnemyBullet
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => .
        {damage} => 1
        {cd} => 0
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
    printf '\033[%d;%dH ' "${self["{y}$X"]}" "${self["{x}$X"]}"
    self["{y}$X"]=$(( ${self["{y}$X"]} + 1 ))
    (( ${self["{y}$X"]} >= SCREEN_H - 1 )) && return 1
    return 0
}
