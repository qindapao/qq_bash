# render/scene.sh — 主场景渲染（拼接 FRAME_BUF，不直接 printf）
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[scene]++ )) && return 0
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

# ASCII art 行缓存：art 字符串在一局内是稳定的（Boss 阶段切换会换新 art），
# 避免每帧重复做 %% 和 # 前缀截取。
declare -A _SCENE_ART_CACHE=()
_scene_art_lines () {
    local art=$1
    [[ -n "${_SCENE_ART_CACHE["$art|__n"]+_}" ]] && return 0
    local n=0 rest=$art line
    while [[ -n "$rest" ]] ; do
        line=${rest%%$'\n'*}
        if [[ "$rest" == *$'\n'* ]] ; then rest=${rest#*$'\n'} ; else rest='' ; fi
        _SCENE_ART_CACHE["$art|$n"]=$line
        ((n++))
    done
    _SCENE_ART_CACHE["$art|__n"]=$n
}

_scene_clear_art_at () {
    local ay=$1 ax=$2 art=$3
    _scene_art_lines "$art"
    local -i r=0 n=${_SCENE_ART_CACHE["$art|__n"]:-0} \
             _cy _cx _cw
    local line _buf='' _t
    while (( r < n )) ; do
        line=${_SCENE_ART_CACHE["$art|$r"]}
        _cy=$(( ay + r )) _cx=$ax _cw=${#line}
        # 夹到可玩区：art 贴边时不能擦到边框（每行两次比较）
        if (( _cx < 2 )) ; then
            _cw=$(( _cw - (2 - _cx) )) _cx=2
        fi
        (( _cx + _cw > SCREEN_W - 1 )) && _cw=$(( SCREEN_W - 1 - _cx ))
        if (( _cw > 0 )) ; then
            _buf+="$ESC[${_cy};${_cx}H${SPACE_PROTOTYPE_STRING:0:_cw}"
            # art 擦掉的格子里可能有掉落物/子弹：重新标脏，下一次 emit 补画回来
            _scene_erase_mark "$_cy" "$_cx" $(( _cx + _cw - 1 ))
        fi
        ((r++))
    done
    FRAME_BUF+="$_buf"
}

_render_erase_one () {
    local -i skip_static=${2:-0}
    local -n o=$1
    local px=${o[prev_x]:-${o[x]:-0}} py=${o[prev_y]:-${o[y]:-0}}
    # 帧缓冲：把属于它的格子清掉（用 owner 判定；未迁移的对象没有 owner，天然 no-op）
    local -i _fx _fy _fi
    for _fy in "$py" "${o[y]:-0}" ; do
        (( _fy >= 2 && _fy <= SCREEN_H - 2 )) || continue
        _fx=${o[x]:-0}
        (( _fx >= 2 && _fx <= SCREEN_W - 2 )) || continue
        _fi=$(( (_fy - 1) * FB_W + (_fx - 1) ))
        if [[ "${FB_OWNER[_fi]}" == "$1" ]] ; then
            FB_CELL[_fi]='' FB_OWNER[_fi]='' FB_DIRTY+=("$_fi")
        fi
        if [[ "${FB_DOWNER[_fi]}" == "$1" ]] ; then
            FB_DROP[_fi]='' FB_DOWNER[_fi]='' FB_DIRTY+=("$_fi")
        fi
    done

    # 新对象首帧 prev=(0,0)，跳过擦除
    if (( px == 0 && py == 0 )) ; then
        return 0
    fi

    # skip_static=1：位置没变时不必擦除，本帧的绘制会把这块重新盖住。
    # 但 art 形态也算"变"——护盾开关会换 art/宽度/行数（2 行变 3 行且上移 1 行），
    # 只比位置会漏擦，屏幕上留下旧护盾的轮廓。
    if (( skip_static )) && \
       (( px == ${o[x]:-0} && py == ${o[y]:-0} )) ; then
        if [[ -z "${o[prev_art]+_}" ]] \
           || [[ "${o[prev_art]}" == "${o[art]}" \
              && "${o[prev_al]}" == "${o[al]}" \
              && "${o[prev_shield]}" == "${o[shield]}" ]] ; then
            return 0
        fi
    fi

    local cls=${o["{CLS}$X"]} _t
    case "$cls" in
    Bullet|Missile|EnemyBullet|BossBullet|Drop)
        FRAME_BUF+="$ESC[${py};${px}H "
        ;;
    Plane|PlaneBee|PlaneHornet|PlaneEagle|PlaneIl2)
        local psh=${o[prev_shield]:-0} \
              pal=${o[prev_al]:-${o[al]:-1}} \
              part=${o[prev_art]:-${o[art]}} pay=$py
        (( psh )) && pay=$(( py + ${o[shield_top]:--1} ))
        _scene_clear_art_at "$pay" $(( px - pal )) "$part"
        ;;
    Word)
        local len=${o[len]:-0}
        local eff=$len
        (( px + eff > SCREEN_W - 1 )) && eff=$(( SCREEN_W - 1 - px ))
        (( eff < 0 )) && eff=0
        if (( eff > 0 )) ; then
            FRAME_BUF+="$ESC[${py};${px}H${SPACE_PROTOTYPE_STRING:0:eff}"
        fi
        ;;
    EnemyV|EnemyQ|EnemyM|EnemyB|Boss|BossSpinner|SkullKing)
        # 用上一帧的 art 擦除：Boss 换阶段/无头时，当前 art 可能比旧 art 窄，
        # 拿当前 art 去擦会留下旧头/旧腿的残影。
        local _old_art=${o[prev_art]:-${o[art]}}
        _scene_clear_art_at "$py" "$px" "$_old_art"
        local _bcls=${o["{CLS}$X"]}
        if [[ "$_bcls" == "Boss" ]] || [[ "$_bcls" == "BossSpinner" ]] \
           || [[ "$_bcls" == "SkullKing" ]] || [[ "$_bcls" == "EnemyB" ]] \
           || [[ "$_bcls" == "EnemyM" ]] ; then
            local _bh=${o[h]:-1}
            if (( py + _bh < SCREEN_H )) ; then
                # 整行擦除（\033[K）会抹掉这一行上的帧缓冲对象，擦完把它们的格子标脏补回
                FRAME_BUF+="$ESC[$((py + _bh));2H$ESC[K$ESC[$((py + _bh));${SCREEN_W}H$FRAME_V"
                _scene_erase_mark $((py + _bh)) 2 $(( SCREEN_W - 2 ))
            fi
        fi
        ;;
    esac
}

