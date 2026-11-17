# classes/enemies/boss_buff.sh — Boss 动态增益（对象级 Mixin 的第一批使用者）
#
# 一局共发放 4 次：出生（phase 0）+ 3 次伤害阶段切换。
# 规则：先定新能力（不与已持有重复），再按上限随机删掉一个旧的；一次性能力用掉后会
# 自己卸载，因此槽位自然腾出。
#
# 每个能力就是一个对象级 Mixin，可用这些方法（都写成 M_<能力>_<方法名>）：
#   buff_ok      现在值不值得被拿？返回非 0 就不进候选池
#                （例：满血时回血没有意义，此时不该占用槽位）
#   _init        获得时执行一次（初始化状态 + 对世界的效果，由框架自动调用）
#   _cleanup     失去时收尾（由框架在卸载前调用；bury 不需要，对象整体销毁）
#   buff_tick    每 tick 执行（周期无敌、发射导弹……）
# 私有方法名自带一个下划线，所以完整函数名是 M_<能力>__init / M_<能力>__cleanup 这种双下划线。
# 未实现的钩子直接跳过，不需要在游戏层写任何特例。
[[ -n "${_STRAFE_BOSS_BUFF_SH:-}" ]] && return 0
_STRAFE_BOSS_BUFF_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"

# 增益池：新增能力就往这里追加一个 Mixin 名
declare -ga BOSS_BUFF_POOL=(
    M_BuffInvuln
    M_BuffHeal
    M_BuffMissile
    M_BuffSlow
    M_BuffWave
)

# HP 行尾的短标签（{buff_str} 由这里映射出来，只在增益变化时重算）
declare -gA BOSS_BUFF_LABEL=(
    [M_BuffMissile]=MIS
    [M_BuffInvuln]=INV
    [M_BuffHeal]=HEAL
    [M_BuffWave]=WAVE
    [M_BuffSlow]=SLOW
)

# 把 {OBJMIX} 映射成短标签写回 {buff_str}；{OBJMIX} 是唯一事实来源。
_boss_buff_sync_str () {
    local -n _b=$1
    local list=${_b["{OBJMIX}$X"]} out='' m
    for m in $list ; do
        out+="${BOSS_BUFF_LABEL[$m]:-?} "
    done
    _b["{buff_str}$X"]=${out% }
}

# 能力是否"当前值得拿"：没写 buff_ok 谓词的能力默认永远可用
_boss_buff_ok () {
    local fn="$2_buff_ok"
    declare -F "$fn" >/dev/null || return 0
    "$fn" "$1"
}

