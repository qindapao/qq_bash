#!/usr/bin/env bash
#
# Boss 动态增益（P1 + P2 前两个能力）的测试。
#
# 分组：
#   A. 发放规则（4 个假能力，把「4 次发放 / 上限 2 / 随机替换 / 不重复」跑满）
#   B. 单个真实能力的效果（周期无敌 4+6 秒、回血 1/2）
#   C. 两个能力同时持有：钩子必须「每个都跑一次」（xo_obj_call_all 的用途）
#   D. 增益标签真的画到 Boss HP 行上
#   E. 能力自述「现在值不值得拿」（满血不该拿回血）+ 一次性能力自卸腾槽位
#   F. 无敌占空比 4 秒无敌 / 6 秒可受伤（回归：曾经写成永久无敌）
#   G. 回血不得让阶段回退（回归）
#   H. 敌跟踪导弹：立即发射、伤害/配色/燃料/速度、渲染、燃料耗尽自毁并登记擦除格
#   I. 30 秒减速：玩家子弹变慢，到期恢复

STRAFE_PROJ_DIR=$(cd ../../src/strafe_bash && pwd -P)
STRAFE_LIB_HOME=$(cd ../../src/bashlib && pwd -P)
export STRAFE_PROJ_DIR STRAFE_LIB_HOME

. ../libs/test_utils.sh
. "$STRAFE_PROJ_DIR/game/main.sh" >/dev/null 2>&1

CHECKS=0
FAILS=0

check ()        # $1=标签 $2=期望 $3=实际
{
    CHECKS=$((CHECKS+1))
    if [[ "$2" == "$3" ]] ; then
        printf '  [ok]   %-46s %s\033[0m\n' "$1" "$3"
    else
        printf '  [FAIL] %-46s 期望=[%s] 实际=[%s]\033[0m\n' "$1" "$2" "$3"
        FAILS=$((FAILS+1))
    fi
}

# 假能力：只提供 _init 钩子，用来验证发放规则
M_Ta__init () { : ; }
M_Tb__init () { : ; }
M_Tc__init () { : ; }
M_Td__init () { : ; }

xo_init

# 读某对象的增益相关字段
buf_read ()
{
    local -n _l=$1
    BUF_LIST=${_l["{OBJMIX}$X"]}
    BUF_PHASE=${_l[buff_phase]}
    BUF_STR=${_l[buff_str]}
    BUF_HP=${_l[hp]}
    BUF_INV=${_l[inv_cd]}
    BUF_BI=${_l[bi_cd]}
    BUF_PH=${_l[phase]}
    BUF_MS=${_l[ms_cd]}
}

# 读任意对象的任意字段（$1=对象 $2=字段名，不带花括号）
field ()
{
    local -n _f=$1
    printf '%s' "${_f[$2]}"
    unset -n _f
}

# 模拟 _boss_update_phase 里对 {inv_cd} 的递减（测试里不跑 Boss_move，需手动还原这一步）
inv_dec ()
{
    local -n _d=$1
    if (( ${_d[inv_cd]:-0} > 0 )) ; then
        _d[inv_cd]=$(( ${_d[inv_cd]} - 1 ))
    fi
    unset -n _d
}

# hp_to <对象> <值>
hp_to ()
{
    local -n _h=$1
    _h[hp]=$2
    unset -n _h
}

