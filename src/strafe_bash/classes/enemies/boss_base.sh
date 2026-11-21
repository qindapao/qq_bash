# classes/enemies/boss_base.sh — BossBase 抽象基类
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[boss_base]++ )) && return 0
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"


# 类变量和方法声明
declare -gA XO_CLASS_FLAT_OBJ_VARS XO_CLASS_METHODS
XO_CLASS_FLAT_OBJ_VARS[BossBaseObj]=1
XO_CLASS_METHODS[BossBase]='born'

# 所有 Boss 的公共字段和公共行为。
# 具体 Boss 只在自己的模板里覆盖 w/h/hp/art/pcut/death_style。
declare -gA BossBaseObj=(
    [{CLS}$X]='BossBase'
    [{SUP}$X]='Entity'
    [{MIX}$X]=''
    # 死亡横幅上显示的名字
    [name]='THE BOSS'
    # 位置与碰撞/擦除包围盒（w=宽 h=高，单位格）
    [x]='0'
    [y]='0'
    [w]='13'
    [h]='5'
    # 当前立绘；prev_art 是上一帧用过的立绘（换形态时整块重画用）
    [art]=''
    [prev_art]=''
    # 伤害阶段 0..3 各自的立绘，阶段推进时 art 取对应那张
    [art0]=''
    [art1]=''
    [art2]=''
    [art3]=''
    # 血量；maxhp 用于算阶段百分比与 UI
    [hp]='150'
    [maxhp]='150'
    # 击杀得分（游戏层会按当前分数倍率折算）
    [score]='5000'
    # 通用计时器：各 Boss 自己解释（开火/走位节拍等）
    [cd]='0'
    # 单字符符号：调试/极简渲染用，正式立绘走 art
    [symbol]='X'
    # 当前伤害阶段（0..3），只前进不后退
    [phase]='0'
    # 走位目标点与走过一格的计时器
    [tx]='0'
    [ty]='0'
    [ttl]='0'
    # 阶段边界（百分比）：>p1 阶段0，>p2 阶段1，>p3 阶段2，其余阶段3
    [pcut1]='70'
    [pcut2]='50'
    [pcut3]='20'
    # 死亡演出样式（0=普通，具体值由 _boss_on_death 解释）
    [death_style]='0'
    # 无敌剩余 tick：>0 时伤害归零、渲染成青色（阶段切换与 INV 增益共用）
    [inv_cd]='0'
    # 对象级动态能力：空格分隔的 Mixin 名列表（顺序即优先级），由 xo_obj_mixin_* 维护
    [{OBJMIX}$X]=''
    # 上一次发放增益时看到的阶段；-1 表示还没发过，所以出生那次也算一次发放
    [buff_phase]='-1'
    # HP 行尾显示的增益短标签（由 {OBJMIX} 映射而来，只在变化时重算）
    [buff_str]=''
    # INV 增益的周期计数：归零时开一次无敌窗口
    [bi_cd]='0'
    # MIS 增益的发射冷却：归零时打一枚跟踪导弹
    [ms_cd]='0'
    # HEAL 增益的观察窗口：窗口内本阶段血掉够一半就补回阶段上限，超时自卸
    [heal_cd]='0'
    # WAVE 增益的连发状态：剩余发数 / 下一发倒计时(tick) / 间隔(tick)
    [wv_left]='0'
    [wv_cd]='0'
    [wv_gap]='0'
)
BossBase_born () {
    local -n self=$1
    local -i _w=${self[w]:-13}
    local -i _bx=$(( (SCREEN_W - _w) / 2 ))
    self[x]=$_bx self[y]=$GAME_TOP self[cd]=0 \
    self[phase]=0 self[art]=${self[art0]} \
    self[tx]=$_bx self[ty]=$GAME_TOP self[ttl]=0 \
    self[inv_cd]=0
    # 动态增益：-1 表示还没发过，所以第一次 tick 会把 phase 0 也算作一次发放
    self[buff_phase]=-1 self[buff_str]='' \
    self[bi_cd]=$BOSS_BUFF_INV_GAP
}

# 具体 Boss 在 born 时把四段 art 写进自己的类字段。
_boss_set_arts () {
    local -n _ba=$1
    _ba[art0]=$2 \
    _ba[art1]=$3 \
    _ba[art2]=$4 \
    _ba[art3]=$5
}

