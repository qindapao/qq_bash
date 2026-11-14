# classes/projectiles/missile.sh — Missile
[[ -n "${_STRAFE_MISSILE_SH:-}" ]] && return 0
_STRAFE_MISSILE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"

readonly MissileStaticTemplate='
    MissileObj ->
        {CLS} => Missile
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => ^
        {damage} => 2
        {vx} => 0
        {vy} => -1
    '
Missile_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{damage}$X"]=${4:-2}
    self["{vx}$X"]=0
    self["{vy}$X"]=-1
    self["{symbol}$X"]='^'
}
Missile_move () {
    local -n self=$1
    local _x=${self["{x}$X"]} _y=${self["{y}$X"]}
    printf '\033[%d;%dH ' "$_y" "$_x"

    if (( RANDOM % 10 < 4 )) ; then
        local _r=$(( RANDOM % 20 ))
        if (( _r < 10 )) ; then
            self["{vx}$X"]=0 ; self["{vy}$X"]=-1
        elif (( _r < 15 )) ; then
            self["{vx}$X"]=-1 ; self["{vy}$X"]=0
        else
            self["{vx}$X"]=1 ; self["{vy}$X"]=0
        fi
    fi

    _x=$(( _x + ${self["{vx}$X"]} ))
    _y=$(( _y + ${self["{vy}$X"]} ))
    self["{x}$X"]=$_x
    self["{y}$X"]=$_y

    local _vx=${self["{vx}$X"]} _vy=${self["{vy}$X"]}
    if (( _vy < 0 )) ; then self["{symbol}$X"]='^'
    elif (( _vy > 0 )) ; then self["{symbol}$X"]='v'
    elif (( _vx < 0 )) ; then self["{symbol}$X"]='<'
    elif (( _vx > 0 )) ; then self["{symbol}$X"]='>'
    fi

    (( _x < 2 )) && return 1
    (( _x > SCREEN_W - 2 )) && return 1
    (( _y < GAME_TOP )) && return 1
    (( _y >= SCREEN_H - 1 )) && return 1
    return 0
}
