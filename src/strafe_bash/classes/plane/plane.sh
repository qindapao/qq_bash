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
        {w1} => 
        {w2} => 
        {w3} => 
        {w4} => 
        {w5} => 
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
    local i wpn
    for i in 1 2 3 4 5 ; do
        wpn=${self["{w$i}$X"]}
        [[ -n "$wpn" && -n "${XO_OBJ_POOL[$wpn]+_}" ]] && xo_obj_kill "$wpn"
    done
    unset -n self
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
    local wpn=${self["{bullet}$X"]}
    if [[ -z "$wpn" || -z "${XO_OBJ_POOL[$wpn]+_}" ]] ; then
        G_FIRE_CD=6
        return 0
    fi

    # 当前武器的 8 方向字符 / 伤害 / 射速 / 弹速
    local -n w=$wpn
    local dmg=${w["{damage}$X"]:-1}
    local cd=${w["{cd}$X"]:-6}
    local spd=${w["{spd}$X"]:-1}
    local su=${w["{u}$X"]:-.}
    local sul=${w["{ul}$X"]:-$su}
    local sur=${w["{ur}$X"]:-$su}
    local sl=${w["{l}$X"]:-$su}
    local sr=${w["{r}$X"]:-$su}
    unset -n w

    (( spd < 1 )) && spd=1
    (( cd < 0 ))  && cd=0
    G_FIRE_CD=$cd

    local _fx=${self["{x}$X"]}
    local _fy=$(( ${self["{y}$X"]} - 1 ))
    local _lanes=${self["{lanes}$X"]:-0}
    local _side=${self["{lanes_side}$X"]:-0}
    local -i _up=$(( -spd )) _left=$(( -spd )) _right=$spd

    # 正中：向上
    xo_obj_born Bullet "$_fx" "$_fy" "$su" "$dmg" 0 "$_up"
    BULLETS+=("$REPLY")

    if (( _lanes >= 1 )) ; then
        local _do_l=0 _do_r=0
        if (( _lanes == 1 )) ; then
            if (( _side == 0 )) ; then _do_l=1 ; else _do_r=1 ; fi
        else
            _do_l=1 ; _do_r=1
        fi
        if (( _do_l )) ; then
            # 左上：用该武器的 {ul} 字符
            xo_obj_born Bullet "$_fx" "$_fy" "$sul" "$dmg" "$_left" "$_up"
            BULLETS+=("$REPLY")
        fi
        if (( _do_r )) ; then
            # 右上：用该武器的 {ur} 字符
            xo_obj_born Bullet "$_fx" "$_fy" "$sur" "$dmg" "$_right" "$_up"
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
            # 左侧：用该武器的 {l} 字符
            local _lox=$(( _fx - 2 ))
            (( _lox < 2 )) && _lox=2
            xo_obj_born Bullet "$_lox" "$_fy" "$sl" "$dmg" "$_left" 0
            BULLETS+=("$REPLY")
        fi
        if (( _do_or )) ; then
            # 右侧：用该武器的 {r} 字符
            local _rox=$(( _fx + 2 ))
            (( _rox > SCREEN_W - 2 )) && _rox=$(( SCREEN_W - 2 ))
            xo_obj_born Bullet "$_rox" "$_fy" "$sr" "$dmg" "$_right" 0
            BULLETS+=("$REPLY")
        fi
    fi
}
