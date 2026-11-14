# classes/enemies/boss_base.sh — BossBase 抽象基类
[[ -n "${_STRAFE_BOSS_BASE_SH:-}" ]] && return 0
_STRAFE_BOSS_BASE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

# 所有 Boss 的公共字段和公共行为。
# 具体 Boss 只在自己的模板里覆盖 w/h/hp/art/pcut/death_style。
readonly BossBaseStaticTemplate='
    BossBaseObj ->
        {CLS} => BossBase
        {SUP} => Entity
        {MIX} => 
        {x} => 0
        {y} => 0
        {w} => 13
        {h} => 5
        {art} => 
        {art0} => 
        {art1} => 
        {art2} => 
        {art3} => 
        {hp} => 150
        {maxhp} => 150
        {score} => 5000
        {cd} => 0
        {symbol} => X
        {phase} => 0
        {tx} => 0
        {ty} => 0
        {ttl} => 0
        {pcut1} => 70
        {pcut2} => 50
        {pcut3} => 20
        {death_style} => 0
    '
BossBase_born () {
    local -n self=$1
    local -i _w=${self["{w}$X"]:-13}
    local -i _bx=$(( (SCREEN_W - _w) / 2 ))
    self["{x}$X"]=$_bx
    self["{y}$X"]=$GAME_TOP
    self["{cd}$X"]=0
    self["{phase}$X"]=0
    self["{art}$X"]=${self["{art0}$X"]}
    self["{tx}$X"]=$_bx
    self["{ty}$X"]=$GAME_TOP
    self["{ttl}$X"]=0
}

# 具体 Boss 在 born 时把四段 art 写进自己的类字段。
_boss_set_arts () {
    local -n _ba=$1
    _ba["{art0}$X"]=$2
    _ba["{art1}$X"]=$3
    _ba["{art2}$X"]=$4
    _ba["{art3}$X"]=$5
    unset -n _ba
}

# 按 hp 百分比刷新阶段，阶段 art 从 {art0..3} 读取。
# 具体 Boss 只改 {pcut1..3} 即可，不再在 move 里写死 art 变量。
_boss_update_phase () {
    local -n _bs=$1
    local -i _hp=${_bs["{hp}$X"]:-0}
    local -i _maxhp=${_bs["{maxhp}$X"]:-0}
    (( _maxhp > 0 )) || _maxhp=1
    local -i _pct=$(( _hp * 100 / _maxhp ))
    local -i _p1=${_bs["{pcut1}$X"]:-70}
    local -i _p2=${_bs["{pcut2}$X"]:-50}
    local -i _p3=${_bs["{pcut3}$X"]:-20}
    local -i _newphase
    if (( _pct > _p1 )) ; then _newphase=0
    elif (( _pct > _p2 )) ; then _newphase=1
    elif (( _pct > _p3 )) ; then _newphase=2
    else _newphase=3
    fi
    if (( _newphase != ${_bs["{phase}$X"]:-0} )) ; then
        _bs["{phase}$X"]=$_newphase
        _bs["{art}$X"]=${_bs["{art$_newphase}$X"]}
        _bs["{ttl}$X"]=0        # 阶段变化立即换一条轨迹
    fi
    unset -n _bs
}

# 公共目标点移动。
# $1=obj $2=移动间隔 $3=纵向目标上限 $4=中途变向概率
# $5=ttl 基数 $6=ttl 随机范围
# $7=y 底部留白（默认 4，旋刃可传 3 换更大活动范围）
# $8=边缘巡逻模式（默认 0；旋刃传 1，目标点打屏幕边缘）
_boss_move_target () {
    local obj=$1
    local -i _step=$2 _yhi=$3 _jitter=$4 _ttl_base=$5 _ttl_span=$6
    local -i _ymargin=${7:-4} _wide=${8:-0}
    local -n _bs=$obj

    local -i _w=${_bs["{w}$X"]:-1} _h=${_bs["{h}$X"]:-1}
    local -i _xmin=2 _xmax=$(( SCREEN_W - 2 - _w ))
    # y 上限留出 HP 条那一行，避免 Boss 的 [K 清行擦掉玩家
    local -i _ymin=$GAME_TOP _ymax=$(( SCREEN_H - _ymargin - _h ))
    (( _xmax < _xmin )) && _xmax=$_xmin
    (( _ymax < _ymin )) && _ymax=$_ymin
    (( _yhi > _ymax )) && _yhi=$_ymax
    (( _yhi < _ymin )) && _yhi=$_ymin

    local -i _cd=$(( ${_bs["{cd}$X"]:-0} + 1 ))
    if (( _cd >= _step )) ; then
        _bs["{cd}$X"]=0

        local -i x=${_bs["{x}$X"]:-0} y=${_bs["{y}$X"]:-0}
        local -i tx=${_bs["{tx}$X"]:-0} ty=${_bs["{ty}$X"]:-0} ttl=${_bs["{ttl}$X"]:-0}

        (( x < _xmin )) && x=$_xmin
        (( x > _xmax )) && x=$_xmax
        (( y < _ymin )) && y=$_ymin
        (( y > _ymax )) && y=$_ymax

        if (( ttl <= 0 || (x == tx && y == ty) )) || (( RANDOM % 100 < _jitter )) ; then
            if (( _wide )) ; then
                # 旋刃：主要打左右对面边缘，偶尔打上下边缘。
                # 目标在屏幕边缘，避免只在中间小范围打圈。
                local -i _xmid=$(( (_xmin + _xmax) / 2 ))
                if (( RANDOM % 5 == 0 )) ; then
                    if (( RANDOM % 2 )) ; then ty=$_ymin ; else ty=$_yhi ; fi
                    tx=$(( RANDOM % (_xmax - _xmin + 1) + _xmin ))
                else
                    if (( x < _xmid )) ; then tx=$_xmax ; else tx=$_xmin ; fi
                    ty=$(( RANDOM % (_yhi - _ymin + 1) + _ymin ))
                fi
            else
                tx=$(( RANDOM % (_xmax - _xmin + 1) + _xmin ))
                ty=$(( RANDOM % (_yhi - _ymin + 1) + _ymin ))
            fi
            ttl=$(( _ttl_base + RANDOM % _ttl_span ))
        else
            (( ttl-- ))
        fi

        if (( x < tx )) ; then x=$(( x + 1 ))
        elif (( x > tx )) ; then x=$(( x - 1 )) ; fi
        if (( y < ty )) ; then y=$(( y + 1 ))
        elif (( y > ty )) ; then y=$(( y - 1 )) ; fi

        (( x < _xmin )) && x=$_xmin
        (( x > _xmax )) && x=$_xmax
        (( y < _ymin )) && y=$_ymin
        (( y > _ymax )) && y=$_ymax

        _bs["{x}$X"]=$x ; _bs["{y}$X"]=$y
        _bs["{tx}$X"]=$tx ; _bs["{ty}$X"]=$ty ; _bs["{ttl}$X"]=$ttl
    else
        _bs["{cd}$X"]=$_cd
    fi
    unset -n _bs
}
