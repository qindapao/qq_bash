# classes/plane/plane.sh — Plane（玩家飞机）
[[ -n "${_STRAFE_PLANE_SH:-}" ]] && return 0
_STRAFE_PLANE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_helpers.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/bullet.sh"

readonly PlaneStaticTemplate='
    PlaneObj ->
        {CLS} => Plane
        {SUP} => Entity
        {MIX} => 
        {x} => 0
        {y} => 0
        {w} => 3
        {h} => 2
        {art} => 
        {al} => 1
        {hp} => 20
        {score} => 0
        {symbol} => ^
        {bullet} => 
        {bombs} => 0
        {t2} => 0
        {t3} => 0
        {t4} => 0
        {t5} => 0
        {mt} => 0
        {lanes} => 0
        {lanes_side} => 0
        {lt} => 0
        {shield} => 0
        {st} => 0
        {prev_shield} => 0
    '
Plane_born () {
    local -n self=$1
    self["{x}$X"]=$(( SCREEN_W / 2 ))
    self["{y}$X"]=$(( SCREEN_H - 2 ))
    self["{art}$X"]="$PLANE_ART_BASE"
    self["{al}$X"]=1
}
Plane_kill () {
    Entity_kill "$1"
    local -n self=$1
    local bt=${self["{bullet}$X"]}
    [[ -n "$bt" && -n "${XO_OBJ_POOL[$bt]+_}" ]] && xo_obj_kill "$bt"
}
Plane_move () {
    local -n self=$1
    local dx=${2:-0} dy=${3:-0}
    local _al=${self["{al}$X"]:-1}
    local _sh=${self["{shield}$X"]:-0}
    local x=$(( ${self["{x}$X"]} + dx ))
    local y=$(( ${self["{y}$X"]} + dy ))
    local _minx=$(( _al + 2 ))
    local _maxx=$(( SCREEN_W - _al - 2 ))
    (( x < _minx )) && x=$_minx
    (( x > _maxx )) && x=$_maxx
    local _miny=$GAME_TOP
    (( _sh )) && _miny=$(( GAME_TOP + 1 ))
    (( y < _miny )) && y=$_miny
    (( y > SCREEN_H - 2 )) && y=$(( SCREEN_H - 2 ))
    self["{x}$X"]=$x
    self["{y}$X"]=$y
}
Plane_fire () {
    local -n self=$1
    local bt=${self["{bullet}$X"]}
    local -n bt_obj=$bt
    local sym=${bt_obj["{symbol}$X"]}
    local dmg=${bt_obj["{damage}$X"]}
    unset -n bt_obj

    local _fx=${self["{x}$X"]}
    local _fy=$(( ${self["{y}$X"]} - 1 ))
    local _lanes=${self["{lanes}$X"]:-0}
    local _side=${self["{lanes_side}$X"]:-0}
    local _is_laser=0
    [[ "$sym" == "|" ]] && _is_laser=1

    xo_obj_born Bullet "$_fx" "$_fy" "$sym" "$dmg" 0 -1
    BULLETS+=("$REPLY")

    if (( _lanes >= 1 )) ; then
        local _do_l=0 _do_r=0
        if (( _lanes == 1 )) ; then
            if (( _side == 0 )) ; then _do_l=1 ; else _do_r=1 ; fi
        else
            _do_l=1 ; _do_r=1
        fi
        if (( _do_l )) ; then
            local _lsym="$sym"
            (( _is_laser )) && _lsym='\'
            xo_obj_born Bullet "$_fx" "$_fy" "$_lsym" "$dmg" -1 -1
            BULLETS+=("$REPLY")
        fi
        if (( _do_r )) ; then
            local _rsym="$sym"
            (( _is_laser )) && _rsym='/'
            xo_obj_born Bullet "$_fx" "$_fy" "$_rsym" "$dmg" 1 -1
            BULLETS+=("$REPLY")
        fi
    fi

    if (( _lanes >= 3 )) ; then
        local _do_ol=0 _do_or=0
        if (( _lanes == 3 )) ; then
            if (( _side == 0 )) ; then _do_ol=1 ; else _do_or=1 ; fi
        else
            _do_ol=1 ; _do_or=1
        fi
        if (( _do_ol )) ; then
            local _losym="$sym"
            (( _is_laser )) && _losym='-'
            local _lox=$(( _fx - 2 ))
            (( _lox < 2 )) && _lox=2
            xo_obj_born Bullet "$_lox" "$_fy" "$_losym" "$dmg" -1 0
            BULLETS+=("$REPLY")
        fi
        if (( _do_or )) ; then
            local _rosym="$sym"
            (( _is_laser )) && _rosym='-'
            local _rox=$(( _fx + 2 ))
            (( _rox > SCREEN_W - 2 )) && _rox=$(( SCREEN_W - 2 ))
            xo_obj_born Bullet "$_rox" "$_fy" "$_rosym" "$dmg" 1 0
            BULLETS+=("$REPLY")
        fi
    fi
}