# 渲染层加载之后，Entity 系的退役钩子就是"擦掉最后画过的那一格"：
# 这里直接把 Entity_retire 定义成擦除实现（而不是 base_types.sh 里那个带
# declare -F 探测的版本）。好处是一次死亡少一次能力探测 + 一层转发。
# 纯 xo 测试环境不加载本文件，仍然走 base_types.sh 里的探测版。
Entity_retire () { _render_erase_one "$1" ; }

# ============================================================================
# 一帧内的"擦除区间"记录 + 统一补脏
#
# 擦 art / 电网行 / Boss 血条会把压在下面的帧缓冲对象（敌弹、我方子弹、掉落）
# 一起擦掉。旧做法每擦一行调一次 _fb_touch_row 逐格找回；实测单行成本 ≈ 83us
# 固定开销 + 29us/格（98 格就是 ~2.9ms）。行数一多（18 个小敌各 2 行、或 Boss
# 5 行）就非常贵。
#
# 现在：擦除时只记"行 + 列区间"，fb_emit 前做一次成本比较，选便宜的那条：
#   旧成本 ≈ 29*格子数 + 83*行数
#   新成本 ≈ 29*候选对象数 + 8*行数   （候选 = 活着的敌弹 + 我方子弹 + 掉落）
# 化简得"新更快"的条件：候选数 < 格子数 + 2.6*行数。系数由本机实测得出，
# 跨机器绝对值会变，但比例基本稳定；且该判断只在有擦除的帧做，静态帧零成本。
# ============================================================================
declare -gai _ER_MIN=() _ER_MAX=()
declare -gi _ER_CELLS=0 _ER_ROWS=0

# 记录一行被擦过的列区间（$1=行 $2=起始列 $3=结束列，含）
_scene_erase_mark () {
    local -i _r=$1
    (( _r >= 1 && _r <= SCREEN_H )) || return 0
    local -i _a=$2 _b=$3
    _ER_CELLS=$(( _ER_CELLS + _b - _a + 1 ))
    if (( ${_ER_MIN[_r]:--1} < 0 )) ; then
        _ER_MIN[_r]=$_a _ER_MAX[_r]=$_b
        _ER_ROWS=$(( _ER_ROWS + 1 ))
    else
        (( _a < _ER_MIN[_r] )) && _ER_MIN[_r]=$_a
        (( _b > _ER_MAX[_r] )) && _ER_MAX[_r]=$_b
    fi
    return 0
}

