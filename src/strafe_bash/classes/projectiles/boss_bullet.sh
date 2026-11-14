# classes/projectiles/boss_bullet.sh — BossBullet
[[ -n "${_STRAFE_BOSS_BULLET_SH:-}" ]] && return 0
_STRAFE_BOSS_BULLET_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"

readonly BossBulletStaticTemplate='
    BossBulletObj ->
        {CLS} => BossBullet
        {SUP} => EnemyBullet
        {MIX} => 
        {symbol} => o
        {damage} => 1
        {vx} => 0
        {vy} => 1
        {step} => 2
        {color} => 
    '
BossBullet_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{vx}$X"]=$4
    self["{vy}$X"]=$5
    self["{symbol}$X"]=$6
    self["{damage}$X"]=$7
    self["{step}$X"]=${8:-2}
    self["{color}$X"]=${9:-}
    self["{cd}$X"]=0
}
BossBullet_move () {
    local -n self=$1
    local -i cd=$(( ${self["{cd}$X"]:-0} + 1 ))
    local -i _step=${self["{step}$X"]:-2}
    (( _step < 1 )) && _step=1
    (( cd < _step )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0

    local -i x=$(( ${self["{x}$X"]} + ${self["{vx}$X"]:-0} ))
    local -i y=$(( ${self["{y}$X"]} + ${self["{vy}$X"]:-0} ))
    self["{x}$X"]=$x
    self["{y}$X"]=$y
    (( x < 2 || x > SCREEN_W - 2 || y < GAME_TOP || y >= SCREEN_H - 1 )) && return 1
    return 0
}