test_case1 ()
{
    printf '\n== A. 发放规则（假能力池）==\n'

    local -n _C=BossObj
    local has_node=0
    [[ -n "${_C[{OBJMIX}$X]+_}" ]] && has_node=1
    unset -n _C
    check 'BossBase 模板声明了 {OBJMIX}' 1 "$has_node"

    BOSS_BUFF_POOL=(M_Ta M_Tb M_Tc M_Td)

    xo_obj_born_named OBJ_bb Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }

    local -a prev_a=()
    local ph x y
    for ph in 0 1 2 3 ; do
        local -n _bb=OBJ_bb
        _bb[phase]=$ph
        unset -n _bb

        _boss_buff_tick OBJ_bb
        buf_read OBJ_bb

        local -a cur_a=($BUF_LIST)
        local -i want=$(( ph + 1 ))
        (( want > BOSS_BUFF_MAX )) && want=$BOSS_BUFF_MAX

        check "phase=$ph 槽位数（上限 $BOSS_BUFF_MAX）" "$want" "${#cur_a[@]}"

        local -A seen=()
        local -i dup=0
        for x in "${cur_a[@]}" ; do
            [[ -n "${seen[$x]+_}" ]] && dup=1
            seen[$x]=1
        done
        check "phase=$ph 无重复能力" 0 "$dup"

        check "phase=$ph buff_phase 已记录" "$ph" "$BUF_PHASE"

        local -i str_ok=0
        [[ -n "$BUF_STR" ]] && str_ok=1
        check "phase=$ph buff_str 非空" 1 "$str_ok"

        if (( ph >= 2 )) ; then
            local -i inter=0
            for x in "${cur_a[@]}" ; do
                for y in "${prev_a[@]}" ; do
                    [[ "$x" == "$y" ]] && (( inter++ ))
                done
            done
            check "phase=$ph 替换时恰好保留 1 个旧能力" 1 "$inter"
        fi

        prev_a=("${cur_a[@]}")
    done

    printf '\n== B. 单个真实能力 ==\n'

    # B1 周期无敌：获得后先等 6 秒，冷却走完触发 4 秒无敌
    # 注意：{bi_cd} 的初值由 add 触发的 M_BuffInvuln_init 写入，不要再手工置零
    # （那样会覆盖掉 init，测的就不是真实流程了）。
    xo_obj_born_named OBJ_rb Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    local -n _r0=OBJ_rb
    _r0[inv_cd]=0
    unset -n _r0

    xo_obj_mixin_add OBJ_rb M_BuffInvuln || { log_test 0 1 ; return 1 ; }
    buf_read OBJ_rb
    check '无敌：获得后先进入可受伤间隔' "$BOSS_BUFF_INV_OFF" "$BUF_BI"

    local i
    for (( i=0 ; i<BOSS_BUFF_INV_OFF ; i++ )) ; do
        xo_obj_call_all OBJ_rb buff_tick
    done
    buf_read OBJ_rb
    check '无敌：间隔没走完不触发' 0 "$BUF_INV"
    xo_obj_call_all OBJ_rb buff_tick
    buf_read OBJ_rb
    check '无敌：间隔走完触发 4 秒无敌' "$BOSS_BUFF_INV_ON" "$BUF_INV"

    # B2 回血：拿到时不立刻加（那时贴着本阶段上限），等本阶段血被打掉一半再补回来
    xo_obj_born_named OBJ_rb2 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    hp_to OBJ_rb2 80          # phase 0，上限 180，下界 0 → 需要打掉 90 才算"一半"
    xo_obj_mixin_add OBJ_rb2 M_BuffHeal || { log_test 0 1 ; return 1 ; }
    HIT_FX=()
    buf_read OBJ_rb2
    check '回血：获得时不立刻加（避免只加 1 点）' 80 "$BUF_HP"
    check '回血：获得后挂上观察窗口' "$BOSS_BUFF_HEAL_WAIT" "$(field OBJ_rb2 heal_cd)"
    xo_obj_call_all OBJ_rb2 buff_tick
    buf_read OBJ_rb2
    check '回血：本阶段血掉够一半 → 补回上限' 180 "$BUF_HP"
    check '回血：补完即自卸' '' "$BUF_LIST"
    check '回血：产生了 HIT_FX 动画' 1 "$(( ${#HIT_FX[@]} > 0 ))"
    check '回血：动画 TTL 大于普通火花' 1 \
        "$(( ${HIT_FX[4]:-0} > 3 ? 1 : 0 ))"

    # 窗口内一直没等到机会 → 自己卸载，把槽位还回去
    xo_obj_born_named OBJ_rb9 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    hp_to OBJ_rb9 179         # 只差 1 点，永远到不了"一半"
    xo_obj_mixin_add OBJ_rb9 M_BuffHeal || { log_test 0 1 ; return 1 ; }
    local -i wt
    for (( wt=0 ; wt<BOSS_BUFF_HEAL_WAIT + 1 ; wt++ )) ; do
        xo_obj_call_all OBJ_rb9 buff_tick
    done
    buf_read OBJ_rb9
    check '回血：窗口到期仍未触发则自卸' '' "$BUF_LIST"
    check '回血：到期卸载时血量不变' 179 "$BUF_HP"

    # 回归：阶段刚切换那一刻，血量常比"本阶段上限"高一点（整数截断），
    # 这时回血必须仍然能被挂上，否则玩家一辈子见不到它。
    xo_obj_born_named OBJ_rb10 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    local -n _r10=OBJ_rb10
    _r10[hp]=127
    _r10[phase]=1
    unset -n _r10
    local okrc=0
    _boss_buff_ok OBJ_rb10 M_BuffHeal || okrc=$?
    check '阶段刚切换（血量略高于上限）时回血仍可被选中' 0 "$okrc"

    xo_obj_mixin_add OBJ_rb10 M_BuffHeal || { log_test 0 1 ; return 1 ; }
    xo_obj_call_all OBJ_rb10 buff_tick
    buf_read OBJ_rb10
    check '刚切换时不回血（此时没空间）' 127 "$BUF_HP"
    hp_to OBJ_rb10 108
    xo_obj_call_all OBJ_rb10 buff_tick
    buf_read OBJ_rb10
    check '打掉本阶段一半后补回上限' 126 "$BUF_HP"

    printf '\n== C. 两个能力同时持有（钩子必须都跑）==\n'
    xo_obj_born_named OBJ_rb3 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    hp_to OBJ_rb3 80          # 阶段 0 要打掉一半（90）才会触发回血
    local -n _c=OBJ_rb3
    _c[bi_cd]=0
    _c[inv_cd]=0
    unset -n _c
    xo_obj_mixin_add OBJ_rb3 M_BuffInvuln || { log_test 0 1 ; return 1 ; }
    xo_obj_mixin_add OBJ_rb3 M_BuffHeal   || { log_test 0 1 ; return 1 ; }

    buf_read OBJ_rb3
    check '同时持有：无敌计时器也生效' "$BOSS_BUFF_INV_OFF" "$BUF_BI"
    xo_obj_call_all OBJ_rb3 buff_tick
    buf_read OBJ_rb3
    check '同时持有：回血生效' 180 "$BUF_HP"

    printf '\n== D. 增益标签真的画到 Boss HP 行上 ==\n'
    if [[ -z "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        xo_obj_born_named OBJ_player PlaneBee >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    fi
    _boss_buff_sync_str OBJ_rb3
    ENEMIES=(OBJ_rb3)
    FRAME_BUF=''
    render
    local shown=0
    [[ "$FRAME_BUF" == *'INV'* ]] && shown=1
    check 'HP 行输出里含增益标签' 1 "$shown"
    ENEMIES=()
    FRAME_BUF=''

    printf '\n== E. 能力自述"现在值不值得拿" ==\n'
    BOSS_BUFF_POOL=(M_BuffHeal)
    xo_obj_born_named OBJ_ok1 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    _boss_buff_gain OBJ_ok1
    buf_read OBJ_ok1
    local -a e1=($BUF_LIST)
    check '满血：回血不进候选（槽位仍空）' 0 "${#e1[@]}"

    hp_to OBJ_ok1 80          # 阶段 0 要打掉一半（90）才会触发回血
    _boss_buff_gain OBJ_ok1
    buf_read OBJ_ok1
    check '掉血后：回血进入槽位' 'M_BuffHeal' "$BUF_LIST"
    xo_obj_call_all OBJ_ok1 buff_tick
    buf_read OBJ_ok1
    check '掉血后：补回本阶段上限（180）' 180 "$BUF_HP"
    check '掉血后：回血用完即自卸、槽位为空' '' "$BUF_LIST"

    hp_to OBJ_ok1 80
    _boss_buff_gain OBJ_ok1
    xo_obj_call_all OBJ_ok1 buff_tick
    buf_read OBJ_ok1
    check '槽位腾出后可再次抽到回血' 180 "$BUF_HP"

    BOSS_BUFF_POOL=(M_BuffHeal M_BuffInvuln)
    xo_obj_born_named OBJ_ok2 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    _boss_buff_gain OBJ_ok2
    buf_read OBJ_ok2
    check '满血开局：只会拿到无敌' 'M_BuffInvuln' "$BUF_LIST"

    printf '\n== F. 无敌占空比（4 秒无敌 + 6 秒可受伤）==\n'
    xo_obj_born_named OBJ_rb4 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_mixin_add OBJ_rb4 M_BuffInvuln || { log_test 0 1 ; return 1 ; }

    local -i t on=0
    for (( t=0 ; t<BOSS_BUFF_INV_OFF ; t++ )) ; do
        inv_dec OBJ_rb4
        xo_obj_call_all OBJ_rb4 buff_tick
        buf_read OBJ_rb4
        (( BUF_INV > 0 )) && (( on++ ))
    done
    check '获得后先有可受伤窗口（无敌 tick=0）' 0 "$on"

    on=0
    local -i period=$(( BOSS_BUFF_INV_ON + BOSS_BUFF_INV_OFF ))
    for (( t=0 ; t<period ; t++ )) ; do
        inv_dec OBJ_rb4
        xo_obj_call_all OBJ_rb4 buff_tick
        buf_read OBJ_rb4
        (( BUF_INV > 0 )) && (( on++ ))
    done
    check '一个周期里无敌时长 = 4 秒' "$BOSS_BUFF_INV_ON" "$on"

    # 阶段切换给的无敌窗口不应该被"再叠一层"
    local -n _ov=OBJ_rb4
    _ov[inv_cd]=100      # 假设此刻正处在阶段切换给的无敌里
    _ov[bi_cd]=0
    unset -n _ov
    xo_obj_call_all OBJ_rb4 buff_tick
    buf_read OBJ_rb4
    check '已无敌时不叠加（保持原窗口）' 100 "$BUF_INV"
    check '跳过这一次但冷却照常重新开始' "$(( BOSS_BUFF_INV_ON + BOSS_BUFF_INV_OFF ))" "$BUF_BI"

    printf '\n== G. 回血不得让阶段回退 ==\n'
    xo_obj_born_named OBJ_rb5 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    hp_to OBJ_rb5 108        # 60% → 应当进入 phase 1
    xo_call OBJ_rb5 move >/dev/null 2>&1
    buf_read OBJ_rb5
    check '掉血到 60% 后进入 phase 1' 1 "$BUF_PH"

    xo_obj_mixin_add OBJ_rb5 M_BuffHeal || { log_test 0 1 ; return 1 ; }
    xo_obj_call_all OBJ_rb5 buff_tick
    buf_read OBJ_rb5
    check '回血封顶在本阶段上限（70% = 126）' 126 "$BUF_HP"

    # phase 3 的上限是 20%（36）：打到本阶段一半（<=18）才补
    xo_obj_born_named OBJ_rb8 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    hp_to OBJ_rb8 15
    local -n _g3=OBJ_rb8
    _g3[phase]=3
    unset -n _g3
    xo_obj_mixin_add OBJ_rb8 M_BuffHeal || { log_test 0 1 ; return 1 ; }
    xo_obj_call_all OBJ_rb8 buff_tick
    buf_read OBJ_rb8
    check 'phase 3 回血封顶在 20%（36）' 36 "$BUF_HP"

    local -n _g2=OBJ_rb5
    _g2[inv_cd]=10
    unset -n _g2
    xo_call OBJ_rb5 move >/dev/null 2>&1
    buf_read OBJ_rb5
    check '回血后阶段不回退' 1 "$BUF_PH"
    check '阶段无敌窗口未被重复触发' 9 "$BUF_INV"

    printf '\n== H. 敌跟踪导弹（SoA 槽位）==\n'
    eb_reset
    xo_obj_born_named OBJ_rb6 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_mixin_add OBJ_rb6 M_BuffMissile || { log_test 0 1 ; return 1 ; }
    buf_read OBJ_rb6
    check '获得后立即可发射（冷却为 0）' 0 "$BUF_MS"
    xo_obj_call_all OBJ_rb6 buff_tick
    check '获得后下一 tick 立刻发射 1 枚' 1 "$EB_LIVE"
    xo_obj_call_all OBJ_rb6 buff_tick
    buf_read OBJ_rb6
    check '发射后进入下一轮冷却' "$(( BOSS_BUFF_MISSILE_CD - 1 ))" "$BUF_MS"

    local -i m0=-1 _si
    for (( _si=0 ; _si<EB_N ; _si++ )) ; do
        (( EB_ALIVE[_si] )) && { m0=$_si ; break ; }
    done
    eb_field "$m0" damage ; check '导弹伤害为 1' 1 "$REPLY"
    local -i _cok=0 _sok=0
    [[ "${EB_GLYPH[m0]}" == *"${C_BOLD}${C_RED}"* ]] && _cok=1
    [[ "${EB_GLYPH[m0]}" == *"$BOSS_BUFF_MISSILE_SYM"* ]] && _sok=1
    check '导弹用加粗亮红（敌方配色）' 1 "$_cok"
    check '导弹用单宽实心大圆点' 1 "$_sok"
    eb_field "$m0" fuel ; check '导弹初始燃料' "$BOSS_BUFF_MISSILE_FUEL" "$REPLY"
    eb_field "$m0" step ; check '导弹比玩家慢（每 step tick 走 1 格）' "$BOSS_BUFF_MISSILE_STEP" "$REPLY"

    # 渲染：位置 + 配色 + 符号
    local -i mx=${EB_X[m0]} my=${EB_Y[m0]}
    FRAME_BUF=''
    render
    local needle=""$ESC"[$my;${mx}H${EB_GLYPH[m0]}" _seen=0
    [[ "$FRAME_BUF" == *"$needle"* ]] && _seen=1
    check '导弹真的被画到屏幕上' 1 "$_seen"

    # 移动：走满一个 step 朝玩家方向前进 1 格（玩家在导弹下方）
    OBJ_player[x]=$mx
    OBJ_player[y]=$(( my + 8 ))
    G_INV=900
    local -i k y_before=$my
    for (( k=0 ; k<BOSS_BUFF_MISSILE_STEP ; k++ )) ; do
        ENEMIES=() ; BULLETS=() ; DROPS=() ; WORDS=()
        _play_game_tick >/dev/null 2>&1
    done
    check '走满一个 step 后向玩家方向前进 1 格' 1 \
        "$(( EB_Y[m0] == y_before + 1 ? 1 : 0 ))"

    # 燃料烧完自毁
    EB_FUEL[m0]=1
    for (( k=0 ; k<BOSS_BUFF_MISSILE_STEP ; k++ )) ; do
        ENEMIES=() ; BULLETS=() ; DROPS=() ; WORDS=()
        _play_game_tick >/dev/null 2>&1
    done
    check '燃料烧完后自毁' 0 "${EB_ALIVE[m0]}"

    # 死亡出口：槽位死亡时必须把格子从帧缓冲擦掉
    eb_reset
    enemy_bullet_spawn EnemyMissile 40 10 "$BOSS_BUFF_MISSILE_FUEL" 99 >/dev/null 2>&1
    m0=0
    FB_DIRTY=()
    eb_kill "$m0"
    local -i _mi=$(( (10 - 1) * FB_W + (40 - 1) )) _ok=0
    if (( ${#FB_DIRTY[@]} >= 1 )) && [[ -z "${FB_CELL[_mi]}" ]] ; then _ok=1 ; fi
    check '死亡出口擦掉了当前格（避免残影）' 1 "$_ok"

    # 我方子弹一碰即毁：跑一次真实 tick
    eb_reset ; BULLETS=() ; ENEMIES=()
    enemy_bullet_spawn EnemyMissile 40 10 "$BOSS_BUFF_MISSILE_FUEL" 99 >/dev/null 2>&1
    m0=0
    xo_obj_born Bullet 40 12 '|' 1 0 -2 >/dev/null 2>&1
    local bhit=$REPLY
    BULLETS=("$bhit")
    _play_game_tick >/dev/null 2>&1
    local -i m_gone=${EB_ALIVE[m0]:-1} b_gone=1
    [[ -n "${XO_OBJ_POOL[$bhit]+_}" ]] && b_gone=0
    check '我方子弹能把跟踪导弹打掉' 0 "$m_gone"
    check '打掉时那颗子弹也一起消失' 1 "$b_gone"
    eb_reset ; BULLETS=()

    printf '\n== I. 30 秒减速 ==\n'
    if [[ -z "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        xo_obj_born_named OBJ_player PlaneBee >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    fi
    init_game >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_born_named OBJ_rb7 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }

    BULLETS=()
    OBJ_player[spd_pct]=100
    xo_call OBJ_player fire
    local -i v_normal=${BULLETS[0]:+$(field "${BULLETS[0]}" vy)}
    (( v_normal < 0 )) && v_normal=$(( -v_normal ))

    # 能力在 add 的瞬间生效（M_BuffSlow_init 里挂到玩家身上）
    xo_obj_mixin_add OBJ_rb7 M_BuffSlow || { log_test 0 1 ; return 1 ; }
    check '玩家子弹速度降到 50%' "$BOSS_BUFF_SLOW_PCT" "$(field OBJ_player spd_pct)"
    check '减速计时器 = 30 秒' "$BONUS_SLOW" "$(field OBJ_player slow)"

    BULLETS=()
    xo_call OBJ_player fire
    local -i v_slow=${BULLETS[0]:+$(field "${BULLETS[0]}" vy)}
    (( v_slow < 0 )) && v_slow=$(( -v_slow ))
    check '减速后发射的子弹确实更慢' 1 "$(( v_slow < v_normal ? 1 : 0 ))"

    # 光降弹速不会减少输出：射速也必须被压
    BULLETS=()
    OBJ_player[spd_pct]=100
    xo_call OBJ_player fire
    local -i cd_normal=$G_FIRE_CD
    BULLETS=()
    OBJ_player[spd_pct]=50
    xo_call OBJ_player fire
    local -i cd_slow=$G_FIRE_CD
    check '减速同时压射速（cd ×1.5）' \
        "$(( cd_normal * BOSS_BUFF_SLOW_CD_PCT / 100 ))" "$cd_slow"

    local -n _pl=OBJ_player
    _pl[slow]=0
    _pl[spd_pct]=100
    unset -n _pl
    check '到期后速度恢复' 100 "$(field OBJ_player spd_pct)"

    printf '\n== J. 量子能量武器 ==\n'
    OBJ_player[spd_pct]=100
    xo_obj_born_named OBJ_laser BulletTypeLaser >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    OBJ_player[bullet]=OBJ_laser
    OBJ_player[lanes]=0
    BULLETS=()
    xo_call OBJ_player fire
    local lb=${BULLETS[0]}
    check '激光 cd 已从 1 调到 2' 2 "$G_FIRE_CD"
    check '激光符号统一为 |' '|' "$(field "$lb" symbol)"
    check '激光威力 = lanes+1' 1 "$(field "$lb" damage)"
    check '威力 1 用默认弹色' '' "$(field "$lb" color)"

    # 威力 2..5 用颜色区分：青 / 绿 / 紫 / 红+加粗
    local -A _lwant=( [1]=$C_CYAN [2]=$C_GREEN [3]=$C_PURPLE [4]="${C_BOLD}${C_RED}" )
    local -A _lname=( [1]=青 [2]=绿 [3]=紫 [4]='红加粗' )
    local _ln
    for _ln in 1 2 3 4 ; do
        OBJ_player[lanes]=$_ln
        BULLETS=()
        xo_call OBJ_player fire
        check "威力 $(( _ln + 1 )) 的激光是${_lname[$_ln]}色" \
            "${_lwant[$_ln]}" "$(field "${BULLETS[0]}" color)"
    done

    OBJ_player[lanes]=4
    BULLETS=()
    xo_call OBJ_player fire
    check '满 lanes 时威力 5，符号仍是 |' '5|' \
        "$(field "${BULLETS[0]}" damage)$(field "${BULLETS[0]}" symbol)"
    OBJ_player[lanes]=0
    OBJ_player[bullet]=OBJ_player[w1]

    printf '\n== K. 扫描电网（Boss 红色自上而下 / 我方绿色自下而上）==\n'
    if [[ -z "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        xo_obj_born_named OBJ_player PlaneBee >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    fi

    # K1 启动参数：我方波自下而上、绿色
    _wave_clear_all
    _wave_start 1 "$PLAYER_WAVE_DAMAGE"
    local -i s=$REPLY
    check '我方波：自下而上' -1 "${WV_DIR[$s]}"
    check '我方波：绿色' "$C_GREEN" "${WV_CLR[$s]}"
    check '我方波：从底部开始' "$(( SCREEN_H - 1 ))" "${WV_Y[$s]}"
    check '我方波：整行字符已准备好' 1 "$(( ${#WV_LINE[$s]} > 0 ? 1 : 0 ))"
    # 渲染：确认真的画出了整行（颜色 + 字符）
    ENEMIES=()
    FRAME_BUF=''
    render
    local wseen=0
    [[ "$FRAME_BUF" == *"${WV_CLR[$s]}${WV_LINE[$s]}"* ]] && wseen=1
    check '电网真的被画到屏幕上' 1 "$wseen"

    # K2 每 WAVE_STEP_TICKS 走一行（慢速扫描）
    local -i y0=${WV_Y[$s]} i
    ENEMIES=() ; eb_reset ; DROPS=() ; WORDS=()
    for (( i=0 ; i<WAVE_STEP_TICKS ; i++ )) ; do _play_game_tick >/dev/null 2>&1 ; done
    check '走满一个 step 前进 1 行' "$(( y0 - 1 ))" "${WV_Y[$s]}"

    # K3 Boss 波：打到玩家 -3 血、打掉护盾、一条波只结算一次
    # 洞是随机的，本段测"命中"，所以强制不留洞（否则玩家/子弹可能正好落在洞里）
    OBJ_player[hp]=20
    OBJ_player[shield]=1
    G_INV=0
    _wave_clear_all
    _wave_start 0 "$BOSS_WAVE_DAMAGE"
    s=$REPLY
    check 'Boss 波：红色' "$C_RED" "${WV_CLR[$s]}"
    check 'Boss 波：自上而下' 1 "${WV_DIR[$s]}"
    WV_GAP1[s]=-99 ; WV_GAP2[s]=-99
    local -i guard=0 hp_after=0
    while (( WV_ON[s] && guard < 200 )) ; do
        ((guard++))
        ENEMIES=() ; eb_reset ; DROPS=() ; WORDS=()
        _play_game_tick >/dev/null 2>&1
    done
    hp_after=${OBJ_player[hp]}
    check 'Boss 波：命中扣 3 血' 17 "$hp_after"
    check 'Boss 波：无视护盾，命中即打掉' 0 "${OBJ_player[shield]}"

    # 再来一条波：血量只再扣一次 3（说明每条波只结算一次）
    OBJ_player[hp]=20
    G_INV=0
    _wave_clear_all
    _wave_start 0 "$BOSS_WAVE_DAMAGE"
    s=$REPLY
    WV_GAP1[s]=-99 ; WV_GAP2[s]=-99
    guard=0
    while (( WV_ON[s] && guard < 200 )) ; do
        ((guard++))
        ENEMIES=() ; eb_reset ; DROPS=() ; WORDS=()
        _play_game_tick >/dev/null 2>&1
    done
    check '每条波对玩家只结算一次' 17 "${OBJ_player[hp]}"

    # K4 我方波：对同一个敌人只结算 30 点，且只结算一次
    ENEMIES=() ; eb_reset ; DROPS=() ; WORDS=() ; BULLETS=()
    xo_obj_born_named OBJ_wv EnemyQ >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    local -n _we=OBJ_wv
    _we[x]=$(( ${OBJ_player[x]} + 10 ))
    _we[y]=10
    _we[hp]=60
    _we[maxhp]=60
    unset -n _we
    ENEMIES=(OBJ_wv)
    G_INV=900        # 别让路上的敌人影响玩家，本段只关心敌人掉血
    _wave_clear_all
    _wave_start 1 "$PLAYER_WAVE_DAMAGE"
    s=$REPLY
    guard=0
    while (( WV_ON[s] && guard < 200 )) ; do
        ((guard++))
        # 只保留被测敌人，避免它被自动射击/其他怪干扰
        ENEMIES=(OBJ_wv)
        eb_reset ; DROPS=() ; WORDS=() ; BULLETS=()
        _play_game_tick >/dev/null 2>&1
    done
    local -n _wv=OBJ_wv
    local -i wv_hp=${_wv[hp]}
    unset -n _wv
    check '我方波：对敌人结算 30 点' 30 "$wv_hp"

    for (( i=0 ; i<20 ; i++ )) ; do
        ENEMIES=(OBJ_wv) ; eb_reset ; DROPS=() ; WORDS=() ; BULLETS=()
        _play_game_tick >/dev/null 2>&1
    done
    local -n _wv2=OBJ_wv
    check '同一敌人不会被同一条波重复结算' 30 "${_wv2[hp]}"
    unset -n _wv2
    ENEMIES=() ; G_INV=0

    # K5 掉落物 W：捡到即发射我方波
    xo_obj_born Drop W >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    local wdrop=$REPLY
    check '掉落 W 的 dtype' 'W' "$(field "$wdrop" dtype)"
    check '掉落 W 的字符' 'W' "$(field "$wdrop" symbol)"
    _wave_clear_all
    local -n _wd=$wdrop
    _wd[x]=${OBJ_player[x]}
    _wd[y]=${OBJ_player[y]}
    unset -n _wd
    DROPS=("$wdrop")
    ENEMIES=() ; eb_reset ; BULLETS=() ; WORDS=()
    _play_game_tick >/dev/null 2>&1
    check '捡到 W 立刻发射我方波' 1 "$WAVE_ON"
    local -i ally_slot=0 i2
    for (( i2=0 ; i2<WAVE_SLOTS ; i2++ )) ; do
        (( WV_ON[i2] && WV_OWNER[i2] == 1 )) && ally_slot=1
    done
    check '捡到的波打敌人（owner=我方）' 1 "$ally_slot"
    _wave_clear_all

    # K4b 电网同时清除那一行的子弹
    #     我方波：清敌方子弹；Boss 波：清我方子弹
    #     注意 tick 顺序：对象先 move，电网后推进。EnemyBullet 每 4 tick 才动一格，
    #     所以把敌弹放在"移动后仍在 20 行"的位置（cd=0 时本 tick 不动）。
    ENEMIES=() ; eb_reset ; BULLETS=() ; DROPS=() ; WORDS=()
    enemy_bullet_spawn EnemyBullet 30 20 'x' 1 >/dev/null 2>&1
    local -i ebul=0
    _wave_clear_all
    _wave_start 1 "$PLAYER_WAVE_DAMAGE"
    s=$REPLY
    WV_Y[s]=21                    # 本 tick 前进到 20
    WV_CD[s]=$(( WAVE_STEP_TICKS - 1 ))
    G_INV=900
    _play_game_tick >/dev/null 2>&1
    check '我方电网清掉扫到的敌方子弹' 0 "${EB_ALIVE[$ebul]}"

    ENEMIES=() ; eb_reset ; BULLETS=() ; DROPS=() ; WORDS=()
    xo_obj_born Bullet 30 21 '|' 1 0 -1 >/dev/null 2>&1
    local pbul=$REPLY
    BULLETS=("$pbul")
    _wave_clear_all
    _wave_start 0 "$BOSS_WAVE_DAMAGE"
    s=$REPLY
    WV_GAP1[s]=-99 ; WV_GAP2[s]=-99      # 本段测清弹，强制不留洞
    WV_Y[s]=19                    # 本 tick 前进到 20
    WV_CD[s]=$(( WAVE_STEP_TICKS - 1 ))
    _play_game_tick >/dev/null 2>&1
    check 'Boss 电网清掉扫到的我方子弹' '' "${XO_OBJ_POOL[$pbul]+}"

    # 波在同一行停留的那几个 tick 里也要清扫（否则会因 3:4 的节奏错拍漏掉子弹）
    ENEMIES=() ; eb_reset ; BULLETS=() ; DROPS=() ; WORDS=()
    enemy_bullet_spawn EnemyBullet 30 15 'x' 1 >/dev/null 2>&1
    local -i ebul2=0
    _wave_clear_all
    _wave_start 1 "$PLAYER_WAVE_DAMAGE"
    s=$REPLY
    WV_Y[s]=15
    WV_CD[s]=0                    # 本 tick 不前进，只停留清扫
    G_INV=900
    _play_game_tick >/dev/null 2>&1
    check '波停留期间也会清扫子弹' 0 "${EB_ALIVE[$ebul2]}"

    # 擦肩而过：波 9→8、敌弹 8→9 在同一 tick 内交换行，从未同格，也必须清掉
    ENEMIES=() ; eb_reset ; BULLETS=() ; DROPS=() ; WORDS=()
    enemy_bullet_spawn EnemyBullet 30 8 'x' 1 >/dev/null 2>&1
    local -i ebul3=0
    EB_CD[ebul3]=3               # 本 tick 会移动一格：8 -> 9
    _wave_clear_all
    _wave_start 1 "$PLAYER_WAVE_DAMAGE"
    s=$REPLY
    WV_Y[s]=9                     # 本 tick 前进到 8
    WV_CD[s]=$(( WAVE_STEP_TICKS - 1 ))
    G_INV=900
    _play_game_tick >/dev/null 2>&1
    check '与波擦肩而过的敌弹也会被清掉' 0 "${EB_ALIVE[$ebul3]}"
    _wave_clear_all ; G_INV=0

    # K6 逃生缝：Boss 波随机挖两个 3 格宽的洞，站在洞里不挨打
    _wave_clear_all
    _wave_start 0 "$BOSS_WAVE_DAMAGE"
    s=$REPLY
    local -i line_len=${#WV_LINE[$s]}
    check '挖洞后行宽不变' "$(( SCREEN_W - 4 ))" "$line_len"
    local -i gap_ok=1
    (( WV_GAP1[s] >= 0 && WV_GAP2[s] >= 0 )) || gap_ok=0
    # 两个洞不能重叠（至少隔 1 格）
    if (( WV_GAP2[s] + WAVE_GAP_W >= WV_GAP1[s] && WV_GAP2[s] <= WV_GAP1[s] + WAVE_GAP_W )) ; then
        gap_ok=0
    fi
    check '随机生成了两个不重叠的洞' 1 "$gap_ok"
    check '洞中心是安全格' 0 "$( _wave_gap_x "$s" $(( WV_GAP1[s] + 1 + 3 )) ; echo $? )"

    # 下面两条测"缝内安全 / 缝外受伤"，把缝固定成已知位置，避免随机位置让断言不稳
    OBJ_player[hp]=20
    OBJ_player[shield]=0
    G_INV=0
    _wave_clear_all
    _wave_start 0 "$BOSS_WAVE_DAMAGE"
    s=$REPLY
    WV_GAP1[s]=0 ; WV_GAP2[s]=40
    OBJ_player[x]=4            # 第 4 列 = 缝 1 的中心（波从第 3 列起算）
    local -i guard6=0
    while (( WV_ON[s] && guard6 < 200 )) ; do
        ((guard6++))
        ENEMIES=() ; eb_reset ; DROPS=() ; WORDS=()
        _play_game_tick >/dev/null 2>&1
    done
    check '站在逃生缝里不受伤' 20 "${OBJ_player[hp]}"

    # 站在缝外：照常挨打
    OBJ_player[hp]=20
    OBJ_player[x]=20           # 第 20 列不在任何一个缝里
    G_INV=0
    guard6=0
    _wave_clear_all
    _wave_start 0 "$BOSS_WAVE_DAMAGE"
    s=$REPLY
    WV_GAP1[s]=0 ; WV_GAP2[s]=40
    while (( WV_ON[s] && guard6 < 200 )) ; do
        ((guard6++))
        ENEMIES=() ; eb_reset ; DROPS=() ; WORDS=()
        _play_game_tick >/dev/null 2>&1
    done
    check '站在缝外照常受伤' 17 "${OBJ_player[hp]}"
    _wave_clear_all ; G_INV=0

    # ------------------------------------------------------------------
    # 能力生命周期钩子：add 即初始化、delete 即清理，重复获取不窜状态
    # ------------------------------------------------------------------
    printf '\n== 能力钩子：初始化 / 清理 ==\n'
    if [[ -n "${XO_OBJ_POOL[OBJ_rbX]+_}" ]] ; then xo_obj_bury OBJ_rbX >/dev/null 2>&1 ; fi
    xo_obj_born_named OBJ_rbX Boss >/dev/null 2>&1
    OBJ_rbX[hp]=180 ; OBJ_rbX[maxhp]=180

    # INV：注入即初始化，不再依赖调用方补 buff_gain
    xo_obj_mixin_add OBJ_rbX M_BuffInvuln
    check 'INV 注入后立即初始化冷却' "$BOSS_BUFF_INV_OFF" "${OBJ_rbX[bi_cd]}"

    # 人为改成脏值 → 卸载必须清掉 → 重新获取必须回到初始值（不窜属性）
    OBJ_rbX[bi_cd]=7
    xo_obj_mixin_delete OBJ_rbX M_BuffInvuln
    check 'INV 卸载后冷却清零' 0 "${OBJ_rbX[bi_cd]}"
    xo_obj_mixin_add OBJ_rbX M_BuffInvuln
    check 'INV 重新获取后状态被重置' "$BOSS_BUFF_INV_OFF" "${OBJ_rbX[bi_cd]}"
    xo_obj_mixin_delete OBJ_rbX

    # HEAL：卸载作废观察窗口（否则下次拿到会立刻回血）
    xo_obj_mixin_add OBJ_rbX M_BuffHeal
    check 'HEAL 注入后打开观察窗口' "$BOSS_BUFF_HEAL_WAIT" "${OBJ_rbX[heal_cd]}"
    xo_obj_mixin_delete OBJ_rbX M_BuffHeal
    check 'HEAL 卸载后窗口作废' 0 "${OBJ_rbX[heal_cd]}"

    # MISSILE：卸载清发射节拍
    xo_obj_mixin_add OBJ_rbX M_BuffMissile
    check 'MISSILE 注入后立即可发射' 0 "${OBJ_rbX[ms_cd]}"
    OBJ_rbX[ms_cd]=9
    xo_obj_mixin_delete OBJ_rbX M_BuffMissile
    check 'MISSILE 卸载后节拍清零' 0 "${OBJ_rbX[ms_cd]}"

    # 列表形式：一次注入两个，别名顺序即优先级
    xo_obj_mixin_add OBJ_rbX M_BuffInvuln M_BuffMissile
    xo_obj_mixin_list OBJ_rbX
    check '列表形式一次注入两个能力' 'M_BuffInvuln M_BuffMissile' "$REPLY"

    # WAVE 连发：add 立刻放第一根，之后按 {wv_cd} 定时再放，最后一根放完立刻自卸
    xo_obj_mixin_delete OBJ_rbX
    _wave_clear_all
    xo_obj_mixin_add OBJ_rbX M_BuffWave
    local -i wv_gap=${OBJ_rbX[wv_gap]} wv_left=${OBJ_rbX[wv_left]}
    check 'WAVE 获得即放第一根' 1 "$WAVE_ON"
    check 'WAVE 间隔落在 1..3 秒' 1 "$(( wv_gap >= 1*FPS && wv_gap <= 3*FPS ? 1 : 0 ))"
    check 'WAVE 总发数 2..4（已放 1）' 1 "$(( wv_left >= 1 && wv_left <= 3 ? 1 : 0 ))"
    xo_obj_mixin_list OBJ_rbX
    check 'WAVE 不是一次性：连发期间仍持有' 'M_BuffWave' "$REPLY"

    # 固定成"还剩 1 根、间隔 3 tick"，验证倒计时、放第二根、随后立即自卸
    OBJ_rbX[wv_gap]=3 ; OBJ_rbX[wv_cd]=3 ; OBJ_rbX[wv_left]=1
    _wave_clear_all
    xo_obj_call_all OBJ_rbX buff_tick
    check '倒计时递减' 2 "${OBJ_rbX[wv_cd]}"
    xo_obj_call_all OBJ_rbX buff_tick
    xo_obj_call_all OBJ_rbX buff_tick
    check '倒计时没走完不放' 0 "$WAVE_ON"
    xo_obj_call_all OBJ_rbX buff_tick
    check '到点放下一根' 1 "$WAVE_ON"
    xo_obj_mixin_list OBJ_rbX
    check '最后一根放完立刻自卸' '' "$REPLY"

    # 同屏多条：间隔到点就开新槽，不和正在扫的波抢（这是压迫感的来源）
    _wave_clear_all
    xo_obj_mixin_add OBJ_rbX M_BuffWave
    OBJ_rbX[wv_cd]=0 ; OBJ_rbX[wv_left]=3
    xo_obj_call_all OBJ_rbX buff_tick
    xo_obj_call_all OBJ_rbX buff_tick
    local -i wave_cnt=0 i3
    for (( i3=0 ; i3<WAVE_SLOTS ; i3++ )) ; do
        (( WV_ON[i3] )) && ((wave_cnt++))
    done
    check '同屏允许多条波并存' 1 "$(( wave_cnt >= 2 ? 1 : 0 ))"
    check '连发期间仍持有能力' 'M_BuffWave' "$( xo_obj_mixin_list OBJ_rbX ; echo "$REPLY" )"
    _wave_clear_all

    # 槽位耗尽时不能丢发：放不下就下一 tick 重试
    OBJ_rbX[wv_cd]=0 ; OBJ_rbX[wv_left]=2
    for (( i3=0 ; i3<WAVE_SLOTS ; i3++ )) ; do
        _wave_start 0 "$BOSS_WAVE_DAMAGE" >/dev/null
    done
    xo_obj_call_all OBJ_rbX buff_tick
    check '槽满时保留发数（下一 tick 重试）' 2 "${OBJ_rbX[wv_left]}"
    check '槽满时倒计时设为 1（下 tick 再试）' 1 "${OBJ_rbX[wv_cd]}"
    _wave_clear_all

    # 列表形式同时注入：WAVE 不会在 init 里自卸，两个都留在名单里
    xo_obj_mixin_delete OBJ_rbX
    _wave_clear_all
    xo_obj_mixin_add OBJ_rbX M_BuffWave M_BuffInvuln
    xo_obj_mixin_list OBJ_rbX
    check '同批注入的 WAVE 与 INV 都保留' 'M_BuffWave M_BuffInvuln' "$REPLY"
    _wave_clear_all

    # bury 时逐个 cleanup（只清能力自己的节拍，共享字段不动）
    OBJ_rbX[inv_cd]=99
    xo_obj_bury OBJ_rbX >/dev/null 2>&1
    check 'bury 已执行（对象出池）' '' "${XO_OBJ_POOL[OBJ_rbX]-}"

    printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
    if (( FAILS == 0 )) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
}

eval -- "$(AS_RUN_TEST_CASES)"
