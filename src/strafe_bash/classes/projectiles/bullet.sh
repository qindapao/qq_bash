# classes/projectiles/bullet.sh — Bullet
[[ -n "${_STRAFE_BULLET_SH:-}" ]] && return 0
_STRAFE_BULLET_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"

readonly BulletStaticTemplate='
    BulletObj ->
        {CLS} => Bullet
        {SUP} => Entity
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => .
        {damage} => 1
        {vx} => 0
        {vy} => -1
    '
Bullet_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{symbol}$X"]=$4
    self["{damage}$X"]=$5
    self["{vx}$X"]=${6:-0}
    self["{vy}$X"]=${7:--1}
}
Bullet_move () {
    local -n self=$1
    CLEAR_BATCH+=("${self["{y}$X"]}" "${self["{x}$X"]}")
    self["{x}$X"]=$(( ${self["{x}$X"]} + ${self["{vx}$X"]} ))
    self["{y}$X"]=$(( ${self["{y}$X"]} + ${self["{vy}$X"]} ))
}
