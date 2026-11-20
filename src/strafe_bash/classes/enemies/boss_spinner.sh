# classes/enemies/boss_spinner.sh — BossSpinner（旋刃，继承 BossBase）
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[boss_spinner]++ )) && return 0
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_base.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/soa_bullets.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_pattern.sh"

# 旋刃四阶段 art（来自任务二设计稿）。
readonly BOSS_SPINNER_ART_0=$'   o  >-----<  o\n    \\/  .-.  \\/\n    |  ( O )  |\n    /\\  \'-\'  /\\\n   o  >-----<  o'
readonly BOSS_SPINNER_ART_1=$'   o  >-----<\n    \\/  .-.  \\\n    |  ( O )  |\n     \\  \'-\'  /\\\n      >-----<  o'
readonly BOSS_SPINNER_ART_2=$'      >-----<\n     /  .-.  \\\n    |  ( O )  |\n     \\  \'-\'  /\n      >-----<'
readonly BOSS_SPINNER_ART_3=$'      .-----.\n     /  .-.  \\\n    |  ( X )  |\n     \\  \'-\'  /\n      \'-----\''

declare -gA BossSpinnerObj=(
    [{CLS}$X]='BossSpinner'
    [{SUP}$X]='BossBase'
    [{MIX}$X]=''
    # 死亡横幅上的名字
    [name]='THE SPINNER'
    # 包围盒（16x5，比经典 Boss 更宽）
    [w]='16'
    [h]='5'
    # 血量：最耐打的一档（300）
    [hp]='300'
    [maxhp]='300'
    # 击杀得分基数
    [score]='8000'
    # 单字符符号（立绘走 art，仅调试用）
    [symbol]='S'
    # 阶段边界百分比
    [pcut1]='75'
    [pcut2]='50'
    [pcut3]='25'
    # 死亡演出样式（1 = 旋刃专用演出）
    [death_style]='1'
    # 旋转环发射冷却：归零时打一圈 8 方向弹
    [ring_cd]='0'
    # 瞄准射击冷却：归零时朝玩家打一发
    [aim_cd]='0'
    # 走位模式计时器/步号/模式号：控制弹幕节奏的循环
    [pat_cd]='0'
    [pat_step]='-1'
    [pat_mode]='0'
    # 旋转相位：每轮 +1，决定 8 方向缺口转到哪
    [spin]='0'
)
BossSpinner_born () {
    _boss_set_arts "$1" "$BOSS_SPINNER_ART_0" "$BOSS_SPINNER_ART_1" "$BOSS_SPINNER_ART_2" "$BOSS_SPINNER_ART_3"
    BossBase_born "$1"
    local -n _self=$1
    _self[ring_cd]=18 \
    _self[aim_cd]=36 \
    _self[pat_cd]=90 \
    _self[pat_step]=-1 \
    _self[pat_mode]=0 \
    _self[spin]=0
}

# 旋转环：8 方向留 2 个对向缺口，每轮转 45°。
_boss_spinner_ring () {
    local -n _bs=$1
    local -i _cx=$(( ${_bs[x]} + ${_bs[w]} / 2 )) \
             _cy=$(( ${_bs[y]} + ${_bs[h]} / 2 )) \
             _spin=${_bs[spin]:-0}
    if (( EB_LIVE + 6 > BOSS_BULLET_LIMIT )) ; then
        return 0
    fi
    local -a _dx=(0 1 1 1 0 -1 -1 -1) \
             _dy=(-1 -1 0 1 1 1 0 -1)
    local -i _i _s1=$_spin _s2=$(( (_spin + 4) % 8 ))
    for ((_i=0; _i<8; _i++)) ; do
        (( _i == _s1 || _i == _s2 )) && continue
        enemy_bullet_spawn BossBullet "$_cx" "$_cy" "${_dx[_i]}" "${_dy[_i]}" 'o' 3 2 "$C_CYAN"
    done
    _bs[spin]=$(( (_spin + 1) % 8 ))
}

