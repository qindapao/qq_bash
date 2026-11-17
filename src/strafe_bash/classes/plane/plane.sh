# classes/plane/plane.sh — Plane（玩家飞机）
[[ -n "${_STRAFE_PLANE_SH:-}" ]] && return 0
_STRAFE_PLANE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_helpers.sh"
. "$STRAFE_PROJ_DIR/classes/plane/mixin_blink.sh"
. "$STRAFE_PROJ_DIR/classes/plane/mixin_long_blink.sh"
. "$STRAFE_PROJ_DIR/classes/plane/mixin_ram.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/bullet.sh"

readonly PlaneStaticTemplate='
    PlaneObj ->
        {CLS} => Plane
        {SUP} => Entity
        {MIX} => M_Blink
        # 位置（判定的点就是 x,y 这一格）
        {x} => 0
        {y} => 0
        # 机体包围盒（拾取/撞击判定用）
        {w} => 3
        {h} => 2
        # 当前立绘 / 无护盾立绘 / 护盾立绘
        {art} => 
        {base_art} => 
        {shield_art} => 
        # 立绘左右余量：立绘比机体宽时，按它把 art 居中画
        {al} => 1
        {base_al} => 1
        {shield_al} => 3
        # 护盾包围盒（shield_top=-1 表示护盾顶在机身上方一行）
        {shield_w} => 7
        {shield_h} => 3
        {shield_top} => -1
        # 最大血量（各机型覆盖：20/30/15/40）
        {maxhp} => 20
        # 击杀得分倍率（百分比）：机型差异项
        {score_pct} => 100
        # 弹速加成 / 射速加成（cd 为负表示更快）
        {spd_delta} => 0
        {cd_delta} => 0
        # 1 = 激光不受 spd_delta 影响（保持能量武器手感）
        {laser_exempt} => 0
        # 预留的机型技能名（当前未使用）
        {skill} => 
        # 当前血量 / 累计得分
        {hp} => 20
        {score} => 0
        # 单字符符号（立绘走 art，仅调试用）
        {symbol} => ^
        # 当前武器对象句柄（指向下面 w1..w5 之一）
        {bullet} => 
        # 各档武器对象句柄：w1=默认弹，w2..w5=可掉落的四档
        {w1} => 
        {w2} => 
        {w3} => 
        {w4} => 
        {w5} => 
        # 炸弹库存（上限 5）
        {bombs} => 0
        # 各档武器剩余时间（tick）：归零就退回默认弹
        {t2} => 0
        {t3} => 0
        {t4} => 0
        {t5} => 0
        # 追踪导弹剩余时间
        {mt} => 0
        # 额外弹道数（0..4）：越多单次发射的子弹越多
        {lanes} => 0
        # lanes 为奇数时的左右偏好（0=左 1=右）
        {lanes_side} => 0
        # 弹道加成剩余时间
        {lt} => 0
        # 护盾状态（0/1）
        {shield} => 0
        # 护盾剩余时间
        {st} => 0
        # 受伤闪烁（无敌）剩余 tick
        {blink} => 0
        # 撞击能力冷却
        {ram_cd} => 0
        # 上一帧的立绘/余量/护盾状态：渲染擦除上一帧时用
        {prev_art} => 
        {prev_al} => 1
        {prev_shield} => 0
        # 对象级动态能力列表（当前玩家侧未使用，预留给掉落式能力）
        {OBJMIX} => 
        # 弹速百分比：被 Boss 减速时为 50，到期恢复 100
        {spd_pct} => 100
        # 减速剩余 tick（归零时把 spd_pct 恢复成 100）
        {slow} => 0
    '