# 按 hp 百分比刷新阶段，阶段 art 从 {art0..3} 读取。
# 具体 Boss 只改 {pcut1..3} 即可，不再在 move 里写死 art 变量。
_boss_update_phase () {
    local -n _bs=$1
    local -i _hp=${_bs[hp]:-0} \
             _maxhp=${_bs[maxhp]:-0}
    (( _maxhp > 0 )) || _maxhp=1
    local -i _pct=$(( _hp * 100 / _maxhp )) \
             _p1=${_bs[pcut1]:-70} \
             _p2=${_bs[pcut2]:-50} \
             _p3=${_bs[pcut3]:-20} \
             _ic=${_bs[inv_cd]:-0}
    if (( _ic > 0 )) ; then
        _bs[inv_cd]=$(( _ic - 1 ))
    fi
    local -i _newphase
    if (( _pct > _p1 )) ; then _newphase=0
    elif (( _pct > _p2 )) ; then _newphase=1
    elif (( _pct > _p3 )) ; then _newphase=2
    else _newphase=3
    fi
    # 阶段只前进、不后退：阶段代表「伤害进度」，回血不能把 Boss 打回上一个形态。
    # 否则 art 会倒退，且阶段切换的无敌窗口与动态增益发放都会被重复触发。
    if (( _newphase > ${_bs[phase]:-0} )) ; then
        _bs[phase]=$_newphase \
        _bs[art]=${_bs["art$_newphase"]} \
        _bs[ttl]=0 \
        _bs[inv_cd]=$BOSS_INV_TICKS
    fi
}

# 公共目标点移动。
# $1=obj $2=移动间隔 $3=纵向目标上限 $4=中途变向概率
# $5=ttl 基数 $6=ttl 随机范围
# $7=y 底部留白（默认 4，旋刃可传 3 换更大活动范围）
# $8=边缘巡逻模式（默认 0；旋刃传 1，目标点打屏幕边缘）
# $9=俯冲概率（默认 0）：每次选目标点时，有这个百分比的机会把目标压到最下面，
#    用来在"大部分时间待在上半屏"之外保留"突然冲下来打你"的压迫感
_boss_move_target () {
    local -i _step=$2 _yhi=$3 _jitter=$4 _ttl_base=$5 _ttl_span=$6 \
             _ymargin=${7:-4} _wide=${8:-0} _dive=${9:-0}
    local -n _bs=$1

    local -i _w=${_bs[w]:-1} _h=${_bs[h]:-1}
    local -i _xmin=2 _xmax=$(( SCREEN_W - 2 - _w ))
    # y 上限留出 HP 条那一行，避免 Boss 的 [K 清行擦掉玩家
    local -i _ymin=$GAME_TOP _ymax=$(( SCREEN_H - _ymargin - _h ))
    (( _xmax < _xmin )) && _xmax=$_xmin
    (( _ymax < _ymin )) && _ymax=$_ymin
    (( _yhi > _ymax )) && _yhi=$_ymax
    (( _yhi < _ymin )) && _yhi=$_ymin

    local -i _cd=$(( ${_bs[cd]:-0} + 1 ))
    if (( _cd >= _step )) ; then
        _bs[cd]=0

        local -i x=${_bs[x]:-0} y=${_bs[y]:-0}
        local -i tx=${_bs[tx]:-0} ty=${_bs[ty]:-0} ttl=${_bs[ttl]:-0}

        (( x < _xmin )) && x=$_xmin
        (( x > _xmax )) && x=$_xmax
        (( y < _ymin )) && y=$_ymin
        (( y > _ymax )) && y=$_ymax

        if (( ttl <= 0 || (x == tx && y == ty) )) || (( RANDOM % 100 < _jitter )) ; then
            if (( _wide )) ; then
                # 旋刃/骷髅王：主要打左右对面边缘，偶尔打上下边缘。
                # 纵向默认压在上半屏，按 _dive 概率偶尔俯冲到底部。
                local -i _xmid=$(( (_xmin + _xmax) / 2 ))
                if (( RANDOM % 5 == 0 )) ; then
                    if (( RANDOM % 2 )) ; then ty=$_ymin ; else ty=$_yhi ; fi
                    tx=$(( RANDOM % (_xmax - _xmin + 1) + _xmin ))
                else
                    if (( x < _xmid )) ; then tx=$_xmax ; else tx=$_xmin ; fi
                    if (( _dive > 0 && RANDOM % 100 < _dive )) ; then
                        # 俯冲：目标压到底部 3 行内，保证真的冲下来
                        ty=$(( _ymax - RANDOM % 3 ))
                        (( ty < _yhi )) && ty=$_yhi
                    else
                        ty=$(( RANDOM % (_yhi - _ymin + 1) + _ymin ))
                    fi
                fi
            else
                tx=$(( RANDOM % (_xmax - _xmin + 1) + _xmin ))
                if (( _dive > 0 && RANDOM % 100 < _dive )) ; then
                    # 俯冲：目标压到底部 3 行内，保证真的冲下来
                    ty=$(( _ymax - RANDOM % 3 ))
                    (( ty < _yhi )) && ty=$_yhi
                else
                    ty=$(( RANDOM % (_yhi - _ymin + 1) + _ymin ))
                fi
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

        _bs[x]=$x ; _bs[y]=$y \
        _bs[tx]=$tx ; _bs[ty]=$ty ; _bs[ttl]=$ttl
    else
        _bs[cd]=$_cd
    fi
}