# 瞄准散弹：朝玩家所在八分方向打 3 发，左右各偏一格。
_boss_spinner_aim () {
    local -n _bs=$1
    local -i _cx=$(( ${_bs[x]} + ${_bs[w]} / 2 )) \
             _cy=$(( ${_bs[y]} + ${_bs[h]} / 2 ))

    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] || return 0
    local -i _px=${OBJ_player[x]} _py=${OBJ_player[y]}
    local -i _dx=$(( _px - _cx )) _dy=$(( _py - _cy )) _bi
    if (( _dx == 0 && _dy == 0 )) ; then
        _bi=4
    elif (( _dy < 0 )) ; then
        if (( _dx < 0 )) ; then _bi=7 ; elif (( _dx > 0 )) ; then _bi=1 ; else _bi=0 ; fi
    elif (( _dy > 0 )) ; then
        if (( _dx < 0 )) ; then _bi=5 ; elif (( _dx > 0 )) ; then _bi=3 ; else _bi=4 ; fi
    else
        if (( _dx < 0 )) ; then _bi=6 ; else _bi=2 ; fi
    fi
    if (( EB_LIVE + 3 > BOSS_BULLET_LIMIT )) ; then
        return 0
    fi
    local -a _dxs=(0 1 1 1 0 -1 -1 -1)
    local -a _dys=(-1 -1 0 1 1 1 0 -1)
    local -i _o _i
    for _o in -1 0 1 ; do
        _i=$(( (_bi + _o + 8) % 8 ))
        enemy_bullet_spawn BossBullet "$_cx" "$_cy" "${_dxs[_i]}" "${_dys[_i]}" 'x' 3 2 "$C_ORANGE"
    done
}

BossSpinner_move () {
    _boss_update_phase "$1"
    local -n self=$1

    # 3 tick 一格、1% 中途变向、左右边缘巡逻；
    # 纵向目标压在上半屏（好打），留 12% 的俯冲机会冲到底部。
    local -i _ymin=$GAME_TOP \
             _ymax=$(( SCREEN_H - 3 - ${self[h]} )) \
             _yhi=$(( _ymin + (_ymax - _ymin) / 2 ))
    _boss_move_target "$1" 3 "$_yhi" 1 80 21 3 1 12

    local -i _phase=${self[phase]}
    local -i _ring_every=26 _aim_every=40
    (( _phase == 3 )) && { _ring_every=20 ; _aim_every=30 ; }

    local -i _rc=$(( ${self[ring_cd]:-0} - 1 ))
    if (( _rc <= 0 )) ; then
        self[ring_cd]=$_ring_every
        _boss_spinner_ring "$1"
    else
        self[ring_cd]=$_rc
    fi
    local -i _ac=$(( ${self[aim_cd]:-0} - 1 ))
    if (( _ac <= 0 )) ; then
        self[aim_cd]=$_aim_every
        _boss_spinner_aim "$1"
    else
        self[aim_cd]=$_ac
    fi

    local -i _ps=${self[pat_step]:--1}
    if (( _ps >= 0 )) ; then
        _boss_pattern_spawn_step "$1" "$_ps" "${self[pat_mode]:-0}" 4
        ((_ps++))
        if (( _ps >= ${#BOSS_AIM_PATTERN_STEPS[@]} )) ; then
            self[pat_step]=-1 \
            self[pat_cd]=180
        else
            self[pat_step]=$_ps
        fi
    else
        local -i _pc=$(( ${self[pat_cd]:-0} - 1 ))
        if (( _pc <= 0 )) ; then
            _boss_pattern_mode "$1"
            self[pat_mode]=$REPLY
            _boss_pattern_spawn_step "$1" 0 "$REPLY" 4
            self[pat_step]=1 \
            self[pat_cd]=180
        else
            self[pat_cd]=$_pc
        fi
    fi
    return 0
}
