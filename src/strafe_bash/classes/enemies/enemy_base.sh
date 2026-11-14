# classes/enemies/enemy_base.sh — Enemy 基类 + _enemy_fire
[[ -n "${_STRAFE_ENEMY_BASE_SH:-}" ]] && return 0
_STRAFE_ENEMY_BASE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"

readonly EnemyStaticTemplate='
    EnemyObj ->
        {CLS} => Enemy
        {SUP} => Entity
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => 
        {hp} => 1
        {maxhp} => 1
        {score} => 0
        {cd} => 0
        {vx} => 0
        {vy} => 1
        {w} => 1
        {h} => 1
        {art} => 
    '
Enemy_born () {
    local -n self=$1
    local w=${self["{w}$X"]:-1}
    (( w < 1 )) && w=1
    self["{x}$X"]=$(( RANDOM % (SCREEN_W - 2 - w) + 2 ))
    self["{y}$X"]=$GAME_TOP
    self["{vx}$X"]=0
    self["{vy}$X"]=1
    self["{cd}$X"]=0
}

_enemy_fire () {
    local e=$1 percent=$2 esym=$3 edmg=$4
    (( RANDOM % 100 < percent )) || return 0
    local -n _e=$e
    local _fw=${_e["{w}$X"]}
    local _fy=$(( ${_e["{y}$X"]} + ${_e["{h}$X"]} ))
    local _fx=$(( ${_e["{x}$X"]} + _fw / 2 ))
    xo_obj_born EnemyBullet "$_fx" "$_fy" "$esym" "$edmg"
    ENEMY_BULLETS+=("$REPLY")
    unset -n _e
}
