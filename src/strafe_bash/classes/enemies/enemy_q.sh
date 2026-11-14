# classes/enemies/enemy_q.sh — EnemyQ
[[ -n "${_STRAFE_ENEMY_Q_SH:-}" ]] && return 0
_STRAFE_ENEMY_Q_SH=1
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"

readonly EnemyQStaticTemplate='
    EnemyQObj ->
        {CLS} => EnemyQ
        {SUP} => Enemy
        {MIX} => 
        {symbol} => Q
        {hp} => 5
        {maxhp} => 5
        {score} => 30
        {w} => 3
        {h} => 2
    '
EnemyQ_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' Q \n[_]'
}
EnemyQ_move () {
    local -n self=$1
    _enemy_fire "$1" 3 '.' 1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 10 )) && { self["{cd}$X"]=$cd ; return 0 ; }
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