# 发一次增益：先定新能力（不与已持有重复），再按上限随机删一个旧的
_boss_buff_gain () {
    local boss=$1
    local -n _b=$boss
    local list=${_b["{OBJMIX}$X"]}

    local -a cand=() held=()
    local m
    for m in "${BOSS_BUFF_POOL[@]}" ; do
        [[ " $list " == *" $m "* ]] && continue
        _boss_buff_ok "$boss" "$m" || continue
        cand+=("$m")
    done
    # 一个可用的都没有（例如满血且池里只剩回血）：这一阶段就不发，属于正常情况
    (( ${#cand[@]} )) || return 0
    local new=${cand[RANDOM % ${#cand[@]}]}

    # 先定新能力，再删旧的 —— 顺序按需求固定，不要调换
    for m in $list ; do held+=("$m") ; done
    if (( ${#held[@]} >= BOSS_BUFF_MAX )) ; then
        xo_obj_mixin_delete "$boss" "${held[RANDOM % ${#held[@]}]}"
    fi

    xo_obj_mixin_add "$boss" "$new"
    # 初始化与"获得即生效"的效果都由 add 触发的 _init 负责，这里不需要再调别的钩子
    _boss_buff_sync_str "$boss"
    return 0
}

# 每 tick：阶段变了就发一次增益，然后让持有的能力自己跑一次
_boss_buff_tick () {
    local boss=$1
    local -n _b=$boss
    local -i _ph=${_b["{phase}$X"]:-0} _last=${_b["{buff_phase}$X"]:--1}
    _b["{buff_phase}$X"]=$_ph

    # 出生时 _last=-1，所以 phase 0 也算一次；加上 3 次阶段切换，一局正好 4 次
    (( _ph != _last )) && _boss_buff_gain "$boss"
    # 同样用 call_all：周期无敌等钩子需要每个能力都跑一次
    xo_obj_call_all "$boss" buff_tick
    return 0
}

# ---------------------------------------------------------------------------
# 能力：5 秒无敌 + 5 秒可受伤，循环
# 复用阶段切换的无敌窗口 {inv_cd}：它已经在扣减、已经让 Boss 变青色、已经被伤害判定
# 读取，所以这里只需要周期性把它置满，零新增渲染与判定代码。
# 周期必须是「无敌时长 + 可受伤时长」：两者相等时若只按无敌时长轮转，无敌会首尾相接。
# ---------------------------------------------------------------------------
M_BuffInvuln__init () {
    local -n self=$1
    # 获得时先等一个"可受伤"间隔再触发，避免和"阶段切换自带的无敌"重叠浪费
    self["{bi_cd}$X"]=$BOSS_BUFF_INV_OFF
    return 0
}

M_BuffInvuln__cleanup () {
    local -n self=$1
    # 只清自己的节拍。{inv_cd} 是与"阶段切换无敌"共用的字段，能力清理不能去动它——
    # 否则会提前结束一段与本能力无关的无敌窗口（越权清别人的状态）。
    # 正在生效的无敌也随它自然走完（最多 BOSS_BUFF_INV_ON），本能力只是不再续期。
    self["{bi_cd}$X"]=0
    return 0
}

M_BuffInvuln_buff_tick () {
    local -n self=$1
    local -i cd=${self["{bi_cd}$X"]:-0}
    if (( cd > 0 )) ; then
        self["{bi_cd}$X"]=$(( cd - 1 ))
        return 0
    fi
    # 到点了：进入下一轮冷却；但如果此刻已经无敌（例如阶段切换给的窗口），
    # 就不再叠加一层——否则玩家会觉得"几乎一直在无敌"。
    self["{bi_cd}$X"]=$(( BOSS_BUFF_INV_ON + BOSS_BUFF_INV_OFF ))
    if (( ${self["{inv_cd}$X"]:-0} == 0 )) ; then
        self["{inv_cd}$X"]=$BOSS_BUFF_INV_ON
    fi
    return 0
}

# ---------------------------------------------------------------------------
# 能力：生命值回复 1/4（获得时一次）
# 满血时这个能力毫无意义（Boss 出生就是满血），所以由能力自己声明"现在不值得拿"，
# 而不是让游戏层去判断"出生时别发回血"。
# ---------------------------------------------------------------------------
# 当前阶段允许回血到的上限，以及本阶段的下界（REPLY_LO）。
# 回血不能"破阶"：各阶段区间是 (pcut(n+1), pcut(n)]，phase n 的上限就是 pcut(n)，
# phase 0 的上限是满血；下界用于算出"本阶段有多宽"，决定回血什么时候触发。
_boss_phase_hp_cap () {
    local -n _c=$1
    # 注意：不要写成 local a=1 b=$a —— bash 会先把所有赋值展开再逐个赋值，b 拿到的是旧值。
    local -i mx=${_c["{maxhp}$X"]:-1}
    local -i ph=${_c["{phase}$X"]:-0}
    local -i p1=${_c["{pcut1}$X"]:-70}
    local -i p2=${_c["{pcut2}$X"]:-50}
    local -i p3=${_c["{pcut3}$X"]:-20}
    (( mx > 0 )) || mx=1
    local -i cap=$mx lo=$(( mx * p1 / 100 ))
    case $ph in
        1) cap=$(( mx * p1 / 100 )) ; lo=$(( mx * p2 / 100 )) ;;
        2) cap=$(( mx * p2 / 100 )) ; lo=$(( mx * p3 / 100 )) ;;
        3) cap=$(( mx * p3 / 100 )) ; lo=0 ;;
    esac
    REPLY=$cap
    REPLY_LO=$lo
    return 0
}

M_BuffHeal_buff_ok () {
    local -n self=$1
    local -i hp=${self["{hp}$X"]:-0}
    local -i mx=${self["{maxhp}$X"]:-0}
    # 只要受过伤就值得拿。不要用"当前还有没有恢复空间"来筛：阶段判定是整数截断
    # （127*100/180 = 70 就算进了 phase 1），而本阶段上限是 126，所以刚跨阶段时
    # 血量几乎总比上限高一点，按"有空间"筛就永远筛不中，回血从挂不上。
    (( mx > 0 && hp < mx ))
}

# 回血：在本阶段内"补血"。
# 为什么不是拿到就立刻回：刚跨过阶段边界时 Boss 正贴着本阶段上限，那一刻最多只能加
# 1 点（等于空技能）。所以拿到后先挂一个观察窗口，等玩家把本阶段的血又打掉一半，
# 才一次性补回本阶段上限 —— 既守住"不破阶"，又让回血真的看得见。
M_BuffHeal__init () {
    local -n self=$1
    self["{heal_cd}$X"]=$BOSS_BUFF_HEAL_WAIT
    return 0
}

M_BuffHeal__cleanup () {
    local -n self=$1
    # 能力被摘掉：观察窗口作废（正在等待的回血不再发生）
    self["{heal_cd}$X"]=0
    return 0
}

M_BuffHeal_buff_tick () {
    local -n self=$1
    local -i ttl=${self["{heal_cd}$X"]:-0}
    local -i hp=${self["{hp}$X"]:-0}

    if (( ttl <= 0 )) ; then
        # 窗口内一直没等到机会：卸载，把槽位还回去
        xo_obj_mixin_delete "$1" M_BuffHeal
        _boss_buff_sync_str "$1"
        return 0
    fi

    self["{heal_cd}$X"]=$(( ttl - 1 ))

    _boss_phase_hp_cap "$1"
    local -i cap=$REPLY
    local -i lo=$REPLY_LO
    local -i need=$(( (cap - lo) / 2 ))
    (( need < 4 )) && need=4

    # 本阶段的血被打掉了一半 → 补回本阶段上限（绝不越过它）
    if (( cap - hp >= need )) ; then
        self["{hp}$X"]=$cap
        local -i by=${self["{y}$X"]} bx=${self["{x}$X"]} bw=${self["{w}$X"]:-9}

        local -i cx=$(( bx + bw / 2 )) cy=$(( by + 1 ))
        local -a _dxs=(-2 -1 0 1 2 1 0 -1)
        local -a _dys=(-1 -1 -1 -1 0 1 1 1)
        local -i i ttl2
        for (( i=0 ; i<8 ; i++ )) ; do
            ttl2=$(( 8 + (i % 3) * 6 ))
            _hit_fx_add "$(( cy + _dys[i] ))" "$(( cx + _dxs[i] ))" '+' "$C_GREEN" "$ttl2"
        done

        xo_obj_mixin_delete "$1" M_BuffHeal
        _boss_buff_sync_str "$1"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# 能力：敌跟踪导弹（周期发射，场上最多 BOSS_BUFF_MISSILE_MAX 枚）
# ---------------------------------------------------------------------------
M_BuffMissile__init () {
    local -n self=$1
    # 获得即发射：否则玩家要等 4 秒才看到第一次效果，容易以为能力没生效
    self["{ms_cd}$X"]=0
    return 0
}

M_BuffMissile__cleanup () {
    local -n self=$1
    # 只清自己的发射节拍；已经在飞的导弹属于游戏层的子弹表，不在这里回收
    self["{ms_cd}$X"]=0
    return 0
}

M_BuffMissile_buff_tick () {
    local -n self=$1
    local -i cd=${self["{ms_cd}$X"]:-0}
    if (( cd > 0 )) ; then
        self["{ms_cd}$X"]=$(( cd - 1 ))
        return 0
    fi
    self["{ms_cd}$X"]=$BOSS_BUFF_MISSILE_CD

    # 场上数量上限：只在真要发射时数一次，不在每 tick 数
    local -i live=0
    local eb
    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "${XO_OBJ_POOL[$eb]+_}" && "${XO_OBJ_POOL[$eb]}" == EnemyMissile ]] && (( live++ ))
    done

    local -i sx=$(( ${self["{x}$X"]} + ${self["{w}$X"]:-9} / 2 ))
    local -i sy=$(( ${self["{y}$X"]} + ${self["{h}$X"]:-5} ))

    (( live >= BOSS_BUFF_MISSILE_MAX )) && return 0
    enemy_bullet_spawn EnemyMissile "$sx" "$sy" \
        "$BOSS_BUFF_MISSILE_FUEL" "$BOSS_BUFF_MISSILE_STEP" >/dev/null 2>&1
    return 0
}

# ---------------------------------------------------------------------------
# 能力：扫描电网（红色，自上而下扫过整个战场；一次能力连放 2..4 根）
# 无视护盾（命中时把玩家的护盾打掉），但仍受无敌帧保护。
# 获得时立刻放第一根；之后每隔 1..3 秒放一根，**允许同屏多条波**（压迫感的来源：
# 缝隙每根都重新随机，玩家要连续换位躲）。放完最后一根立刻卸载，把槽位还回去。
# 这是延迟动作，所以状态放在 {wv_left}/{wv_cd}/{wv_gap} 里由 buff_tick 推进，
# 不能在 _init 里放完就删。
# ---------------------------------------------------------------------------
M_BuffWave__init () {
    local -n self=$1
    local -i gap_s=$(( BOSS_WAVE_GAP_MIN + RANDOM % (BOSS_WAVE_GAP_MAX - BOSS_WAVE_GAP_MIN + 1) ))
    local -i n=$(( BOSS_WAVE_BURST_MIN + RANDOM % (BOSS_WAVE_BURST_MAX - BOSS_WAVE_BURST_MIN + 1) ))
    self["{wv_gap}$X"]=$(( gap_s * FPS ))
    self["{wv_cd}$X"]=$(( gap_s * FPS ))
    self["{wv_left}$X"]=$(( n - 1 ))      # 第一根立刻放，所以剩下 n-1 根
    _wave_start 0 "$BOSS_WAVE_DAMAGE"
    return 0
}

M_BuffWave_buff_tick () {
    local -n self=$1
    local -i cd=${self["{wv_cd}$X"]:-0}
    if (( cd > 0 )) ; then
        self["{wv_cd}$X"]=$(( cd - 1 ))
        return 0
    fi

    # 到点：占一个空槽放一条波（同屏可以有多条）
    if ! _wave_start 0 "$BOSS_WAVE_DAMAGE" ; then
        # 槽位满了：下一 tick 再试，别把这一根丢掉
        self["{wv_cd}$X"]=1
        return 0
    fi
    local -i left=$(( ${self["{wv_left}$X"]:-0} - 1 ))
    if (( left <= 0 )) ; then
        # 最后一根已经放出去了：立刻卸载，把槽位还给后面的阶段
        xo_obj_mixin_delete "$1" M_BuffWave
        _boss_buff_sync_str "$1"
        return 0
    fi
    self["{wv_left}$X"]=$left
    self["{wv_cd}$X"]=${self["{wv_gap}$X"]}
    return 0
}

M_BuffWave__cleanup () {
    local -n self=$1
    # 只清自己的连发状态；已经放出去的波属于场景系统，让它自然扫完
    self["{wv_left}$X"]=0
    self["{wv_cd}$X"]=0
    return 0
}

# ---------------------------------------------------------------------------
# 能力：30 秒内我方子弹速度 -50%
# 一次性挂到玩家身上（百分比 + 计时器）；到期由 _play_game_tick 的计时器循环恢复。
# 只影响之后发射的子弹，已经在飞的子弹速度已定。
# 状态在玩家身上、由独立计时器收尾，所以只有 _init（获得即生效），没有 cleanup。
# ---------------------------------------------------------------------------
M_BuffSlow__init () {
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] || return 0
    OBJ_player["{spd_pct}$X"]=$BOSS_BUFF_SLOW_PCT
    OBJ_player["{slow}$X"]=$BONUS_SLOW
    return 0
}
