# classes/enemies/enemy_v.sh — EnemyV
[[ -n "${_STRAFE_ENEMY_V_SH:-}" ]] && return 0
_STRAFE_ENEMY_V_SH=1
. "$(dirname "${BASH_SOURCE[0]}")/enemy_base.sh"

readonly EnemyVStaticTemplate='
    EnemyVObj ->
        {CLS} => EnemyV
        {SUP} => Enemy
        {MIX} => 
        {symbol} => v
        {hp} => 1
        {maxhp} => 1
        {score} => 10
        {w} => 3
        {h} => 2
    '
EnemyV_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' v \n/ \\'
}
EnemyV_move () {
    local -n self=$1
    _enemy_fire "$1" 2 '.' 1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 6 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
    (( RANDOM % 3 == 0 )) && {
        local dx=$(( (RANDOM % 2) * 2 - 1 ))
        local x=$(( _ax + dx ))
        (( x < 2 )) && x=2
        (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
        self["{x}$X"]=$x
    }
    self["{y}$X"]=$(( _ay + 1 ))
    (( ${self["{y}$X"]} + _h > SCREEN_H - 1 )) && return 1
    return 0
}
