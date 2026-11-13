# classes/enemies/enemy_b.sh — EnemyB
[[ -n "${_STRAFE_ENEMY_B_SH:-}" ]] && return 0
_STRAFE_ENEMY_B_SH=1
. "$(dirname "${BASH_SOURCE[0]}")/enemy_base.sh"

readonly EnemyBStaticTemplate='
    EnemyBObj ->
        {CLS} => EnemyB
        {SUP} => Enemy
        {MIX} => 
        {symbol} => B
        {hp} => 30
        {maxhp} => 30
        {score} => 500
        {w} => 5
        {h} => 3
    '
EnemyB_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' ___ \n| B |\n|___|'
}
EnemyB_move () {
    local -n self=$1
    _enemy_fire "$1" 3 '+' 3
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 14 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
    (( _ay + _h < SCREEN_H )) && { printf '\033[%d;%dH\033[K\033[%d;%dH%s' $((_ay + _h)) "$_ax" $((_ay + _h)) "$SCREEN_W" "$FRAME_V" ; }
    local vx=${self["{vx}$X"]}
    (( RANDOM % 4 == 0 )) && vx=$(( (RANDOM % 3) - 1 ))
    self["{vx}$X"]=$vx
    local x=$(( _ax + vx ))
    (( x < 2 )) && x=2
    (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
    self["{x}$X"]=$x
    local vy=${self["{vy}$X"]}
    (( RANDOM % 8 == 0 )) && vy=$(( (RANDOM % 2) * 2 - 1 ))
    local y=$(( _ay + vy ))
    if (( y + _h >= SCREEN_H - 1 )) ; then
        y=$(( SCREEN_H - 2 - _h )) ; vy=-1
    elif (( y < GAME_TOP )) ; then
        y=$GAME_TOP ; vy=1
    fi
    self["{vy}$X"]=$vy
    self["{y}$X"]=$y
    return 0
}
