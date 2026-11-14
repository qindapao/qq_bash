# classes/enemies/boss_spinner.sh — BossSpinner（旋刃，继承 BossBase）
[[ -n "${_STRAFE_BOSS_SPINNER_SH:-}" ]] && return 0
_STRAFE_BOSS_SPINNER_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_base.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/boss_bullet.sh"

# 旋刃四阶段 art（来自任务二设计稿）。
readonly BOSS_SPINNER_ART_0=$'   o  >-----<  o\n    \\/  .-.  \\/\n    |  ( O )  |\n    /\\  \'-\'  /\\\n   o  >-----<  o'
readonly BOSS_SPINNER_ART_1=$'   o  >-----<\n    \\/  .-.  \\\n    |  ( O )  |\n     \\  \'-\'  /\\\n      >-----<  o'
readonly BOSS_SPINNER_ART_2=$'      >-----<\n     /  .-.  \\\n    |  ( O )  |\n     \\  \'-\'  /\n      >-----<'
readonly BOSS_SPINNER_ART_3=$'      .-----.\n     /  .-.  \\\n    |  ( X )  |\n     \\  \'-\'  /\n      \'-----\''

readonly BossSpinnerStaticTemplate='
    BossSpinnerObj ->
        {CLS} => BossSpinner
        {SUP} => BossBase
        {MIX} => 
        {w} => 16
        {h} => 5
        {hp} => 250
        {maxhp} => 250
        {score} => 8000
        {symbol} => S
        {pcut1} => 75
        {pcut2} => 50
        {pcut3} => 25
        {death_style} => 1
        {ring_cd} => 0
        {aim_cd} => 0
        {spin} => 0
    '
BossSpinner_born () {
    _boss_set_arts "$1" "$BOSS_SPINNER_ART_0" "$BOSS_SPINNER_ART_1" "$BOSS_SPINNER_ART_2" "$BOSS_SPINNER_ART_3"
    BossBase_born "$1"
    local -n _self=$1
    _self["{ring_cd}$X"]=18
    _self["{aim_cd}$X"]=36
    _self["{spin}$X"]=0
    unset -n _self
}

# 旋转环：8 方向留 2 个对向缺口，每轮转 45°。
_boss_spinner_ring () {
    local -n _bs=$1
    local -i _cx=$(( ${_bs["{x}$X"]} + ${_bs["{w}$X"]} / 2 ))
    local -i _cy=$(( ${_bs["{y}$X"]} + ${_bs["{h}$X"]} / 2 ))
    local -i _spin=${_bs["{spin}$X"]:-0}
    if (( ${#ENEMY_BULLETS[@]} + 6 > BOSS_BULLET_LIMIT )) ; then
        unset -n _bs
        return 0
    fi
    local -a _dx=(0 1 1 1 0 -1 -1 -1)
    local -a _dy=(-1 -1 0 1 1 1 0 -1)
    local -i _i _s1=$_spin _s2=$(( (_spin + 4) % 8 ))
    for ((_i=0; _i<8; _i++)) ; do
        (( _i == _s1 || _i == _s2 )) && continue
        xo_obj_born BossBullet "$_cx" "$_cy" "${_dx[_i]}" "${_dy[_i]}" 'o' 1 2 "$C_CYAN"
        ENEMY_BULLETS+=("$REPLY")
    done
    _bs["{spin}$X"]=$(( (_spin + 1) % 8 ))
    unset -n _bs
}

# 瞄准散弹：朝玩家所在八分方向打 3 发，左右各偏一格。
_boss_spinner_aim () {
    local -n _bs=$1
    local -i _cx=$(( ${_bs["{x}$X"]} + ${_bs["{w}$X"]} / 2 ))
    local -i _cy=$(( ${_bs["{y}$X"]} + ${_bs["{h}$X"]} / 2 ))
    unset -n _bs

    [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] || return 0
    local -n _p=$PLAYER
    local -i _px=${_p["{x}$X"]} _py=${_p["{y}$X"]}
    unset -n _p
    local -i _dx=$(( _px - _cx )) _dy=$(( _py - _cy ))
    local -i _bi
    if (( _dx == 0 && _dy == 0 )) ; then
        _bi=4
    elif (( _dy < 0 )) ; then
        if (( _dx < 0 )) ; then _bi=7 ; elif (( _dx > 0 )) ; then _bi=1 ; else _bi=0 ; fi
    elif (( _dy > 0 )) ; then
        if (( _dx < 0 )) ; then _bi=5 ; elif (( _dx > 0 )) ; then _bi=3 ; else _bi=4 ; fi
    else
        if (( _dx < 0 )) ; then _bi=6 ; else _bi=2 ; fi
    fi
    if (( ${#ENEMY_BULLETS[@]} + 3 > BOSS_BULLET_LIMIT )) ; then
        return 0
    fi
    local -a _dxs=(0 1 1 1 0 -1 -1 -1)
    local -a _dys=(-1 -1 0 1 1 1 0 -1)
    local -i _o _i
    for _o in -1 0 1 ; do
        _i=$(( (_bi + _o + 8) % 8 ))
        xo_obj_born BossBullet "$_cx" "$_cy" "${_dxs[_i]}" "${_dys[_i]}" 'x' 2 2 "$C_ORANGE"
        ENEMY_BULLETS+=("$REPLY")
    done
}

BossSpinner_move () {
    _boss_update_phase "$1"
    local -n self=$1

    # 3 tick 一格、1% 中途变向、目标打屏幕左右边缘：
    # 速度比之前慢，但每次目标更远，活动范围覆盖整块场地。
    local -i _yhi=$(( SCREEN_H - 3 - ${self["{h}$X"]} ))
    _boss_move_target "$1" 3 "$_yhi" 1 80 21 3 1

    local -i _phase=${self["{phase}$X"]}
    local -i _ring_every=30 _aim_every=45
    (( _phase == 3 )) && { _ring_every=24 ; _aim_every=36 ; }

    local -i _rc=$(( ${self["{ring_cd}$X"]:-0} - 1 ))
    if (( _rc <= 0 )) ; then
        self["{ring_cd}$X"]=$_ring_every
        _boss_spinner_ring "$1"
    else
        self["{ring_cd}$X"]=$_rc
    fi
    local -i _ac=$(( ${self["{aim_cd}$X"]:-0} - 1 ))
    if (( _ac <= 0 )) ; then
        self["{aim_cd}$X"]=$_aim_every
        _boss_spinner_aim "$1"
    else
        self["{aim_cd}$X"]=$_ac
    fi
    unset -n self
    return 0
}
