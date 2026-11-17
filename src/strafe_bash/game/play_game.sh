# game/play_game.sh — 单局主循环（游戏核心逻辑）
[[ -n "${_STRAFE_PLAY_GAME_SH:-}" ]] && return 0
_STRAFE_PLAY_GAME_SH=1

. "$STRAFE_LIB_HOME/xo.sh"

# config 层
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/config/words.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

# classes 层
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/bullet.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/missile.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_missile.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_base.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/boss_bullet.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_spinner.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/skull_king.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_buff.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_v.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_q.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_m.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_b.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss.sh"
. "$STRAFE_PROJ_DIR/classes/pickups/drop.sh"
. "$STRAFE_PROJ_DIR/classes/pickups/word.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_helpers.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_types.sh"

# render 层
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/render/frame.sh"
. "$STRAFE_PROJ_DIR/render/hud.sh"
. "$STRAFE_PROJ_DIR/render/scene.sh"
. "$STRAFE_PROJ_DIR/render/fx.sh"
. "$STRAFE_PROJ_DIR/render/clear_banner.sh"

# save 层
. "$STRAFE_PROJ_DIR/save/save.sh"

# ============================================================================
# 鼠标：xterm SGR 鼠标上报（1003 any-event + 1006 SGR）
# 只移动飞机；开火仍然是自动的。
# ============================================================================
_mouse_on () {
    (( G_MOUSE_ON )) && return 0
    cursor_hide
    # 1003 any-event；1002/1000 are fallbacks for terminals that only
    # implement click/drag tracking (e.g. WindTerm).
    # ESC：控制序列开始
    # [?：DEC 私有模式
    # 1000：点击上报
    # 1002：按住拖动上报
    # 1003：任何鼠标移动都上报
    # 1006：SGR 坐标格式
    # h：开启
    # l：关闭
    printf '\033[?1000h\033[?1002h\033[?1003h\033[?1006h'
    G_MOUSE_ON=1
}
_mouse_off () {
    printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l'
    G_MOUSE_ON=0
}
_mouse_assert () {
    # 有些终端在失焦/切换后会悄悄丢掉鼠标上报；定期重新声明一次
    if (( G_MOUSE_ON )) ; then
        printf '\033[?1000h\033[?1002h\033[?1003h\033[?1006h'
    else
        _mouse_on
    fi
}
_mouse_move_to () {
    local -i tx=$1 ty=$2
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] || return 0
    local -i cx=${OBJ_player["{x}$X"]} cy=${OBJ_player["{y}$X"]}
    xo_call "OBJ_player" move "$((tx - cx))" "$((ty - cy))"
    need_render=1
}
_mouse_bomb () {
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] || return 0
    (( ${OBJ_player["{bombs}$X"]:-0} > 0 )) && G_WANT_BOMB=1
}
_mouse_apply () {
    local seq=$1
    [[ "$seq" == '[<'* ]] || return 0
    [[ "$seq" == *M || "$seq" == *m ]] || return 0
    local ev=${seq: -1}
    local body=${seq:2:${#seq}-3}
    local mb mx my
    IFS=';' read -r mb mx my <<< "$body"
    [[ "$mx" =~ ^[0-9]+$ && "$my" =~ ^[0-9]+$ ]] || return 0
    (( mb & 64 )) && return 0     # 滚轮不移动飞机
    # SGR 的 m 通常是 release，但 WindTerm 的 no-button motion 也会用 m。
    # 只有“没有 motion 位”的 m 才是真正的释放。
    [[ "$ev" == "m" ]] && (( !(mb & 32) )) && return 0
    if (( (mb & 3) == 2 && !(mb & 32) )) ; then
        _mouse_bomb
        return 0
    fi
    # 指针放在飞机正下方两格，避免挡住机体
    _mouse_move_to "$mx" "$(( my - 2 ))"
}

# ============================================================================
# _hit_fx_add — 命中火花（短命，不创建 xo 对象）
# ttl 可选：普通命中用默认 3 tick，回血那种需要看得见的动画会传更大值
# ============================================================================
_hit_fx_add () {
    local y=$1 x=$2 ch=$3 clr=$4
    local -i ttl=${5:-3}
    (( y >= GAME_TOP && y < SCREEN_H - 1 && x >= 2 && x <= SCREEN_W - 2 )) || return 0
    (( ${#HIT_FX[@]} >= HIT_FX_LIMIT )) && return 0
    HIT_FX+=("$y" "$x" "$ch" "$clr" "$ttl")
}

# ============================================================================
# _wave_start — 启动一条扫描电网，占一个空槽（**允许同屏多条**）
# owner 0 = Boss（红，自上而下，打玩家）；1 = 我方（绿，自下而上，打敌人）
# 返回 0=成功；1=槽位已满（调用方决定重试还是放弃）。
# 注意：不复位该槽的 WV_LAST_Y —— 让渲染器先把上一条波的最后一行擦掉。
# ============================================================================
_wave_start () {
    local -i owner=$1
    local -i dmg=$2
    local -i slot=-1 i
    for (( i=0 ; i<WAVE_SLOTS ; i++ )) ; do
        (( WV_ON[i] )) || { slot=$i ; break ; }
    done
    (( slot >= 0 )) || return 1

    WV_ON[slot]=1
    WV_OWNER[slot]=$owner
    WV_DMG[slot]=$dmg
    WV_CD[slot]=0
    WV_HIT[slot]=0
    WV_CLEAR_LO[slot]=0
    WV_CLEAR_HI[slot]=0
    WAVE_ON=1
    if (( owner == 0 )) ; then
        WV_DIR[slot]=1
        WV_Y[slot]=$(( GAME_TOP - 1 ))
        WV_CLR[slot]=$C_RED
    else
        WV_DIR[slot]=-1
        WV_Y[slot]=$(( SCREEN_H - 1 ))
        WV_CLR[slot]=$C_GREEN
    fi

    # 整行字符只在这里拼一次，之后每帧直接复用
    local -i _n=$(( SCREEN_W - 4 ))
    local _line
    printf -v _line '%*s' "$_n" ''
    _line=${_line// /$WAVE_SYMBOL}

    # Boss 的波随机挖两个逃生缝（同一条波内固定，玩家能提前看到并跑过去）。
    # 我方波不留缝：它是来救场的，留洞反而放过敌人子弹。
    WV_GAP1[slot]=-99
    WV_GAP2[slot]=-99
    if (( owner == 0 )) ; then
        local -i _room=$(( _n - WAVE_GAP_W ))
        (( _room < 0 )) && _room=0
        local -i _try _g1 _g2
        _g1=$(( RANDOM % (_room + 1) ))
        _g2=$(( RANDOM % (_room + 1) ))
        for (( _try=0 ; _try<20 ; _try++ )) ; do
            # 两洞之间至少隔 1 格，避免连成一个大洞
            if (( _g2 + WAVE_GAP_W < _g1 || _g2 > _g1 + WAVE_GAP_W )) ; then
                break
            fi
            _g2=$(( RANDOM % (_room + 1) ))
        done
        WV_GAP1[slot]=$_g1
        WV_GAP2[slot]=$_g2
        for _g1 in "${WV_GAP1[slot]}" "${WV_GAP2[slot]}" ; do
            (( _g1 < 0 || _g1 > _room )) && continue
            _line="${_line:0:_g1}   ${_line:_g1+WAVE_GAP_W}"
        done
    fi
    WV_LINE[slot]=$_line

    # 槽位可能被上一条波用过：清掉它遗留的命中记录，避免新波"打不动"敌人
    if (( ${#WAVE_HIT_ENEMY[@]} )) ; then
        local _k
        for _k in "${!WAVE_HIT_ENEMY[@]}" ; do
            [[ "$_k" == "$slot|"* ]] && unset -v 'WAVE_HIT_ENEMY[$_k]'
        done
    fi
    REPLY=$slot
    return 0
}

# 某个屏幕列是否落在第 $1 条波的逃生缝里（$2=屏幕列）
_wave_gap_x () {
    local -i slot=$1
    local -i idx=$(( $2 - 2 ))
    (( idx >= WV_GAP1[slot] && idx < WV_GAP1[slot] + WAVE_GAP_W )) && return 0
    (( idx >= WV_GAP2[slot] && idx < WV_GAP2[slot] + WAVE_GAP_W )) && return 0
    return 1
}

# 清空所有波（换局/读档/测试用）：槽全灭、派生标量归零。
# **不重置 WV_LAST_Y**：渲染器要靠它把每条波最后画过的那一行擦掉，否则留残影。
_wave_clear_all () {
    local -i i
    for (( i=0 ; i<WAVE_SLOTS ; i++ )) ; do
        WV_ON[i]=0
    done
    WAVE_ON=0
    G_WAVE_DMG_PENDING=0
    WAVE_HIT_ENEMY=()
    return 0
}

# ============================================================================
# _enemy_bullet_bury — 敌方子弹 / 导弹的唯一死亡出口
# 死之前先把「最后画过的那一格」交给擦除队列：炸弹清屏、撞玩家、燃料耗尽都会让它们
# 在画面中间消失，对象一旦被 bury，渲染阶段就再也找不到它，不登记就会留下一个残格。
# ============================================================================
_enemy_bullet_bury () {
    local obj=$1
    local -n _k=$obj
    local -i py=${_k["{prev_y}$X"]:--1} px=${_k["{prev_x}$X"]:--1}
    if (( py >= GAME_TOP && py < SCREEN_H - 1 && px >= 2 && px <= SCREEN_W - 2 )) ; then
        MISSILE_TRAIL_CLEAR+=("$py" "$px")
    fi
    # 解聘而不是销毁：弹体回到资源市场，下一发直接复用（省掉类模板反序列化）
    xo_obj_fire "$obj"
}

_score_bonus () {
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] || return 0
    OBJ_player["{score}$X"]=$(( ${OBJ_player["{score}$X"]:-0} + $1 ))
}

# 掉落类型抽取：把 [0,100) 的随机数按权重映射成掉落符号。
# 三套权重对应玩家的 lane 状态，百分比也就是阈值本身：
#   lanes 1..3 : L15 S5  W5  m20 H10 b5 2:5  3:10 4:10 5:15   （L/S 降，m 升，tier2 降）
#   lanes == 0 : L10 S5  W5  m20 H10 b5 2:5  3:10 4:10 5:20
#   lanes <  0 : L5  S5  m15 W5  H10 b5 2:5  3:10 4:15 5:25
# 用阈值 if 链而不是 case 枚举：枚举要逐项匹配几十个模式，实测比阈值链慢约 1.6 倍；
# 而且阈值直接就是权重，调平衡不用数格子。
# $1=当前 lane 数  $2=0..99 的随机数；结果放 REPLY。
_drop_pick_type () {
    local -i lanes=$1 r=$2
    if (( lanes >= 1 && lanes <= 3 )) ; then
        if (( r < 15 )) ; then REPLY='L'
        elif (( r < 20 )) ; then REPLY='S'
        elif (( r < 25 )) ; then REPLY='W'
        elif (( r < 45 )) ; then REPLY='m'
        elif (( r < 55 )) ; then REPLY='H'
        elif (( r < 60 )) ; then REPLY='b'
        elif (( r < 65 )) ; then REPLY='2'
        elif (( r < 75 )) ; then REPLY='3'
        elif (( r < 85 )) ; then REPLY='4'
        else REPLY='5'
        fi
    elif (( lanes == 0 )) ; then
        if (( r < 10 )) ; then REPLY='L'
        elif (( r < 15 )) ; then REPLY='S'
        elif (( r < 20 )) ; then REPLY='W'
        elif (( r < 40 )) ; then REPLY='m'
        elif (( r < 50 )) ; then REPLY='H'
        elif (( r < 55 )) ; then REPLY='b'
        elif (( r < 60 )) ; then REPLY='2'
        elif (( r < 70 )) ; then REPLY='3'
        elif (( r < 80 )) ; then REPLY='4'
        else REPLY='5'
        fi
    else
        if (( r < 5 )) ; then REPLY='L'
        elif (( r < 10 )) ; then REPLY='S'
        elif (( r < 25 )) ; then REPLY='m'
        elif (( r < 30 )) ; then REPLY='W'
        elif (( r < 40 )) ; then REPLY='H'
        elif (( r < 45 )) ; then REPLY='b'
        elif (( r < 50 )) ; then REPLY='2'
        elif (( r < 60 )) ; then REPLY='3'
        elif (( r < 75 )) ; then REPLY='4'
        else REPLY='5'
        fi
    fi
    return 0
}

# 导弹尾点清理：只记录最后渲染过的尾点，死亡时交给场景统一擦除。
_missile_queue_trail_clear () {
    local -n _mt=$1
    local -i tx=${_mt["{prev_trail_x}$X"]:--1}
    local -i ty=${_mt["{prev_trail_y}$X"]:--1}
    if (( tx >= 0 && ty >= 0 )) ; then
        MISSILE_TRAIL_CLEAR+=("$ty" "$tx")
    fi
}

# 撞击伤害：由 M_Ram 提供伤害值，游戏层负责计分/死亡/Boss 收尾。
# 返回 0 表示撞死，1 表示还活着。
_ram_enemy () {
    local eid=$1 ex=$2 ey=$3 ew=$4 eh=$5 eart=$6
    local -n _re=$eid
    local -i hp=${_re["{hp}$X"]:-1}
    local -i escore=${_re["{score}$X"]:-0}
    local -i _rinv=${_re["{inv_cd}$X"]:-0}
    local -i rdmg
    REPLY=
    xo_call "OBJ_player" ram_damage
    rdmg=${REPLY:-5}
    REPLY=
    (( rdmg > 0 )) || rdmg=5
    (( _rinv > 0 )) && rdmg=0
    hp=$(( hp - rdmg ))
    _re["{hp}$X"]=$hp
    _hit_fx_add "$py" "$px" '*' "$C_CYAN"
    (( hp <= 0 )) || return 1
    ((G_KILLS++))
    OBJ_player["{score}$X"]=$(( ${OBJ_player["{score}$X"]:-0} + escore * _score_pct / 100 ))
    if Base_is_a "$eid" BossBase ; then
        ((G_BOSS_KILLS++))
        _boss_on_death "$eid" "$ex" "$ey" "$ew" "$eh" "$eart"
    fi
    xo_obj_bury "$eid"
    return 0
}

# ============================================================================
# _boss_on_death — Boss 死亡统一处理（掉落 + 死亡动画参数）
# ============================================================================
_boss_on_death () {
    local obj=$1 ex=$2 ey=$3 ew=$4 eh=$5 art=$6
    local -n _b=$obj
    local -i _style=${_b["{death_style}$X"]:-0}
    local _bname=${_b["{name}$X"]:-THE BOSS}

    # 击杀 Boss 也触发全清横幅；与清场条件互相独立
    _score_bonus "$BOSS_SCORE_BONUS"
    _clear_banner_start "${_bname} WAS KILLED BY YOU!  +${BOSS_SCORE_BONUS}"

    # 如果上一个 Boss 的死亡特效还没放完，先擦掉残留火花
    local _i _t
    for (( _i=0; _i<${#BOSS_DEATH_POS[@]}; _i+=2 )) ; do
        printf -v _t '\033[%d;%dH ' "${BOSS_DEATH_POS[_i]}" "${BOSS_DEATH_POS[_i+1]}"
        FRAME_BUF+="$_t"
    done
    BOSS_DEATH_POS=()
    BOSS_DEATH_STYLE=$_style
    BOSS_DEATH_CX=$(( ex + ew / 2 ))
    BOSS_DEATH_CY=$(( ey + eh / 2 ))
    BOSS_DEATH_WAVE=0
    BOSS_DEATH_TICK=30

    # style 0：老 Boss，按 art 的非空格子放随机火花
    if (( _style == 0 )) ; then
        local _dr=0 _drest=$art
        while [[ -n "$_drest" ]] ; do
            local _dl=${_drest%%$'\n'*}
            if [[ "$_drest" == *$'\n'* ]] ; then _drest=${_drest#*$'\n'}
            else _drest=''
            fi
            local _dc=0 _dlen=${#_dl}
            while (( _dc < _dlen )) ; do
                local _dch=${_dl:_dc:1}
                [[ "$_dch" != " " ]] && BOSS_DEATH_POS+=($((ey + _dr)) $((ex + _dc)))
                ((_dc++))
            done
            ((_dr++))
        done
    fi

    local _bdt=(2 3 4 5 H b m L S)
    local _bdc="${_bdt[RANDOM % 9]}"
    xo_obj_born Drop "$_bdc"
    local -n _bd=$REPLY
    _bd["{x}$X"]=$(( ex + ew / 2 ))
    _bd["{y}$X"]=$(( ey + eh - 1 ))
    DROPS+=("$REPLY")
}

# 随机挑一个 Boss 类：经典/旋刃各 37.5%，骷髅王 25%
# 骷髅王约为另外两个各自概率的 2/3。
_boss_random_class () {
    local -i _r=$(( RANDOM % 8 ))
    if (( _r < 3 )) ; then
        REPLY=Boss
    elif (( _r < 6 )) ; then
        REPLY=BossSpinner
    else
        REPLY=SkullKing
    fi
}

# 全清横幅条件：30 秒内没有敌人从底部逃出，且场上敌人已清空。
# 触发后冷却 60 秒，避免连续清场时横幅和奖励刷屏。
_clear_banner_ready () {
    (( CLEAR_BANNER_TICK == 0 )) || return 1
    (( G_RUN_TICKS - G_LAST_ESCAPE_TICK >= 30 * FPS )) || return 1
    (( G_LAST_ACE_TICK == 0 || G_RUN_TICKS - G_LAST_ACE_TICK >= 60 * FPS )) || return 1
    (( ${#ENEMIES[@]} == 0 )) || return 1
    return 0
}

# ============================================================================
# _play_game_tick — 单个逻辑 tick（纯计算，绝不碰终端）
# ============================================================================
_play_game_tick () {
    local b e d eb m w
    # 本 tick 的"已死标记"：所有死亡都只标记，统一在第 9 段清理时 bury/fire。
    # 这样从第 5 段（对象移动，会重建各数组）到第 9 段之间，数组里不会出现死句柄。
    local -A killed_b=() killed_m=()
    ((G_RUN_TICKS++))
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && xo_call "OBJ_player" blink_tick
    if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && declare -F "${XO_OBJ_POOL[OBJ_player]}_ram_tick" >/dev/null 2>&1 ; then
        xo_call "OBJ_player" ram_tick
    fi
    (( G_RUN_TICKS % 30 == 0 )) && _mouse_assert

    # ---- 0. 奖励计时器递减（每 tick 减 1）----
    local -i _score_pct=${OBJ_player["{score_pct}$X"]:-100}
    local _tk _tv
    for _tk in "{t2}$X" "{t3}$X" "{t4}$X" "{t5}$X" "{mt}$X" "{lt}$X" "{st}$X" "{slow}$X" ; do
        _tv=${OBJ_player[$_tk]:-0}
        (( _tv > 0 )) && OBJ_player["$_tk"]=$(( _tv - 1 ))
    done
    (( ${OBJ_player["{lt}$X"]:-0} == 0 )) && OBJ_player["{lanes}$X"]=0
    # 减速到期：恢复我方子弹速度（增益由 Boss 的 M_BuffSlow 施加）
    if (( ${OBJ_player["{slow}$X"]:-0} == 0 && ${OBJ_player["{spd_pct}$X"]:-100} != 100 )) ; then
        OBJ_player["{spd_pct}$X"]=100
    fi
    if (( ${OBJ_player["{shield}$X"]:-0} && ${OBJ_player["{st}$X"]:-0} == 0 )) ; then
        _plane_set_shield "OBJ_player" 0
    fi

    # ---- 0.5 武器过期检测 ----
    # 当前武器是一个独立的 BulletType 子类对象；过期后只切回默认武器，
    # 不再像旧实现那样每 tick 动态 bury/born 一个 BulletType。
    local _bt=${OBJ_player["{bullet}$X"]}
    local _tier=1
    if [[ -n "$_bt" && -n "${XO_OBJ_POOL[$_bt]+_}" ]] ; then
        local -n _bo=$_bt
        _tier=${_bo["{tier}$X"]:-1}
    fi
    local _tk_cur="{t$_tier}$X"
    if (( _tier >= 2 && _tier <= 5 )) && (( ${OBJ_player[$_tk_cur]:-0} == 0 )) ; then
        OBJ_player["{bullet}$X"]=${OBJ_player["{w1}$X"]}
    fi
    # ---- 1. 冷却递减 ----
    (( G_FIRE_CD > 0 )) && ((G_FIRE_CD--))
    (( G_MISSILE_CD > 0 )) && ((G_MISSILE_CD--))
    (( G_INV > 0 )) && ((G_INV--))

    # ---- 2. 玩家移动 ----
    (( G_DX || G_DY )) && xo_call "OBJ_player" move "$G_DX" "$G_DY"

    # ---- 3. 玩家开火 ----
    # 射速由当前武器类的 {cd} 决定，Plane_fire 内部会设置 G_FIRE_CD
    if (( G_FIRE_CD == 0 )) ; then
        xo_call "OBJ_player" fire
    fi

    # ---- 4. 玩家导弹发射 ----
    if (( ${OBJ_player["{mt}$X"]:-0} > 0 && G_MISSILE_CD == 0 )) ; then
        local _my=$(( ${OBJ_player["{y}$X"]} - 1 ))
        local _mx
        if (( G_MISSILE_SIDE )) ; then
            _mx=$(( ${OBJ_player["{x}$X"]} - 1 ))
            G_MISSILE_SIDE=0
        else
            _mx=$(( ${OBJ_player["{x}$X"]} + 1 ))
            G_MISSILE_SIDE=1
        fi
        (( _mx < 2 )) && _mx=2
        (( _mx > SCREEN_W - 2 )) && _mx=$(( SCREEN_W - 2 ))
        xo_obj_hire Missile "$_mx" "$_my" 2
        MISSILES+=("$REPLY")
        G_MISSILE_CD=10
    fi
    # ---- 5. 所有对象 move ----
    # 玩家子弹只有 Bullet 一类；这里内联移动，省掉每颗一次 xo_call。
    local -a alive_b=()
    for b in "${BULLETS[@]}" ; do
        local -n _b=$b
        local -i bx=${_b["{x}$X"]} by=${_b["{y}$X"]}
        bx=$(( bx + ${_b["{vx}$X"]} ))
        by=$(( by + ${_b["{vy}$X"]} ))
        _b["{x}$X"]=$bx
        _b["{y}$X"]=$by
        if (( by < GAME_TOP || bx < 2 || bx > SCREEN_W - 2 )) ; then
            # 飞出屏幕：解聘，肉体回资源市场（BULLETS 在循环后重建，句柄随后摘除）
            xo_obj_fire "$b"
        else
            alive_b+=("$b")
        fi
    done
    BULLETS=("${alive_b[@]}")

    local -a alive_m=()
    for m in "${MISSILES[@]}" ; do
        # 逐对象循环统一内联分发（同敌弹循环）：类名仍从池子取，多态不变
        "${XO_OBJ_POOL[$m]}_move" "$m"
        if (( $? == 0 )) ; then alive_m+=("$m") ; else _missile_queue_trail_clear "$m" ; xo_obj_fire "$m" ; fi
    done
    MISSILES=("${alive_m[@]}")

    # 我方子弹的位置表：只在场上真有跟踪导弹时才惰性构建（导弹可被打掉才需要它）。
    local -A _pbmap=()
    local -i _pbmap_ready=0

    local -a alive_eb=()
    for eb in "${ENEMY_BULLETS[@]}" ; do
        # 内联分发：与 xo_call "$eb" move 逐字等价（多态性不丢：类名仍从池子取），
        # 只省掉 xo_call 那层包装帧。这一循环是全场最热的调用点之一（一屏上百发）。
        "${XO_OBJ_POOL[$eb]}_move" "$eb"
        if (( $? == 0 )) ; then
            # 跟踪导弹可以被我方子弹打掉，一碰即毁；普通敌弹不参与，保持原来的手感。
            if [[ "${XO_OBJ_POOL[$eb]}" == "EnemyMissile" ]] ; then
                if (( ! _pbmap_ready )) ; then
                    _pbmap=()
                    local _pb _py _px
                    for _pb in "${BULLETS[@]}" ; do
                        [[ -n "$_pb" && -n "${XO_OBJ_POOL[$_pb]+_}" ]] || continue
                        local -n _pob=$_pb
                        _py=${_pob["{y}$X"]} ; _px=${_pob["{x}$X"]}
                        _pbmap["$_py,$_px"]=$_pb
                    done
                    _pbmap_ready=1
                fi
                local -n _emb=$eb
                local -i _emy=${_emb["{y}$X"]} _emx=${_emb["{x}$X"]}
                if [[ -n "${_pbmap["$_emy,$_emx"]+_}" ]] ; then
                    local _hitb=${_pbmap["$_emy,$_emx"]}
                    # 命中火花既做反馈，也负责把这个格子擦干净（和打中敌人同一套）
                    _hit_fx_add "$_emy" "$_emx" '*' "$C_YELLOW"
                    _enemy_bullet_bury "$eb"
                    # 我方子弹只做"死亡标记"，不在这里 bury：BULLETS 早在第 5 段
                    # 开头就重建过了，立刻 bury 会在数组里留下一个死句柄（第 7 段
                    # 用 killed_b 跳过它，第 9 段统一清理并把它从数组里摘掉）。
                    killed_b[$_hitb]=1
                    unset "_pbmap[$_emy,$_emx]"
                    continue
                fi
            fi
            alive_eb+=("$eb")
        else
            _enemy_bullet_bury "$eb"
        fi
    done
    ENEMY_BULLETS=("${alive_eb[@]}")

    local -a alive_e=()
    for e in "${ENEMIES[@]}" ; do
        # 逐对象循环统一内联分发（同敌弹循环）：类名仍从池子取，多态不变
        "${XO_OBJ_POOL[$e]}_move" "$e"
        if (( $? == 0 )) ; then
            alive_e+=("$e")
            # Boss 动态增益：类名比较比 Base_is_a 便宜，且只有 3 个 Boss 会进入
            case "${XO_OBJ_POOL[$e]}" in
                Boss|BossSpinner|SkullKing) _boss_buff_tick "$e" ;;
            esac
        else
            local -n _esc=$e
            local -i _esc_y=${_esc["{y}$X"]} _esc_h=${_esc["{h}$X"]:-1}
            (( _esc_y + _esc_h >= SCREEN_H - 1 )) && G_LAST_ESCAPE_TICK=$G_RUN_TICKS
            xo_obj_bury "$e"
        fi
    done
    ENEMIES=("${alive_e[@]}")

    local -a alive_d=()
    for d in "${DROPS[@]}" ; do
        "${XO_OBJ_POOL[$d]}_move" "$d"
        if (( $? == 0 )) ; then alive_d+=("$d") ; else xo_obj_bury "$d" ; fi
    done
    DROPS=("${alive_d[@]}")

    local -a alive_w=()
    for w in "${WORDS[@]}" ; do
        "${XO_OBJ_POOL[$w]}_move" "$w"
        if (( $? == 0 )) ; then alive_w+=("$w") ; else xo_obj_bury "$w" ; fi
    done
    WORDS=("${alive_w[@]}")

    # ---- 5.5 扫描电网推进（每条波各自推进；同屏可多条）----
    # 本 tick 每条波"扫过"的行区间：不前进时就是当前行；前进时包含前后两行。
    # 必须按区间清弹：波向上、敌弹向下，同一 tick 里可能互相交换行而从未同格
    # （波 9→8、子弹 8→9），只比"行相等"会漏掉这种擦肩而过的子弹。
    if (( WAVE_ON )) ; then
        local -i _ws _wleft=0
        for (( _ws=0 ; _ws<WAVE_SLOTS ; _ws++ )) ; do
            (( WV_ON[_ws] )) || continue
            local -i _wy=${WV_Y[_ws]} _wdir=${WV_DIR[_ws]} _wcd=${WV_CD[_ws]}
            local -i _wlo=$_wy _whi=$_wy
            if (( ++_wcd >= WAVE_STEP_TICKS )) ; then
                _wcd=0
                local -i _wy_from=$_wy
                _wy=$(( _wy + _wdir ))
                if (( _wy < _wy_from )) ; then _wlo=$_wy ; _whi=$_wy_from
                else _wlo=$_wy_from ; _whi=$_wy ; fi
                if (( WV_OWNER[_ws] == 0 && ! WV_HIT[_ws] )) ; then
                    # Boss 的波：整架飞机（连护盾一起）都在扫描面上，站在逃生缝里就没事
                    local -i _wpy=${OBJ_player["{y}$X"]} _wph=${OBJ_player["{h}$X"]:-2}
                    local -i _wpx=${OBJ_player["{x}$X"]}
                    if (( _wy >= _wpy && _wy < _wpy + _wph )) && ! _wave_gap_x "$_ws" "$_wpx" ; then
                        WV_HIT[_ws]=1
                        G_WAVE_DMG_PENDING=$(( G_WAVE_DMG_PENDING + WV_DMG[_ws] ))
                    fi
                fi
                if (( _wy < GAME_TOP || _wy > SCREEN_H - 2 )) ; then
                    WV_ON[_ws]=0
                    continue
                fi
            fi
            WV_Y[_ws]=$_wy ; WV_CD[_ws]=$_wcd
            WV_CLEAR_LO[_ws]=$_wlo ; WV_CLEAR_HI[_ws]=$_whi
            ((_wleft++))
        done
        (( _wleft > 0 )) || WAVE_ON=0
    fi

    # ---- 5.6 电网清扫扫过的行区间里的子弹 ----
    # 每个 tick 都扫：波会在一行停留 WAVE_STEP_TICKS 个 tick，而敌弹是每 4 tick 才
    # 移动一格。只在"刚到达"那个 tick 检查会因节奏错拍漏掉大部分子弹。
    # 多条波同时扫时逐条处理：先被清掉的子弹会因为对象已出池而在下一条波里被跳过。
    if (( WAVE_ON )) ; then
        local -i _ws2
        for (( _ws2=0 ; _ws2<WAVE_SLOTS ; _ws2++ )) ; do
            (( WV_ON[_ws2] )) || continue
            if (( WV_OWNER[_ws2] == 0 )) ; then
                # Boss 的波：清我方子弹（这一行随后会被重画，不留残格）
                if (( ${#BULLETS[@]} )) ; then
                    local -a _wb_keep=()
                    local _wb
                    for _wb in "${BULLETS[@]}" ; do
                        [[ -n "$_wb" && -n "${XO_OBJ_POOL[$_wb]+_}" ]] || continue
                        local -n _wbb=$_wb
                        local -i _wby=${_wbb["{y}$X"]}
                        local -i _wbx=${_wbb["{x}$X"]}
                        if (( _wby >= WV_CLEAR_LO[_ws2] && _wby <= WV_CLEAR_HI[_ws2] )) && \
                           ! _wave_gap_x "$_ws2" "$_wbx" ; then
                            # 被电网扫掉：解聘（BULLETS 在循环后重建）
                            xo_obj_fire "$_wb"
                        else
                            _wb_keep+=("$_wb")
                        fi
                    done
                    BULLETS=("${_wb_keep[@]}")
                fi
            else
                # 我方的波：清敌方子弹 / 跟踪导弹
                if (( ${#ENEMY_BULLETS[@]} )) ; then
                    local -a _eb_keep=()
                    local _eb
                    for _eb in "${ENEMY_BULLETS[@]}" ; do
                        [[ -n "$_eb" && -n "${XO_OBJ_POOL[$_eb]+_}" ]] || continue
                        local -n _ebb=$_eb
                        local -i _eby=${_ebb["{y}$X"]}
                        if (( _eby >= WV_CLEAR_LO[_ws2] && _eby <= WV_CLEAR_HI[_ws2] )) ; then
                            _enemy_bullet_bury "$_eb"
                        else
                            _eb_keep+=("$_eb")
                        fi
                    done
                    ENEMY_BULLETS=("${_eb_keep[@]}")
                fi
            fi
        done
    fi

    # ---- 6. 敌人快照（几何/血量/奖励），供子弹、导弹、玩家碰撞共用 ----
    # 每 tick 只绑定每个敌人一次。旧实现每对 (子弹, 敌人) 都要
    # nameref 绑定 + 读 4 个字段；80 子弹 × 20 敌人时是 1600 次绑定、
    # 6400 次关联数组读取，是本 tick 最大的热点。
    local -a _eid=() _ex=() _ey=() _ew=() _eh=() _ehp=() _escore=() _eart=() _ecls=() _einv=()
    local -a _edead=()
    local -i _ne=0 _ndead=0 _j _r _newhp
    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
        local -n _e=$e
        _eid[_ne]=$e
        _ex[_ne]=${_e["{x}$X"]}
        _ey[_ne]=${_e["{y}$X"]}
        _ew[_ne]=${_e["{w}$X"]}
        _eh[_ne]=${_e["{h}$X"]}
        _ehp[_ne]=${_e["{hp}$X"]}
        _escore[_ne]=${_e["{score}$X"]}
        _eart[_ne]=${_e["{art}$X"]}
        _ecls[_ne]=${_e["{CLS}$X"]}
        _einv[_ne]=${_e["{inv_cd}$X"]:-0}
        ((_ne++))
    done

    # 行索引：敌人是稀疏的（最多 20 个，每个 2~5 行），把「敌人索引」
    # 按覆盖的屏幕行分桶。子弹/导弹只检查自己所在行的桶，
    # 每对检测只剩纯算术比较，不再遍历全部敌人。
    local -A _row_e=()
    for (( _j=0 ; _j<_ne ; _j++ )) ; do
        for (( _r=_ey[_j] ; _r<_ey[_j] + _eh[_j] ; _r++ )) ; do
            _row_e[$_r]+=" $_j"
        done
    done

    # ---- 7. 子弹 vs 敌人 ----
    # killed_b / killed_m 已在函数开头声明（第 5 段就会往里写标记）
    local -i score_gain=0

    for b in "${BULLETS[@]}" ; do
        [[ -n "${killed_b[$b]+_}" ]] && continue
        local -n _b=$b
        local bx=${_b["{x}$X"]} by=${_b["{y}$X"]}
        local -i bdmg=${_b["{damage}$X"]}

        for _j in ${_row_e[$by]:-} ; do
            (( _edead[_j] )) && continue
            if (( bx >= _ex[_j] && bx < _ex[_j] + _ew[_j] )) ; then
                local _fxcol="$C_ORANGE"
                if (( ${_einv[_j]:-0} > 0 )) ; then
                    bdmg=0
                    _fxcol="$C_CYAN"
                fi
                _newhp=$(( _ehp[_j] - bdmg ))
                _ehp[_j]=$_newhp
                killed_b[$b]=1
                _hit_fx_add "$by" "$bx" '*' "$_fxcol"
                if (( _newhp <= 0 )) ; then
                    _edead[_j]=1
                    ((_ndead++))
                    ((G_KILLS++))
                    score_gain=$(( score_gain + _escore[_j] * _score_pct / 100 ))
                    if Base_is_a "${_eid[_j]}" BossBase ; then
                        ((G_BOSS_KILLS++))
                        _boss_on_death "${_eid[_j]}" "${_ex[_j]}" "${_ey[_j]}" "${_ew[_j]}" "${_eh[_j]}" "${_eart[_j]}"
                    fi
                else
                    local -n _e=${_eid[_j]}
                    _e["{hp}$X"]=$_newhp
                fi
                break
            fi
        done
    done

    # ---- 8. 导弹 vs 敌人 ----
    for m in "${MISSILES[@]}" ; do
        [[ -n "${killed_m[$m]+_}" ]] && continue
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        local -n _m=$m
        local mx=${_m["{x}$X"]} my=${_m["{y}$X"]}
        local mdmg=${_m["{damage}$X"]}

        for _j in ${_row_e[$my]:-} ; do
            (( _edead[_j] )) && continue
            if (( mx >= _ex[_j] && mx < _ex[_j] + _ew[_j] )) ; then
                local -i _mdmg=$mdmg
                local _fxcol="$C_ORANGE"
                if (( ${_einv[_j]:-0} > 0 )) ; then
                    _mdmg=0
                    _fxcol="$C_CYAN"
                fi
                _newhp=$(( _ehp[_j] - _mdmg ))
                _ehp[_j]=$_newhp
                killed_m[$m]=1
                _hit_fx_add "$my" "$mx" '*' "$_fxcol"
                if (( _newhp <= 0 )) ; then
                    _edead[_j]=1
                    ((_ndead++))
                    ((G_KILLS++))
                    score_gain=$(( score_gain + _escore[_j] * _score_pct / 100 ))
                    if Base_is_a "${_eid[_j]}" BossBase ; then
                        ((G_BOSS_KILLS++))
                        _boss_on_death "${_eid[_j]}" "${_ex[_j]}" "${_ey[_j]}" "${_ew[_j]}" "${_eh[_j]}" "${_eart[_j]}"
                    fi
                else
                    local -n _e=${_eid[_j]}
                    _e["{hp}$X"]=$_newhp
                fi
                break
            fi
        done
    done

    # ---- 8.5 我方扫描电网 vs 敌人（同一敌人对同一条波只结算一次，且必须真的扫到它）----
    if (( WAVE_ON )) ; then
        local -i _ws3
        for (( _ws3=0 ; _ws3<WAVE_SLOTS ; _ws3++ )) ; do
            (( WV_ON[_ws3] && WV_OWNER[_ws3] == 1 )) || continue
            local -i _wy=${WV_Y[_ws3]}
            local _wj
            for _wj in ${_row_e[$_wy]:-} ; do
                (( _edead[_wj] )) && continue
                [[ -n "${WAVE_HIT_ENEMY["${_ws3}|${_eid[_wj]}"]+_}" ]] && continue
                WAVE_HIT_ENEMY["${_ws3}|${_eid[_wj]}"]=1
                local -i _wdmg=${WV_DMG[_ws3]}
                local _wcol="$C_GREEN"
                if (( ${_einv[_wj]:-0} > 0 )) ; then
                    _wdmg=0
                    _wcol="$C_CYAN"
                fi
                _ehp[_wj]=$(( _ehp[_wj] - _wdmg ))
                _hit_fx_add "$_wy" "$(( _ex[_wj] + _ew[_wj] / 2 ))" '*' "$_wcol"
                if (( _ehp[_wj] <= 0 )) ; then
                    _edead[_wj]=1
                    ((_ndead++))
                    ((G_KILLS++))
                    score_gain=$(( score_gain + _escore[_wj] * _score_pct / 100 ))
                    if Base_is_a "${_eid[_wj]}" BossBase ; then
                        ((G_BOSS_KILLS++))
                        _boss_on_death "${_eid[_wj]}" "${_ex[_wj]}" "${_ey[_wj]}" "${_ew[_wj]}" "${_eh[_wj]}" "${_eart[_wj]}"
                    fi
                else
                    local -n _we=${_eid[_wj]}
                    _we["{hp}$X"]=${_ehp[_wj]}
                fi
            done
        done
    fi

    # ---- 9. 清理被击中的子弹/导弹/敌人 ----
    if ((${#killed_b[@]})) ; then
        local -a nb=()
        for b in "${BULLETS[@]}" ; do
            if [[ -n "${killed_b[$b]+_}" ]] ; then
                [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
                xo_obj_fire "$b"
            else
                nb+=("$b")
            fi
        done
        BULLETS=("${nb[@]}")
    fi

    if ((${#killed_m[@]})) ; then
        local -a nm=()
        for m in "${MISSILES[@]}" ; do
            if [[ -n "${killed_m[$m]+_}" ]] ; then
                [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
                _missile_queue_trail_clear "$m"
                xo_obj_fire "$m"
            else
                nm+=("$m")
            fi
        done
        MISSILES=("${nm[@]}")
    fi

    # 敌人延迟到所有碰撞结束后统一 bury：快照数组在子弹/导弹/玩家
    # 三个阶段之间保持有效，_edead 就是「本 tick 已死」标记。
    if (( _ndead )) ; then
        local -a ne=()
        for (( _j=0 ; _j<_ne ; _j++ )) ; do
            if (( _edead[_j] )) ; then
                xo_obj_bury "${_eid[_j]}"
            else
                ne+=("${_eid[_j]}")
            fi
        done
        ENEMIES=("${ne[@]}")
    fi

    # ---- 9. 玩家受伤 ----
    local px=${OBJ_player["{x}$X"]} py=${OBJ_player["{y}$X"]}
    local -i player_dmg=0

    local _sh=$(( ${OBJ_player["{shield}$X"]:-0} ))
    local -i _shw=${OBJ_player["{shield_w}$X"]:-9}
    local -i _shh=${OBJ_player["{shield_h}$X"]:-3}
    local -i _sht=${OBJ_player["{shield_top}$X"]:--1}
    local _sx1=$(( px - _shw / 2 )) _sx2=$(( px + _shw / 2 ))
    local _sy1=$(( py + _sht ))
    local _sy2=$(( _sy1 + _shh - 1 ))

    local -a survive_eb=()
    for eb in "${ENEMY_BULLETS[@]}" ; do
        local -n _eb=$eb
        local _ebx=${_eb["{x}$X"]} _eby=${_eb["{y}$X"]}
        local -i _hit=0
        if (( _sh )) ; then
            (( _ebx >= _sx1 && _ebx <= _sx2 && _eby >= _sy1 && _eby <= _sy2 )) && _hit=1
        else
            (( _ebx == px && _eby == py )) && _hit=1
        fi
        if (( _hit )) ; then
            if (( _sh )) ; then
                _hit_fx_add "$_eby" "$_ebx" '*' "$C_GREEN"
            else
                _hit_fx_add "$_eby" "$_ebx" '*' "$C_RED"
            fi
            (( ! _sh )) && player_dmg=$(( player_dmg + ${_eb["{damage}$X"]} ))
            _enemy_bullet_bury "$eb"
        else
            survive_eb+=("$eb")
        fi
    done
    ENEMY_BULLETS=("${survive_eb[@]}")

    for (( _j=0 ; _j<_ne ; _j++ )) ; do
        (( _edead[_j] )) && continue
        (( px >= _ex[_j] && px < _ex[_j] + _ew[_j] &&
           py >= _ey[_j] && py < _ey[_j] + _eh[_j] )) && {
            player_dmg=$(( player_dmg + 3 ))
            _hit_fx_add "$py" "$px" '*' "$C_RED"
        }
    done

    # 撞击型飞机：M_Ram 在闪烁/受伤状态中提供额外撞击伤害
    local -i _has_ram=0
    if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && declare -F "${XO_OBJ_POOL[OBJ_player]}_ram_ready" >/dev/null 2>&1 ; then
        _has_ram=1
    fi
    local -A _ram_killed=()
    if (( _has_ram )) ; then
        for (( _j=0 ; _j<_ne ; _j++ )) ; do
            (( _edead[_j] )) && continue
            (( px >= _ex[_j] && px < _ex[_j] + _ew[_j] &&
               py >= _ey[_j] && py < _ey[_j] + _eh[_j] )) || continue
            if xo_call "OBJ_player" ram_ready ; then
                _ram_enemy "${_eid[_j]}" "${_ex[_j]}" "${_ey[_j]}" "${_ew[_j]}" "${_eh[_j]}" "${_eart[_j]}" && \
                    _ram_killed["${_eid[_j]}"]=1
            fi
        done
    fi
    if (( ${#_ram_killed[@]} )) ; then
        local -a _kept=()
        for e in "${ENEMIES[@]}" ; do
            [[ -n "${_ram_killed[$e]+_}" ]] && continue
            _kept+=("$e")
        done
        ENEMIES=("${_kept[@]}")
    fi

    # 扫描电网命中：无视护盾（命中时直接把护盾打掉），但仍受无敌帧保护。
    # G_WAVE_DMG_PENDING 是**本 tick 所有波的伤害合计**；同 tick 多条波命中会合并成
    # 一次结算，跨 tick 的命中则由无敌帧（blink）自然挡掉。
    if (( G_WAVE_DMG_PENDING > 0 )) ; then
        player_dmg=$(( player_dmg + G_WAVE_DMG_PENDING ))
    fi

    if (( player_dmg > 0 && G_INV == 0 )) ; then
        OBJ_player["{hp}$X"]=$(( ${OBJ_player["{hp}$X"]} - player_dmg ))
        xo_call "OBJ_player" blink_start
        G_INV=${OBJ_player["{blink}$X"]:-90}
        if (( G_WAVE_DMG_PENDING > 0 && BOSS_WAVE_STRIP_SHIELD )) ; then
            _plane_set_shield "OBJ_player" 0
        fi
        if (( ${OBJ_player["{lt}$X"]:-0} > 0 && ${OBJ_player["{lanes}$X"]:-0} > 0 )) ; then
            local _nl=$(( ${OBJ_player["{lanes}$X"]} - 1 ))
            OBJ_player["{lanes}$X"]=$_nl
            (( _nl == 0 )) && OBJ_player["{lt}$X"]=0
        fi
    fi
    G_WAVE_DMG_PENDING=0

    if (( score_gain > 0 )) ; then
        OBJ_player["{score}$X"]=$(( ${OBJ_player["{score}$X"]} + score_gain ))
    fi

    # ---- 10. 掉落物拾取 ----
    # 拾取用整架飞机的 art 包围盒；护盾形态用护盾 art 的包围盒。
    local -i _pick_al _pick_h _pick_top
    if (( _sh )) ; then
        _pick_al=$(( _shw / 2 )) ; _pick_h=$_shh ; _pick_top=$(( py + _sht ))
    else
        _pick_al=$(( ${OBJ_player["{w}$X"]:-3} / 2 )) ; _pick_h=${OBJ_player["{h}$X"]:-2} ; _pick_top=$py
    fi
    local _px1=$(( px - _pick_al )) _px2=$(( px + _pick_al ))
    local _py1=$_pick_top _py2=$(( _pick_top + _pick_h - 1 ))

    local -a survive_d2=()
    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        local -n _d=$d
        if (( ${_d["{x}$X"]} >= _px1 && ${_d["{x}$X"]} <= _px2 && \
              ${_d["{y}$X"]} >= _py1 && ${_d["{y}$X"]} <= _py2 )) ; then
            local dtype=${_d["{dtype}$X"]}
            xo_obj_bury "$d"
            case "$dtype" in
                2|3|4|5)
                    # 切换到本局该档位的武器对象；武器对象常驻，不销毁。
                    # dtype 现在直接对应 tier（2..5），t2..t5 一一对应。
                    local _wnew=${OBJ_player["{w$dtype}$X"]}
                    if [[ -n "$_wnew" && -n "${XO_OBJ_POOL[$_wnew]+_}" ]] ; then
                        OBJ_player["{t2}$X"]=0 ; OBJ_player["{t3}$X"]=0 ; OBJ_player["{t4}$X"]=0 ; OBJ_player["{t5}$X"]=0
                        OBJ_player["{bullet}$X"]=$_wnew
                        case "$dtype" in
                            2) OBJ_player["{t2}$X"]=$BONUS_T2 ;;
                            3) OBJ_player["{t3}$X"]=$BONUS_T3 ;;
                            4) OBJ_player["{t4}$X"]=$BONUS_T4 ;;
                            5) OBJ_player["{t5}$X"]=$BONUS_T5 ;;
                        esac
                    fi
                    ;;
                H)
                    OBJ_player["{hp}$X"]=$(( ${OBJ_player["{hp}$X"]} + 3 ))
                    (( ${OBJ_player["{hp}$X"]} > ${OBJ_player["{maxhp}$X"]:-20} )) && OBJ_player["{hp}$X"]=${OBJ_player["{maxhp}$X"]:-20}
                    ;;
                b)
                    if (( ${OBJ_player["{bombs}$X"]:-0} >= 5 )) ; then
                        # 满弹时再吃 b：直接引爆刚吃到的这一颗，不消耗库存
                        G_WANT_BOMB=1
                        G_FREE_BOMB=1
                    else
                        OBJ_player["{bombs}$X"]=$(( ${OBJ_player["{bombs}$X"]:-0} + 1 ))
                    fi
                    ;;
                m)
                    OBJ_player["{mt}$X"]=$BONUS_MT
                    ;;
                L)
                    local _cur_lanes=${OBJ_player["{lanes}$X"]:-0}
                    case "$_cur_lanes" in
                        0) OBJ_player["{lanes}$X"]=1 ; OBJ_player["{lanes_side}$X"]=$(( RANDOM % 2 )) ; OBJ_player["{lt}$X"]=$BONUS_LT ;;
                        1) OBJ_player["{lanes}$X"]=2 ; OBJ_player["{lt}$X"]=$BONUS_LT ;;
                        2) OBJ_player["{lanes}$X"]=3 ; OBJ_player["{lanes_side}$X"]=$(( RANDOM % 2 )) ; OBJ_player["{lt}$X"]=$BONUS_LT ;;
                        3) OBJ_player["{lanes}$X"]=4 ; OBJ_player["{lt}$X"]=$BONUS_LT ;;
                        *) OBJ_player["{lt}$X"]=$BONUS_LT ;;
                    esac
                    ;;
                S)
                    _plane_set_shield "OBJ_player" 1
                    ;;
                W)
                    # 我方扫描电网：捡到即发射，自下而上扫敌人
                    _wave_start 1 "$PLAYER_WAVE_DAMAGE"
                    ;;
            esac
        else
            survive_d2+=("$d")
        fi
    done
    DROPS=("${survive_d2[@]}")

    # ---- 10.5 单词拾取：碰到即消失并加分 ----
    local -a survive_w=()
    for w in "${WORDS[@]}" ; do
        [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
        local -n _w=$w
        local _wx=${_w["{x}$X"]} _wy=${_w["{y}$X"]} _wlen=${_w["{len}$X"]}
        if (( _wy >= _py1 && _wy <= _py2 && \
              _wx + _wlen - 1 >= _px1 && _wx <= _px2 )) ; then
            local _wscore=$(( _wlen * 10 * _score_pct / 100 ))
            OBJ_player["{score}$X"]=$(( ${OBJ_player["{score}$X"]} + _wscore ))
            xo_obj_bury "$w"
        else
            survive_w+=("$w")
        fi
    done
    WORDS=("${survive_w[@]}")

    # ---- 11. 死亡判定 ----
    local -i _hp_final=${OBJ_player["{hp}$X"]}
    (( _hp_final <= 0 )) && { G_GAME_OVER=1 ; return 0 ; }

    # ---- 12. 刷怪 ----
    if (( _ne > 0 && ${#ENEMIES[@]} == 0 )) && _clear_banner_ready ; then
        _score_bonus "$CLEAR_SCORE_BONUS"
        _clear_banner_start "YOU ARE AN ACE FIGHTER PILOT!  +${CLEAR_SCORE_BONUS}"
        G_LAST_ACE_TICK=$G_RUN_TICKS
    fi
    (( G_ENEMY_TICK++ % 30 == 0 )) && (( ${#ENEMIES[@]} < ENEMY_LIMIT )) && {
        local alive_B=0 alive_Boss=0
        for e in "${ENEMIES[@]}" ; do
            [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
            local -n _e=$e
            local _c=${_e["{CLS}$X"]}
            [[ "$_c" == "EnemyB" ]] && ((alive_B++))
            Base_is_a "$e" BossBase && ((alive_Boss++))
        done

        local spawn_cls=''
        local _r=$(( RANDOM % 1000 ))
        # Boss 战期间封锁所有新怪；只保留掉落物/飘字等非敌人内容。
        # 现有小怪不清理，Boss 死后本判定自然恢复。
        if (( alive_Boss >= BOSS_LIMIT )) ; then
            spawn_cls=''
            G_BOSS_DRY=0
        else
            if (( G_BOSS_DRY >= 300 )) ; then
                _boss_random_class ; spawn_cls=$REPLY ; G_BOSS_DRY=0
            elif (( G_B_DRY >= 30 && alive_B == 0 )) ; then
                spawn_cls=EnemyB ; G_B_DRY=0
            # 0/1 Boss 时：V38% / Q27% / M23% / B10% / Boss2%
            elif (( _r < 380 )) ; then spawn_cls=EnemyV
            elif (( _r < 650 )) ; then spawn_cls=EnemyQ
            elif (( _r < 880 )) ; then spawn_cls=EnemyM
            elif (( _r < 980 )) ; then spawn_cls=EnemyB
            else                       _boss_random_class ; spawn_cls=$REPLY
            fi
        fi

        if [[ -n "$spawn_cls" ]] ; then
            if [[ "$spawn_cls" == "Boss" || "$spawn_cls" == "BossSpinner" || "$spawn_cls" == "SkullKing" ]] ; then G_BOSS_DRY=0
            else ((G_BOSS_DRY++)) ; fi
            if [[ "$spawn_cls" == "EnemyB" ]] ; then G_B_DRY=0
            elif [[ "$spawn_cls" != "Boss" && "$spawn_cls" != "BossSpinner" && "$spawn_cls" != "SkullKing" ]] ; then ((G_B_DRY++)) ; fi

            xo_obj_born "$spawn_cls"
            ENEMIES+=("$REPLY")
        fi
    }

    # ---- 13. 刷掉落物 ----
    (( G_DROP_TICK++ % 100 == 0 )) && (( RANDOM % 100 < 60 )) && \
        (( ${#DROPS[@]} < DROP_LIMIT )) && {
        local _lanes_now=${OBJ_player["{lanes}$X"]:-0}
        local _drop_type=''
        local _r=$(( RANDOM % 100 ))
        _drop_pick_type "$_lanes_now" "$_r"
        _drop_type=$REPLY
        xo_obj_born Drop "$_drop_type"
        DROPS+=("$REPLY")
    }

    # ---- 14. 刷飘字 ----
    (( G_WORD_TICK++ % 250 == 0 )) && (( ${#WORDS[@]} < WORD_LIMIT )) && {
        local _wtext="${WORD_LIST[RANDOM % ${#WORD_LIST[@]}]}"
        local _ww
        str_display_width "$_wtext" _ww
        if (( _ww <= SCREEN_W - 4 )) ; then
            xo_obj_born Word "$_wtext"
            WORDS+=("$REPLY")
        fi
    }

    return 0
}

# ============================================================================
# play_game — 单局主循环（帧循环，输入/逻辑/渲染三频率独立）
# ============================================================================
play_game () {
    local key running=1
    local -i paused=0 paused_drawn=0
    local msg= msg_tick=0
    local -i bomb_fx_tick=0
    local -i hud_tick=0
    local last_bonus_str='__init__'
    # 注意：这里不能声明为 local -i。下面多处用 printf -v _t 写入 ANSI
    # 转义字符串，integer 属性会让 bash 把字符串当算术表达式求值并报错。
    local _t

    local LAST_US=${EPOCHREALTIME/./}
    local -i LOGIC_ACC_US=0
    local -i RENDER_ACC_US=$RENDER_US
    # 只有逻辑 tick 会改变场景；两个 tick 之间的重复渲染是纯浪费。
    # 需要重画时置 1（首次 / 每次 tick / load 后）。
    local -i need_render=1

    screen_clear
    _mouse_on
    FRAME_BUF=""
    draw_frame
    draw_hud_line2
    frame_flush

    while : ; do
        # ---- 采样时间，两个累加器独立 ----
        local NOW_US=${EPOCHREALTIME/./}
        local DELTA_US=$(( NOW_US - LAST_US ))
        LAST_US=$NOW_US
        (( DELTA_US > TICK_US * 5 )) && DELTA_US=$(( TICK_US * 5 ))
        LOGIC_ACC_US=$(( LOGIC_ACC_US + DELTA_US ))
        RENDER_ACC_US=$(( RENDER_ACC_US + DELTA_US ))

        # ---- 读输入（高频 100Hz）----
        G_DX=0 ; G_DY=0
        local -i paused_changed=0 _in_n=0
        while IFS= read -rsn1 -t 0.002 key ; do
            (( _in_n++ ))
            (( _in_n > 64 )) && break
            case "$key" in
                $'\e')
                    local _mseq='' _mc
                    while IFS= read -rsn1 -t 0.05 _mc ; do
                        _mseq+=$_mc
                        [[ "$_mc" == M || "$_mc" == m ]] && break
                    done
                    if (( G_MOUSE_ON && ! paused )) ; then
                        _mouse_apply "$_mseq"
                    fi
                    continue
                    ;;
                m|M)
                    ;;
                p|P)
                    if (( paused )) ; then
                        # 恢复游戏时保留 paused_drawn，让下面的清行逻辑擦掉 PAUSED 行
                        paused=0
                        msg="" ; msg_tick=0
                        need_render=1
                    else
                        paused=1
                        paused_drawn=0
                    fi
                    paused_changed=1
                    ;;
                q|Q) running=0 ; break ;;
                s|S)
                    if (( paused )) ; then
                        if save_game ; then msg="SAVED" ; else msg="SAVE FAILED" ; fi
                        msg_tick=50
                    else
                        G_DY=1
                    fi
                    ;;
                l|L)
                    if (( paused )) ; then
                        if load_game ; then
                            # 读档成功后立刻回到游戏，不再停在暂停画面
                            paused=0
                            paused_drawn=0
                            msg="" ; msg_tick=0
                            screen_clear
                            FRAME_BUF=""
                            draw_frame
                            draw_hud_line2
                            frame_flush
                            need_render=1
                            # 读档后屏幕已清空，强制下一帧重画 bonus 行，
                            # 否则 last_bonus_str 可能和读档前的值相同而跳过绘制。
                            last_bonus_str='__load__'
                        else
                            msg="LOAD FAILED"
                            msg_tick=50
                        fi
                    else
                        G_DX=1
                    fi
                    ;;
                a|A|h|H) (( paused )) || G_DX=-1 ;;
                d|D)     (( paused )) || G_DX=1  ;;
                w|W|k|K) (( paused )) || G_DY=-1 ;;
                j|J)     (( paused )) || G_DY=1  ;;
                y|Y)     (( paused )) || { G_DX=-1 ; G_DY=-1 ; } ;;
                u|U)     (( paused )) || { G_DX=1  ; G_DY=-1 ; } ;;
                b|B)     (( paused )) || { G_DX=-1 ; G_DY=1  ; } ;;
                n|N)     (( paused )) || { G_DX=1  ; G_DY=1  ; } ;;
                ' ')
                    if (( !paused )) ; then
                        (( ${OBJ_player["{bombs}$X"]:-0} > 0 )) && G_WANT_BOMB=1
                    fi
                    ;;
            esac
        done
        ((running)) || { _mouse_off ; return 1 ; }

        # ---- want_bomb ----
        if (( G_WANT_BOMB )) ; then
            G_WANT_BOMB=0
            if (( G_FREE_BOMB )) ; then
                G_FREE_BOMB=0
            else
                OBJ_player["{bombs}$X"]=$(( ${OBJ_player["{bombs}$X"]:-0} - 1 ))
            fi
            local _ceb
            for _ceb in "${ENEMY_BULLETS[@]}" ; do
                [[ -n "$_ceb" && -n "${XO_OBJ_POOL[$_ceb]+_}" ]] || continue
                _enemy_bullet_bury "$_ceb"
            done
            ENEMY_BULLETS=()

            local -a bomb_alive=()
            local -i bomb_score=0
            local -i _bomb_n=${#ENEMIES[@]}
            local -i _bomb_pct=100
            _bomb_pct=${OBJ_player["{score_pct}$X"]:-100}
            for e in "${ENEMIES[@]}" ; do
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local -i _bomb_dmg=$BOMB_DAMAGE
                if (( ${_e["{inv_cd}$X"]:-0} > 0 )) ; then
                    _bomb_dmg=0
                fi
                local new_hp=$(( ${_e["{hp}$X"]} - _bomb_dmg ))
                _e["{hp}$X"]=$new_hp
                local escore=${_e["{score}$X"]}
                local _ex=${_e["{x}$X"]} _ey=${_e["{y}$X"]}
                local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}
                local _eart=${_e["{art}$X"]}
                if (( new_hp <= 0 )) ; then
                    bomb_score=$(( bomb_score + escore * _bomb_pct / 100 ))
                    ((G_KILLS++))
                    if Base_is_a "$e" BossBase ; then
                        ((G_BOSS_KILLS++))
                        _boss_on_death "$e" "$_ex" "$_ey" "$_ew" "$_eh" "$_eart"
                    fi
                    xo_obj_bury "$e"
                else
                    bomb_alive+=("$e")
                fi
            done
            ENEMIES=("${bomb_alive[@]}")
            if (( _bomb_n > 0 && ${#ENEMIES[@]} == 0 )) && _clear_banner_ready ; then
                _score_bonus "$CLEAR_SCORE_BONUS"
                _clear_banner_start "YOU ARE AN ACE FIGHTER PILOT!  +${CLEAR_SCORE_BONUS}"
                G_LAST_ACE_TICK=$G_RUN_TICKS
            fi
            OBJ_player["{score}$X"]=$(( ${OBJ_player["{score}$X"]:-0} + bomb_score ))
            bomb_fx_tick=50
        fi

        # ---- 暂停 ----
        if (( paused )) ; then
            if (( !paused_drawn )) ; then
                local _s='PAUSED  (p=resume  q=quit  s=save  l=load)'
                local _maxw=$(( SCREEN_W - 2 ))
                _s="${_s:0:_maxw}"
                local _t
                printf -v _t '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
                paused_drawn=1
            fi
            if (( msg_tick > 0 )) ; then
                local _s="$msg"
                local _maxw=$(( SCREEN_W - 2 ))
                _s="${_s:0:_maxw}"
                local _t
                printf -v _t '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
                ((msg_tick--))
                if (( msg_tick == 0 )) ; then
                    local _t2
                    printf -v _t2 '\033[5;2H\033[K\033[5;%dH%s' "$SCREEN_W" "$FRAME_V"
                    FRAME_BUF+="$_t2"
                    paused_drawn=0
                fi
            fi
            frame_flush
            LOGIC_ACC_US=0
            continue
        fi
        if (( paused_drawn )) ; then
            local _t
            printf -v _t '\033[5;2H\033[K\033[5;%dH%s' "$SCREEN_W" "$FRAME_V"
            FRAME_BUF+="$_t"
            paused_drawn=0
        fi

        # ---- 逻辑 tick（独立频率）----
        while (( LOGIC_ACC_US >= TICK_US )) ; do
            LOGIC_ACC_US=$(( LOGIC_ACC_US - TICK_US ))
            _play_game_tick
            need_render=1
            (( G_GAME_OVER )) && break
        done

        # ---- 渲染帧（独立频率）----
        if (( RENDER_ACC_US >= RENDER_US )) ; then
            RENDER_ACC_US=$(( RENDER_ACC_US - RENDER_US ))

            # 场景与 HUD 的数值都只在 tick 后变化；没有 tick 时整块跳过，
            # 避免以 2 倍逻辑帧率做完全相同的重画。
            if (( need_render )) ; then
                if (( hud_tick % 3 == 0 )) ; then
                    draw_hud_line1
                fi
                ((hud_tick++))
                local _cbs="$(( ${OBJ_player["{t2}$X"]:-0} / FPS )) $(( ${OBJ_player["{t3}$X"]:-0} / FPS )) $(( ${OBJ_player["{t4}$X"]:-0} / FPS )) $(( ${OBJ_player["{t5}$X"]:-0} / FPS )) $(( ${OBJ_player["{mt}$X"]:-0} / FPS )) $(( ${OBJ_player["{lt}$X"]:-0} / FPS )) $(( ${OBJ_player["{st}$X"]:-0} / FPS )) ${OBJ_player["{lanes}$X"]:-0} $(( ${OBJ_player["{slow}$X"]:-0} / FPS ))"
                if [[ "$_cbs" != "$last_bonus_str" ]] ; then
                    draw_bonus_hud
                    last_bonus_str=$_cbs
                fi

                render_hit_fx_clear_expired
                render
                render_hit_fx
                need_render=0
            fi

            if (( msg_tick > 0 )) ; then
                local _s="$msg"
                local _maxw=$(( SCREEN_W - 2 ))
                _s="${_s:0:_maxw}"
                local _t
                printf -v _t '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
                ((msg_tick--))
                if (( msg_tick == 0 )) ; then
                    local _t2
                    printf -v _t2 '\033[5;2H\033[K\033[5;%dH%s' "$SCREEN_W" "$FRAME_V"
                    FRAME_BUF+="$_t2"
                fi
            fi

            if (( bomb_fx_tick > 0 )) ; then
                render_bomb_fx
                ((bomb_fx_tick--))
            elif (( ${#BOMB_FX_POS[@]} > 0 )) ; then
                local _bi _t
                for (( _bi=0; _bi<${#BOMB_FX_POS[@]}; _bi+=2 )) ; do
                    printf -v _t '\033[%d;%dH ' "${BOMB_FX_POS[_bi]}" "${BOMB_FX_POS[_bi+1]}"
                    FRAME_BUF+="$_t"
                done
                BOMB_FX_POS=()
            fi

            if (( BOSS_DEATH_TICK > 0 )) ; then
                render_boss_death
                ((BOSS_DEATH_TICK--))
            elif (( ${#BOSS_DEATH_POS[@]} > 0 )) ; then
                local _bi _t
                for (( _bi=0; _bi<${#BOSS_DEATH_POS[@]}; _bi+=2 )) ; do
                    printf -v _t '\033[%d;%dH ' "${BOSS_DEATH_POS[_bi]}" "${BOSS_DEATH_POS[_bi+1]}"
                    FRAME_BUF+="$_t"
                done
                BOSS_DEATH_POS=()
            fi

            (( CLEAR_BANNER_TICK > 0 )) && render_clear_banner

            frame_flush
        fi

        (( G_GAME_OVER )) && { _mouse_off ; return 0 ; }
    done
}
