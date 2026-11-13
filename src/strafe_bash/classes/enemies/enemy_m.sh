# classes/enemies/enemy_m.sh — EnemyM
[[ -n "${_STRAFE_ENEMY_M_SH:-}" ]] && return 0
_STRAFE_ENEMY_M_SH=1
. "$(dirname "${BASH_SOURCE[0]}")/enemy_base.sh"

readonly EnemyMStaticTemplate='
    EnemyMObj ->
        {CLS} => EnemyM
        {SUP} => Enemy
        {MIX} => 
        {symbol} => M
        {hp} => 10
        {maxhp} => 10
        {score} => 100
        {w} => 5
        {h} => 3
    '
EnemyM_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' ___ \n| M |\n|___|'
}
EnemyM_move () {
    local -n self=$1
    _enemy_fire "$1" 4 '+' 3
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 14 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
    (( _ay + _h < SCREEN_H )) && { printf '\033[%d;%dH\033[K\033[%d;%dH%s' $((_ay + _h)) "$_ax" $((_ay + _h)) "$SCREEN_W" "$FRAME_V" ; }
    (( RANDOM % 3 == 0 )) && {
        local dx=$(( (RANDOM % 2) * 2 - 1 ))
        local x=$(( _ax + dx ))
        (( x < 2 )) && x=2
        (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
        self["{x}$X"]=$x
    }
    local vy=${self["{vy}$X"]}
    (( RANDOM % 7 == 0 )) && vy=$(( -vy ))
    self["{vy}$X"]=$vy
    local y=$(( _ay + vy ))
    (( y < GAME_TOP )) && { y=$GAME_TOP ; self["{vy}$X"]=1 ; }
    self["{y}$X"]=$y
    (( y + _h > SCREEN_H - 1 )) && return 1
    return 0
}
