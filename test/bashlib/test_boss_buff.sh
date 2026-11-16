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
        printf '  [ok]   %-46s %s\n' "$1" "$3"
    else
        printf '  [FAIL] %-46s 期望=[%s] 实际=[%s]\n' "$1" "$2" "$3"
        FAILS=$((FAILS+1))
    fi
}

# 假能力：只提供 buff_gain，用来验证发放规则
M_Ta_buff_gain () { : ; }
M_Tb_buff_gain () { : ; }
M_Tc_buff_gain () { : ; }
M_Td_buff_gain () { : ; }

xo_init

# 读某对象的增益相关字段
buf_read ()
{
    local -n _l=$1
    BUF_LIST=${_l["{OBJMIX}$X"]}
    BUF_PHASE=${_l["{buff_phase}$X"]}
    BUF_STR=${_l["{buff_str}$X"]}
    BUF_HP=${_l["{hp}$X"]}
    BUF_INV=${_l["{inv_cd}$X"]}
    BUF_BI=${_l["{bi_cd}$X"]}
    BUF_PH=${_l["{phase}$X"]}
    BUF_MS=${_l["{ms_cd}$X"]}
    unset -n _l
}

# 读任意对象的任意字段（$1=对象 $2=字段名，不带花括号）
field ()
{
    local -n _f=$1
    printf '%s' "${_f["{$2}$X"]}"
    unset -n _f
}

# 模拟 _boss_update_phase 里对 {inv_cd} 的递减（测试里不跑 Boss_move，需手动还原这一步）
inv_dec ()
{
    local -n _d=$1
    if (( ${_d["{inv_cd}$X"]:-0} > 0 )) ; then
        _d["{inv_cd}$X"]=$(( ${_d["{inv_cd}$X"]} - 1 ))
    fi
    unset -n _d
}