# 把被擦除区间盖住的存活帧缓冲对象补脏；按成本模型选"逐行 touch"或"一次扫描"
_scene_erase_refill () {
    (( _ER_ROWS )) || return 0
    local -i _i _y _x
    local -i _ncand=$(( EB_LIVE + ${#BULLETS[@]} + ${#DROPS[@]} ))
    # 新路径成本模型：候选数 < 格子数 + 2.6*行数 时才划算
    if (( _ncand * 5 >= _ER_CELLS * 5 + 13 * _ER_ROWS )) ; then
        local -i _r
        for _r in "${!_ER_MIN[@]}" ; do
            _fb_touch_row "$_r" "${_ER_MIN[_r]}" "${_ER_MAX[_r]}"
        done
        return 0
    fi
    # 敌弹（SoA：槽位可能为空，先判 ALIVE）
    for (( _i=0 ; _i<EB_N ; _i++ )) ; do
        (( EB_ALIVE[_i] )) || continue
        _y=${EB_Y[_i]}
        (( ${_ER_MIN[_y]:--1} < 0 )) && continue
        _x=${EB_X[_i]}
        (( _x >= _ER_MIN[_y] && _x <= _ER_MAX[_y] )) || continue
        FB_DIRTY+=( $(( (_y - 1) * FB_W + (_x - 1) )) )
    done
    # 我方子弹（对象层）
    local _pb
    for _pb in "${BULLETS[@]}" ; do
        [[ -n "${XO_OBJ_POOL[$_pb]+_}" ]] || continue
        local -n _rpb=$_pb
        _y=${_rpb[y]} _x=${_rpb[x]}
        (( ${_ER_MIN[_y]:--1} < 0 )) && continue
        (( _x >= _ER_MIN[_y] && _x <= _ER_MAX[_y] )) || continue
        FB_DIRTY+=( $(( (_y - 1) * FB_W + (_x - 1) )) )
    done
    # 掉落物
    local _pd
    for _pd in "${DROPS[@]}" ; do
        [[ -n "${XO_OBJ_POOL[$_pd]+_}" ]] || continue
        local -n _rpd=$_pd
        _y=${_rpd[y]} _x=${_rpd[x]}
        (( ${_ER_MIN[_y]:--1} < 0 )) && continue
        (( _x >= _ER_MIN[_y] && _x <= _ER_MAX[_y] )) || continue
        FB_DIRTY+=( $(( (_y - 1) * FB_W + (_x - 1) )) )
    done
    return 0
}

render () {
    local b e d eb m w _t _WSP _ex _ey
    # 本帧的擦除区间记录（无擦除的静态帧保持为空，补脏函数直接返回）
    _ER_MIN=() _ER_MAX=() _ER_CELLS=0 _ER_ROWS=0
    # 擦行用的行尾填充串只与屏幕宽度有关：每帧算一次，别在逐对象循环里 printf %*s
    # 电网从第 3 列开始画、宽度 SCREEN_W-4，所以擦除也用它（左右各留 1 格，对称）
    _WSP=${SPACE_PROTOTYPE_STRING:0:SCREEN_W-4}
    local -i _qi _ptx _pty

    # 已死亡导弹（玩家 / 敌方跟踪弹）的最后一格，由 tick 侧排队，这里统一擦除。
    # 画面中间死亡的弹不会再从 ENEMY_BULLETS 里被擦除，所以必须在这里补一刀。
    for (( _qi=0; _qi<${#MISSILE_TRAIL_CLEAR[@]}; _qi+=2 )) ; do
        printf -v _t '\033[%d;%dH ' "${MISSILE_TRAIL_CLEAR[_qi]}" "${MISSILE_TRAIL_CLEAR[_qi+1]}"
        FRAME_BUF+="$_t"
    done
    MISSILE_TRAIL_CLEAR=()

    # 闪烁隐藏的帧机体不会被重绘，那几帧必须照常擦除，所以先取可见性
    local _blink_visible=1
    "${XO_OBJ_POOL[OBJ_player]}_blink_visible" "OBJ_player" || _blink_visible=0

    # ===== 阶段 1：擦除所有活对象的 prev =====
    # 玩家静止且形态未变时可跳过擦除（本帧重绘会覆盖同样格子），省一半写入
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && \
        _render_erase_one "OBJ_player" "$_blink_visible"
    # 单字符对象（导弹/敌弹/掉落）数量较多，内联擦除，
    # 省掉每个对象一次函数调用 + 一次 {CLS} 读取 + case 分派。
    # 我方子弹已迁移到帧缓冲：擦除/绘制都在 tick 和 fb_emit 里，这里不再遍历。
    for m in "${MISSILES[@]}" ; do
        local -n _m=$m
        _ex=${_m[prev_x]:-${_m[x]:-0}} \
        _ey=${_m[prev_y]:-${_m[y]:-0}}
        if (( _ex || _ey )) ; then
            FRAME_BUF+="$ESC[${_ey};${_ex}H "
        fi
        _ptx=${_m[prev_trail_x]:--1} \
        _pty=${_m[prev_trail_y]:--1}
        if (( _ptx >= 0 && _pty >= 0 )) ; then
            FRAME_BUF+="$ESC[${_pty};${_ptx}H "
        fi
    done
    for e in "${ENEMIES[@]}" ; do
        local -n _ep=$e
        local -i _epx=${_ep[x]} _epy=${_ep[y]} \
                 _epvx=${_ep[prev_x]:-0} _epvy=${_ep[prev_y]:-0}
        local _epart=${_ep[art]} _epart0=${_ep[prev_art]-}
        # 位置和 art 都没变：这一帧不用擦——阶段 2 会把同一批格子原样重画一遍。
        # 擦除只在"敌人移动/换 art"时才有意义，静态敌人每帧擦一遍纯属浪费。
        if (( _epx == _epvx && _epy == _epvy )) && [[ "$_epart" == "$_epart0" ]] ; then
            continue
        fi
        _render_erase_one "$e"
    done
    # 掉落物已迁移到帧缓冲（顶层 emit），这里不再擦除。
    for w in "${WORDS[@]}" ; do
        _render_erase_one "$w" 1
    done

    # ===== 扫描电网（同屏可多条）=====
    # 画在对象之前，避免遮住子弹和敌人（对象随后会覆盖它）。
    # 两趟：先擦所有波走过的旧行，再画所有当前行 —— 否则后一条波的擦除会把
    # 前一条刚画好的行抹掉（两条波可能同处一行）。
    if (( WAVE_ON )) ; then
        local -i _ws
        for (( _ws=0 ; _ws<WAVE_SLOTS ; _ws++ )) ; do
            (( WV_ON[_ws] )) || continue
            local -i _ly=${WV_LAST_Y[_ws]:--1}
            # 只在可玩区内擦：波可能从 GAME_TOP 之上起步，别把 HUD 行擦出缺口
            if (( _ly >= GAME_TOP && _ly != WV_Y[_ws] )) ; then
                FRAME_BUF+="$ESC[${_ly};3H$_WSP"
                # 整行擦过：这一行里帧缓冲对象（掉落/敌弹）的格子要补回来
                _scene_erase_mark "$_ly" 3 $(( SCREEN_W - 2 ))
            fi
            WV_LAST_Y[_ws]=-1
        done
        for (( _ws=0 ; _ws<WAVE_SLOTS ; _ws++ )) ; do
            (( WV_ON[_ws] )) || continue
            WV_LAST_Y[_ws]=-1
        done
    else
        # 波已全部结束：把每条波最后画过的行擦掉，否则会留在画面上
        for (( _ws=0 ; _ws<WAVE_SLOTS ; _ws++ )) ; do
            local -i _ly=${WV_LAST_Y[_ws]:--1}
            (( _ly >= GAME_TOP )) || continue
            FRAME_BUF+="$ESC[${_ly};3H$_WSP"
            _scene_erase_mark "$_ly" 3 $(( SCREEN_W - 2 ))
            WV_LAST_Y[_ws]=-1
        done
    fi

    # ===== 阶段 2：绘制所有活对象的 cur =====
    # 玩家放在阶段 2 最后画（见函数末尾）。子弹出生点就在机体上方（护盾时正是
    # 顶罩那一行），机翼又不是判定点，先画玩家会让这些对象反复盖住机体 → 闪烁。
    # 我方子弹已迁移到帧缓冲：tick 里写格子，fb_emit 统一输出。
    for m in "${MISSILES[@]}" ; do
        local -n _m=$m
        local _mx=${_m[x]} _my=${_m[y]} _msym=${_m[symbol]} \
              _ptx=${_m[prev_x]:-} _pty=${_m[prev_y]:-}
        if [[ -n "$_ptx" && -n "$_pty" ]] && (( _ptx >= 2 && _pty >= 2 )) \
           && (( _ptx != _mx || _pty != _my )) ; then
            FRAME_BUF+="$ESC[${_pty};${_ptx}H$C_PLAYER_BULLET.$C_RESET"
            _m[prev_trail_x]=$_ptx \
            _m[prev_trail_y]=$_pty
        fi
        FRAME_BUF+="$ESC[${_my};${_mx}H$C_PLAYER_BULLET$_msym$C_RESET"
        _m[prev_x]=$_mx _m[prev_y]=$_my
    done

    # ===== 帧缓冲：输出本帧变过的格子（敌方子弹 / 导弹）=====
    # 位置必须和旧顺序一致：我方子弹 → 导弹 → 敌弹 → 敌人 art。
    # 放在这里（导弹之后、art 之前），后画的 art 仍然覆盖敌弹，和我们迁移前一致。
    # 已知边界：Boss 换形态时阶段 2 会清一次旧 art（_scene_clear_art_at），
    # 如果敌弹正好停在旧 art 区域，那一格会被擦掉，等它下次移动（≤3 tick）自动补回。
    _scene_erase_refill
    fb_emit

    for e in "${ENEMIES[@]}" ; do
        local -n _e=$e
        local _cls=${_e["{CLS}$X"]} _color=''
        case "$_cls" in
            Boss|EnemyB) _color=$C_RED ;;
            BossSpinner) _color=$C_PURPLE ;;
            SkullKing)   _color=$C_RED ;;
            EnemyM)      _color=$C_ORANGE ;;
            EnemyQ)      _color=$C_YELLOW ;;
            EnemyV)      _color=$C_GREEN ;;
        esac
        if [[ "$_cls" == "Boss" || "$_cls" == "BossSpinner" || "$_cls" == "SkullKing" ]] && \
           (( ${_e[inv_cd]:-0} > 0 )) ; then
            _color=$C_CYAN
        fi
        local _ay=${_e[y]} _ax=${_e[x]} _h=${_e[h]} \
              _hp2=${_e[hp]} _maxhp=${_e[maxhp]} _art=${_e[art]}
        _scene_art_lines "$_art"
        local -i _r=0 _rn=${_SCENE_ART_CACHE["$_art|__n"]:-0} _cy _cx _cw
        while (( _r < _rn )) ; do
            local _line=${_SCENE_ART_CACHE["$_art|$_r"]}
            FRAME_BUF+="$ESC[$((_ay + _r));${_ax}H$_color$_line$C_RESET"
            ((_r++))
        done
        if [[ "$_cls" == "Boss" ]] || [[ "$_cls" == "BossSpinner" ]] \
           || [[ "$_cls" == "SkullKing" ]] || [[ "$_cls" == "EnemyB" ]] \
           || [[ "$_cls" == "EnemyM" ]] ; then
            if (( _ay + _h < SCREEN_H )) ; then
                # 动态增益标签挂在 HP 行尾（非 Boss 没有这个字段，读出来是空）
                local _buff=''
                [[ -n "${_e[buff_str]-}" ]] && _buff=" ${_e[buff_str]}"
                printf -v _t '\033[%d;%dH\033[K%s[%d/%d]%s%s\033[%d;%dH%s' $((_ay + _h)) "$_ax" \
                    "$_color" "$_hp2" "$_maxhp" "$C_RESET" "$_buff" $((_ay + _h)) "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
            fi
        fi
        _e[prev_x]=$_ax \
        _e[prev_y]=$_ay \
        _e[prev_art]=$_art
    done

    # ===== 帧缓冲（顶层）：掉落物在敌人 art 之后、飘字之前输出 =====
    # 旧渲染顺序如此：掉落物画在 art 之上、飘字之下，迁移后必须保持。
    fb_emit_top

    for w in "${WORDS[@]}" ; do
        local -n _w=$w
        local _wx=${_w[x]} _wy=${_w[y]} _wtxt=${_w[text]}
        FRAME_BUF+="$ESC[${_wy};${_wx}H$C_CYAN$_wtxt$C_RESET"
        _w[prev_x]=$_wx _w[prev_y]=$_wy
    done

    # ===== 阶段 3：玩家最后画（层级最高）=====
    # 玩家先画会被自己的子弹（出生点在 y-1，护盾时正压顶罩）和敌弹（机翼不是
    # 判定点，会飞过机翼）覆盖，表现为机体/护盾反复被遮住。放最后即不再被遮。
    local _hp=${OBJ_player[hp]:-0} _maxhp=${OBJ_player[maxhp]:-20} _ph=''
    if (( _hp >= _maxhp )) ; then _ph="${C_BLUE}${C_BOLD}"
    elif (( _hp * 2 < _maxhp )) ; then _ph="${C_RED}${C_BOLD}"
    else _ph="${C_FG_DEFAULT}${C_BOLD}"
    fi
    local _green_bold="${C_GREEN}${C_BOLD}"

    # 独立的赋值合成一条（每条 local 约 3µs）；有依赖的必须另起一条——
    # bash 先把整条命令的字展开再赋值，同一条里的后半段看不到前半段。
    local _px=${OBJ_player[x]} _py=${OBJ_player[y]} \
          _part=${OBJ_player[art]} \
          _al=${OBJ_player[al]:-1} \
          _bal=${OBJ_player[base_al]:-1} \
          _sht=${OBJ_player[shield_top]:--1} \
          _sh=${OBJ_player[shield]:-0}
    local _pax=$(( _px - _al )) _pay=$_py
    (( _sh )) && _pay=$(( _pay + _sht ))
    _scene_art_lines "$_part"
    local -i _pr=0 _pn=${_SCENE_ART_CACHE["$_part|__n"]:-0}
    while (( _pr < _pn )) ; do
        local _pline=${_SCENE_ART_CACHE["$_part|$_pr"]} _out='' _cur_clr='' _c _i _want
        local -i _start=-1 _col
        for (( _i=0 ; _i<${#_pline} ; _i++ )) ; do
            _c=${_pline:_i:1}
            # 夹到可玩区：飞机贴边时不能盖住边框
            _col=$(( _pax + _i ))
            (( _col < 2 || _col > SCREEN_W - 1 )) && continue
            (( _start < 0 )) && _start=$_col
            if [[ "$_c" == " " ]] ; then
                _out+=' '
                continue
            fi
            if (( _sh )) ; then
                # 护盾描边统一绿色；机体和尾翼仍用飞机血量颜色
                if (( _pr == 2 )) ; then
                    _want=$_ph
                elif (( _pr == 1 && _i >= _al - _bal && _i <= _al + _bal )) ; then
                    _want=$_ph
                else
                    _want=$_green_bold
                fi
            else
                _want=$_ph
            fi
            if [[ "$_want" != "$_cur_clr" ]] ; then
                _out+="$_want"
                _cur_clr=$_want
            fi
            _out+="$_c"
        done
        _out+="$C_RESET"
        (( _start < 0 )) && { ((_pr++)) ; continue ; }
        (( _blink_visible )) && FRAME_BUF+="$ESC[$((_pay + _pr));${_start}H$_out"
        ((_pr++))
    done
    OBJ_player[prev_x]=$_px \
    OBJ_player[prev_y]=$_py \
    OBJ_player[prev_art]=$_part \
    OBJ_player[prev_al]=$_al \
    OBJ_player[prev_shield]=$_sh

    # ===== 电网：覆盖层，玩家要能看清缺口在哪 =====
    # 擦除在阶段 1 已经做完了，这里只负责把当前行盖上去。
    if (( WAVE_ON )) ; then
        local -i _ws
        for (( _ws=0 ; _ws<WAVE_SLOTS ; _ws++ )) ; do
            (( WV_ON[_ws] )) || continue
            FRAME_BUF+="$ESC[${WV_Y[_ws]};3H${WV_CLR[_ws]}${WV_LINE[_ws]}$C_RESET"
            WV_LAST_Y[_ws]=${WV_Y[_ws]}
        done
    fi

    # ===== 命中火花：最上层 =====
    # 必须画在 fb_emit / art / 玩家之后：子弹被打掉时它的帧缓冲格会被清空并标脏，
    # 玩家的 art 也会盖住护盾命中点；放在最后才不会被同一帧的任何写入覆盖。
    # 擦除在 render 之前（render_hit_fx_clear_expired），会 _fb_touch_cell 补回
    # 被火花盖住的对象/art，所以不会留下"洞"。
    render_hit_fx

}

