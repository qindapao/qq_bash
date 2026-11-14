# classes/projectiles/missile.sh — Missile
[[ -n "${_STRAFE_MISSILE_SH:-}" ]] && return 0
_STRAFE_MISSILE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"

readonly MissileStaticTemplate='
    MissileObj ->
        {CLS} => Missile
        {SUP} => Entity
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
    local -i x=${self["{x}$X"]} y=${self["{y}$X"]}
    local -i vx=0 vy=-1
    local _e _ex _ey _dx _dy _d _best=999999

    # 自动锁定最近的敌机；没有目标时继续向上飞。
    for _e in "${ENEMIES[@]}" ; do
        [[ -n "$_e" && -n "${XO_OBJ_POOL[$_e]+_}" ]] || continue
        local -n _me=$_e
        _ex=${_me["{x}$X"]} ; _ey=${_me["{y}$X"]}
        unset -n _me
        _dx=$(( _ex - x )) ; _dy=$(( _ey - y ))
        (( _dx < 0 )) && _dx=$(( -_dx ))
        (( _dy < 0 )) && _dy=$(( -_dy ))
        _d=$(( _dx + _dy ))
        if (( _d < _best )) ; then
            _best=$_d
            if (( _ex < x )) ; then vx=-1
            elif (( _ex > x )) ; then vx=1
            else vx=0 ; fi
            if (( _ey < y )) ; then vy=-1
            elif (( _ey > y )) ; then vy=1
            else vy=0 ; fi
        fi
    done

    self["{vx}$X"]=$vx ; self["{vy}$X"]=$vy
    self["{x}$X"]=$(( x + vx ))
    self["{y}$X"]=$(( y + vy ))
    if (( vy < 0 )) ; then self["{symbol}$X"]='^'
    elif (( vy > 0 )) ; then self["{symbol}$X"]='v'
    elif (( vx < 0 )) ; then self["{symbol}$X"]='<'
    elif (( vx > 0 )) ; then self["{symbol}$X"]='>'
    fi
    (( ${self["{x}$X"]} < 2 )) && return 1
    (( ${self["{x}$X"]} > SCREEN_W - 2 )) && return 1
    (( ${self["{y}$X"]} < GAME_TOP )) && return 1
    (( ${self["{y}$X"]} >= SCREEN_H - 1 )) && return 1
    return 0
}