# hp_to <对象> <值>
hp_to ()
{
    local -n _h=$1
    _h["{hp}$X"]=$2
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
        _bb["{phase}$X"]=$ph
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
    xo_obj_born_named OBJ_rb Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_mixin_add OBJ_rb M_BuffInvuln || { log_test 0 1 ; return 1 ; }
    local -n _r0=OBJ_rb
    _r0["{bi_cd}$X"]=0
    _r0["{inv_cd}$X"]=0
    unset -n _r0

    xo_obj_call_all OBJ_rb buff_gain
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
    xo_obj_call_all OBJ_rb2 buff_gain
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
    xo_obj_call_all OBJ_rb9 buff_gain
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
    _r10["{hp}$X"]=127
    _r10["{phase}$X"]=1
    unset -n _r10
    local okrc=0
    _boss_buff_ok OBJ_rb10 M_BuffHeal || okrc=$?
    check '阶段刚切换（血量略高于上限）时回血仍可被选中' 0 "$okrc"

    xo_obj_mixin_add OBJ_rb10 M_BuffHeal || { log_test 0 1 ; return 1 ; }
    xo_obj_call_all OBJ_rb10 buff_gain
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
    _c["{bi_cd}$X"]=0
    _c["{inv_cd}$X"]=0
    unset -n _c
    xo_obj_mixin_add OBJ_rb3 M_BuffInvuln || { log_test 0 1 ; return 1 ; }
    xo_obj_mixin_add OBJ_rb3 M_BuffHeal   || { log_test 0 1 ; return 1 ; }

    xo_obj_call_all OBJ_rb3 buff_gain
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
    xo_obj_call_all OBJ_rb4 buff_gain

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
    _ov["{inv_cd}$X"]=100      # 假设此刻正处在阶段切换给的无敌里
    _ov["{bi_cd}$X"]=0
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
    xo_obj_call_all OBJ_rb5 buff_gain
    xo_obj_call_all OBJ_rb5 buff_tick
    buf_read OBJ_rb5
    check '回血封顶在本阶段上限（70% = 126）' 126 "$BUF_HP"

    # phase 3 的上限是 20%（36）：打到本阶段一半（<=18）才补
    xo_obj_born_named OBJ_rb8 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    hp_to OBJ_rb8 15
    local -n _g3=OBJ_rb8
    _g3["{phase}$X"]=3
    unset -n _g3
    xo_obj_mixin_add OBJ_rb8 M_BuffHeal || { log_test 0 1 ; return 1 ; }
    xo_obj_call_all OBJ_rb8 buff_gain
    xo_obj_call_all OBJ_rb8 buff_tick
    buf_read OBJ_rb8
    check 'phase 3 回血封顶在 20%（36）' 36 "$BUF_HP"

    local -n _g2=OBJ_rb5
    _g2["{inv_cd}$X"]=10
    unset -n _g2
    xo_call OBJ_rb5 move >/dev/null 2>&1
    buf_read OBJ_rb5
    check '回血后阶段不回退' 1 "$BUF_PH"
    check '阶段无敌窗口未被重复触发' 9 "$BUF_INV"

    printf '\n== H. 敌跟踪导弹 ==\n'
    ENEMY_BULLETS=()
    xo_obj_born_named OBJ_rb6 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_mixin_add OBJ_rb6 M_BuffMissile || { log_test 0 1 ; return 1 ; }
    xo_obj_call_all OBJ_rb6 buff_gain
    buf_read OBJ_rb6
    check '获得后立即可发射（冷却为 0）' 0 "$BUF_MS"
    xo_obj_call_all OBJ_rb6 buff_tick
    check '获得后下一 tick 立刻发射 1 枚' 1 "${#ENEMY_BULLETS[@]}"
    xo_obj_call_all OBJ_rb6 buff_tick
    buf_read OBJ_rb6
    check '发射后进入下一轮冷却' "$(( BOSS_BUFF_MISSILE_CD - 1 ))" "$BUF_MS"

    local m0=${ENEMY_BULLETS[0]}
    check '导弹伤害为 1' 1 "$(field "$m0" damage)"
    check '导弹用加粗亮红（敌方配色）' "${C_BOLD}${C_RED}" "$(field "$m0" color)"
    check '导弹用单宽实心大圆点' "$BOSS_BUFF_MISSILE_SYM" "$(field "$m0" symbol)"
    check '导弹初始燃料' "$BOSS_BUFF_MISSILE_FUEL" "$(field "$m0" fuel)"
    check '导弹比玩家慢（每 step tick 走 1 格）' "$BOSS_BUFF_MISSILE_STEP" "$(field "$m0" step)"

    # 渲染：位置 + 敌方配色 + 符号
    local -n _mv=$m0
    local mx=${_mv["{x}$X"]} my=${_mv["{y}$X"]} msym=${_mv["{symbol}$X"]}
    local mcol=${_mv["{color}$X"]}
    unset -n _mv
    FRAME_BUF=''
    render
    local needle=''
    printf -v needle '\033[%d;%dH%s%s' "$my" "$mx" "$mcol" "$msym"
    local seen=0
    [[ "$FRAME_BUF" == *"$needle"* ]] && seen=1
    check '导弹真的被画到屏幕上' 1 "$seen"

    # 先验证一次正常移动：走满一个 step 应当朝玩家方向前进 1 格
    local -n _mv0=$m0
    local -i y_before=${_mv0["{y}$X"]}
    unset -n _mv0
    local -i k
    for (( k=0 ; k<BOSS_BUFF_MISSILE_STEP ; k++ )) ; do
        xo_call "$m0" move >/dev/null 2>&1
    done
    local -n _mv1=$m0
    local -i y_after=${_mv1["{y}$X"]}
    unset -n _mv1
    check '走满一个 step 后向玩家方向前进 1 格' 1 \
        "$(( y_after == y_before + 1 ? 1 : 0 ))"

    # 燃料烧完自毁：燃料压到 1，再走满一个 step 就应当自毁（不写死 tick 数，跟着常量变）
    local -n _m=$m0
    _m["{fuel}$X"]=1
    unset -n _m
    local -i rc=0
    for (( k=0 ; k<BOSS_BUFF_MISSILE_STEP ; k++ )) ; do
        xo_call "$m0" move >/dev/null 2>&1
        rc=$?
    done
    check '燃料烧完后自毁（返回非 0）' 1 "$rc"
    # 死亡统一走 play_game 的 _enemy_bullet_kill：它必须在 kill 前登记擦除格
    MISSILE_TRAIL_CLEAR=()
    _enemy_bullet_kill "$m0"
    check '死亡出口登记了擦除格（避免残影）' 1 \
        "$(( ${#MISSILE_TRAIL_CLEAR[@]} >= 2 ? 1 : 0 ))"

    # 我方子弹一碰即毁：跑一次真实 tick，子弹从下方移到导弹同格
    ENEMY_BULLETS=() ; BULLETS=() ; ENEMIES=()
    xo_obj_born EnemyMissile 40 10 "$BOSS_BUFF_MISSILE_FUEL" 99 >/dev/null 2>&1
    local mkill=$REPLY
    xo_obj_born Bullet 40 12 '|' 1 0 -2 >/dev/null 2>&1
    local bhit=$REPLY
    ENEMY_BULLETS=("$mkill") ; BULLETS=("$bhit")
    _play_game_tick >/dev/null 2>&1
    local -i m_gone=1 b_gone=1
    [[ -n "${XO_OBJ_POOL[$mkill]+_}" ]] && m_gone=0
    [[ -n "${XO_OBJ_POOL[$bhit]+_}" ]] && b_gone=0
    check '我方子弹能把跟踪导弹打掉' 1 "$m_gone"
    check '打掉时那颗子弹也一起消失' 1 "$b_gone"
    ENEMY_BULLETS=() ; BULLETS=()

    printf '\n== I. 30 秒减速 ==\n'
    if [[ -z "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        xo_obj_born_named OBJ_player PlaneBee >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    fi
    init_game >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_born_named OBJ_rb7 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_mixin_add OBJ_rb7 M_BuffSlow || { log_test 0 1 ; return 1 ; }

    BULLETS=()
    OBJ_player["{spd_pct}$X"]=100
    xo_call OBJ_player fire
    local -i v_normal=${BULLETS[0]:+$(field "${BULLETS[0]}" vy)}
    (( v_normal < 0 )) && v_normal=$(( -v_normal ))

    xo_obj_call_all OBJ_rb7 buff_gain
    check '玩家子弹速度降到 50%' "$BOSS_BUFF_SLOW_PCT" "$(field OBJ_player spd_pct)"
    check '减速计时器 = 30 秒' "$BONUS_SLOW" "$(field OBJ_player slow)"

    BULLETS=()
    xo_call OBJ_player fire
    local -i v_slow=${BULLETS[0]:+$(field "${BULLETS[0]}" vy)}
    (( v_slow < 0 )) && v_slow=$(( -v_slow ))
    check '减速后发射的子弹确实更慢' 1 "$(( v_slow < v_normal ? 1 : 0 ))"

    # 光降弹速不会减少输出：射速也必须被压
    BULLETS=()
    OBJ_player["{spd_pct}$X"]=100
    xo_call OBJ_player fire
    local -i cd_normal=$G_FIRE_CD
    BULLETS=()
    OBJ_player["{spd_pct}$X"]=50
    xo_call OBJ_player fire
    local -i cd_slow=$G_FIRE_CD
    check '减速同时压射速（cd ×1.5）' \
        "$(( cd_normal * BOSS_BUFF_SLOW_CD_PCT / 100 ))" "$cd_slow"

    local -n _pl=OBJ_player
    _pl["{slow}$X"]=0
    _pl["{spd_pct}$X"]=100
    unset -n _pl
    check '到期后速度恢复' 100 "$(field OBJ_player spd_pct)"

    printf '\n== J. 量子能量武器 ==\n'
    OBJ_player["{spd_pct}$X"]=100
    xo_obj_born_named OBJ_laser BulletTypeLaser >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    OBJ_player["{bullet}$X"]=OBJ_laser
    OBJ_player["{lanes}$X"]=0
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
        OBJ_player["{lanes}$X"]=$_ln
        BULLETS=()
        xo_call OBJ_player fire
        check "威力 $(( _ln + 1 )) 的激光是${_lname[$_ln]}色" \
            "${_lwant[$_ln]}" "$(field "${BULLETS[0]}" color)"
    done

    OBJ_player["{lanes}$X"]=4
    BULLETS=()
    xo_call OBJ_player fire
    check '满 lanes 时威力 5，符号仍是 |' '5|' \
        "$(field "${BULLETS[0]}" damage)$(field "${BULLETS[0]}" symbol)"
    OBJ_player["{lanes}$X"]=0
    OBJ_player["{bullet}$X"]=OBJ_player["{w1}$X"]

    printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
    if (( FAILS == 0 )) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
}

eval -- "$(AS_RUN_TEST_CASES)"