Plane_born () {
    local -n self=$1
    local _base _shield
    case "${self["{CLS}$X"]}" in
        PlaneHornet) _base=$PLANE_ART_HORNET ; _shield=$PLANE_ART_SHIELD_HORNET ;;
        PlaneEagle)  _base=$PLANE_ART_EAGLE  ; _shield=$PLANE_ART_SHIELD_EAGLE  ;;
        PlaneIl2)    _base=$PLANE_ART_IL2    ; _shield=$PLANE_ART_SHIELD_IL2    ;;
        *)           _base=$PLANE_ART_BASE   ; _shield=$PLANE_ART_SHIELD       ;;
    esac
    self["{base_art}$X"]=$_base
    self["{shield_art}$X"]=$_shield
    self["{art}$X"]=$_base
    self["{x}$X"]=$(( SCREEN_W / 2 ))
    self["{y}$X"]=$(( SCREEN_H - 2 ))
    self["{al}$X"]=${self["{base_al}$X"]:-1}
    self["{shield}$X"]=0
    self["{st}$X"]=0
    self["{prev_art}$X"]=$_base
    self["{prev_al}$X"]=${self["{base_al}$X"]:-1}
    self["{prev_shield}$X"]=0
    self["{hp}$X"]=${self["{maxhp}$X"]:-20}
}
Plane_use_skill () {
    # 预留接口：具体机型以后覆盖这个方法。
    :
}
Plane_bury () {
    Entity_bury "$1"
    local -n self=$1
    local i wpn
    for i in 1 2 3 4 5 ; do
        wpn=${self["{w$i}$X"]}
        [[ -n "$wpn" && -n "${XO_OBJ_POOL[$wpn]+_}" ]] && xo_obj_bury "$wpn"
    done
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
    local _laser=${w["{laser}$X"]:-0}
    local su=${w["{u}$X"]:-.}
    local sul=${w["{ul}$X"]:-$su}
    local sur=${w["{ur}$X"]:-$su}
    local sl=${w["{l}$X"]:-$su}
    local sr=${w["{r}$X"]:-$su}

    local -i _sdelta=${self["{spd_delta}$X"]:-0}
    local -i _cddelta=${self["{cd_delta}$X"]:-0}
    local -i _lex=${self["{laser_exempt}$X"]:-0}
    (( _laser && _lex )) && _sdelta=0

    # 敌方减速：既降弹速（命中延迟），也压射速 —— 只降弹速的话 DPS 一点不变，
    # 玩家只会觉得"手感变钝"，不会觉得被削弱。
    local -i _spct=${self["{spd_pct}$X"]:-100}
    spd=$(( spd + _sdelta ))
    if (( _spct < 100 )) ; then
        spd=$(( spd * _spct / 100 ))
    fi
    (( spd < 1 )) && spd=1

    cd=$(( cd + _cddelta ))
    (( cd < 0 )) && cd=0
    if (( _spct < 100 )) ; then
        cd=$(( cd * BOSS_BUFF_SLOW_CD_PCT / 100 ))
        (( cd < 1 )) && cd=1
    fi
    G_FIRE_CD=$cd

    if (( ${#BULLETS[@]} >= PLAYER_BULLET_LIMIT )) ; then
        return 0
    fi

    local _fx=${self["{x}$X"]}
    local _fy=$(( ${self["{y}$X"]} - 1 ))
    local _lanes=${self["{lanes}$X"]:-0}
    local _side=${self["{lanes_side}$X"]:-0}
    local -i _up=$(( -spd )) _left=$(( -spd )) _right=$spd

    # 量子能量武器只有一道：不按 lanes 分裂成多颗子弹，而是把 lanes+1 作为威力（1..5）。
    # 符号统一用 |：T/F/P/Y 跟威力没有直观对应，玩家学不会。
    # 威力改用「颜色」表达（白→橙→绿→紫→红），相邻等级色相差别大，一眼能分清。
    if (( _laser )) ; then
        local -i _power=$(( _lanes + 1 ))
        (( _power > 5 )) && _power=5
        local _lclr=''
        case "$_power" in
            2) _lclr=$C_CYAN ;;
            3) _lclr=$C_GREEN ;;
            4) _lclr=$C_PURPLE ;;
            # 最高档红 + 加粗：不用蓝色——终端里蓝色偏暗，排在紫后面像降级
            5) _lclr="${C_BOLD}${C_RED}" ;;
        esac
        xo_obj_born Bullet "$_fx" "$_fy" '|' "$_power" 0 "$_up"
        local _nbid=$REPLY
        if [[ -n "$_lclr" ]] ; then
            local -n _nbref=$_nbid
            _nbref["{color}$X"]=$_lclr
        fi
        BULLETS+=("$_nbid")
        return 0
    fi

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
