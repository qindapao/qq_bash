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
        # 位置（每 tick 朝最近敌人方向走一格）
        {x} => 0
        {y} => 0
        # 符号：按方向显示 ^ v < >
        {symbol} => ^
        # 单发伤害（由装备等级决定，默认 2）
        {damage} => 2
        # 追踪方向（vx/vy 取值 -1/0/1）
        {vx} => 0
        {vy} => -1
        # 上一个尾迹点：渲染时在身后补一个 '.'，形成一条会拐弯的轨迹
        # -1 表示还没有尾迹（刚出生）
        {prev_trail_x} => -1
        {prev_trail_y} => -1
    '
Missile_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{damage}$X"]=${4:-2}
    self["{vx}$X"]=0
    self["{vy}$X"]=-1
    self["{symbol}$X"]='^'
    self["{prev_trail_x}$X"]=-1
    self["{prev_trail_y}$X"]=-1
}
Missile_move () {
    local -n self=$1
    local -i x=${self["{x}$X"]} y=${self["{y}$X"]}
    local -i vx=0 vy=-1
    local _e _ex _ey _dx _dy _d _best=999999

    # 跟踪算法（贪心，每 tick 只走一格）：
    #
    #   1. 扫描 ENEMIES，用 |dx| + |dy| 找最近的敌机
    #   2. 横向/纵向各取符号，得到下一格方向
    #   3. 没有敌机时保持 (vx,vy)=(0,-1)，继续向上
    #
    #   目标在上方：        目标在右下：
    #        E                  M  →  E
    #        ↑                     ↘
    #        M
    #
    # 这不是寻路，只是“朝目标直走”；目标横向移动时可能绕圈。
    # 对 30Hz 的小地图来说，简单、便宜，而且视觉上足够像跟踪。
    for _e in "${ENEMIES[@]}" ; do
        [[ -n "$_e" && -n "${XO_OBJ_POOL[$_e]+_}" ]] || continue
        local -n _me=$_e
        _ex=${_me["{x}$X"]} ; _ey=${_me["{y}$X"]}
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
