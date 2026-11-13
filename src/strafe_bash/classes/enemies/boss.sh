# classes/enemies/boss.sh — Boss
[[ -n "${_STRAFE_BOSS_SH:-}" ]] && return 0
_STRAFE_BOSS_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../../config/const.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../../config/art.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../../config/globals.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../projectiles/enemy_bullet.sh"

readonly BossStaticTemplate='
    BossObj ->
        {CLS} => Boss
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {w} => 13
        {h} => 5
        {art} => 
        {hp} => 250
        {maxhp} => 250
        {score} => 5000
        {cd} => 0
        {vx} => 1
        {symbol} => X
        {phase} => 0
    '
Boss_born () {
    local -n self=$1
    self["{x}$X"]=$(( (SCREEN_W - 13) / 2 ))
    self["{y}$X"]=$GAME_TOP
    self["{vx}$X"]=1
    self["{cd}$X"]=0
    self["{phase}$X"]=0
    self["{art}$X"]="$BOSS_ART_100"
}
Boss_move () {
    local -n self=$1

    local _hp=${self["{hp}$X"]} _maxhp=${self["{maxhp}$X"]}
    local _pct=$(( _hp * 100 / _maxhp ))
    local _newphase
    if (( _pct > 70 )) ; then _newphase=0
    elif (( _pct > 50 )) ; then _newphase=1
    elif (( _pct > 20 )) ; then _newphase=2
    else _newphase=3
    fi
    if (( _newphase != ${self["{phase}$X"]} )) ; then
        self["{phase}$X"]=$_newphase
        case "$_newphase" in
            0) self["{art}$X"]="$BOSS_ART_100" ;;
            1) self["{art}$X"]="$BOSS_ART_70" ;;
            2) self["{art}$X"]="$BOSS_ART_50" ;;
            3) self["{art}$X"]="$BOSS_ART_20" ;;
        esac
    fi

    local cd=$(( ${self["{cd}$X"]} + 1 ))
    if (( cd >= 4 )) ; then
        self["{cd}$X"]=0
        local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
        _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
        (( _ay + _h < SCREEN_H )) && { printf '\033[%d;%dH\033[K\033[%d;%dH%s' $((_ay + _h)) "$_ax" $((_ay + _h)) "$SCREEN_W" "$FRAME_V" ; }
        local vx=${self["{vx}$X"]}
        local x=$(( _ax + vx ))
        if (( x < 2 )) ; then
            x=2 ; self["{vx}$X"]=1
        elif (( x + _w > SCREEN_W - 2 )) ; then
            x=$(( SCREEN_W - 2 - _w )) ; self["{vx}$X"]=-1
        fi
        self["{x}$X"]=$x
    else
        self["{cd}$X"]=$cd
    fi

    (( RANDOM % 100 < 8 )) || return 0
    local _by=$(( ${self["{y}$X"]} + ${self["{h}$X"]} ))
    local _bx=${self["{x}$X"]}
    xo_obj_born EnemyBullet $((_bx + 4)) "$_by" '!' 3
    ENEMY_BULLETS+=("$REPLY")
    xo_obj_born EnemyBullet $((_bx + 6)) "$_by" '0' 3
    ENEMY_BULLETS+=("$REPLY")
    xo_obj_born EnemyBullet $((_bx + 8)) "$_by" '!' 3
    ENEMY_BULLETS+=("$REPLY")
    return 0
}
