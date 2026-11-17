# render/scene.sh — 主场景渲染（拼接 FRAME_BUF，不直接 printf）
[[ -n "${_STRAFE_SCENE_SH:-}" ]] && return 0
_STRAFE_SCENE_SH=1
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
    local -i r=0 n=${_SCENE_ART_CACHE["$art|__n"]:-0}
    local line _buf='' _t
    while (( r < n )) ; do
        line=${_SCENE_ART_CACHE["$art|$r"]}
        printf -v _t '\033[%d;%dH%*s' $((ay + r)) "$ax" "${#line}" ''
        _buf+=$_t
        ((r++))
    done
    FRAME_BUF+="$_buf"
}

_render_erase_one () {
    local -i skip_static=${2:-0}
    local -n o=$1
    local px=${o["{prev_x}$X"]:-${o["{x}$X"]:-0}}
    local py=${o["{prev_y}$X"]:-${o["{y}$X"]:-0}}

    # 新对象首帧 prev=(0,0)，跳过擦除
    if (( px == 0 && py == 0 )) ; then
        return 0
    fi

    # skip_static=1：位置没变时不必擦除，本帧的绘制会把这块重新盖住。
    # 但 art 形态也算"变"——护盾开关会换 art/宽度/行数（2 行变 3 行且上移 1 行），
    # 只比位置会漏擦，屏幕上留下旧护盾的轮廓。
    if (( skip_static )) && \
       (( px == ${o["{x}$X"]:-0} && py == ${o["{y}$X"]:-0} )) ; then
        if [[ -z "${o[{prev_art}$X]+_}" ]] \
           || [[ "${o[{prev_art}$X]}" == "${o[{art}$X]}" \
              && "${o[{prev_al}$X]}" == "${o[{al}$X]}" \
              && "${o[{prev_shield}$X]}" == "${o[{shield}$X]}" ]] ; then
            return 0
        fi
    fi

    local cls=${o["{CLS}$X"]}
    local _t
    case "$cls" in
    Bullet|Missile|EnemyBullet|BossBullet|Drop)
        printf -v _t '\033[%d;%dH ' "$py" "$px"
        FRAME_BUF+="$_t"
        ;;
    Plane|PlaneBee|PlaneHornet|PlaneEagle|PlaneIl2)
        local psh=${o["{prev_shield}$X"]:-0}
        local pal=${o["{prev_al}$X"]:-${o["{al}$X"]:-1}}
        local part=${o["{prev_art}$X"]:-${o["{art}$X"]}}
        local pay=$py
        (( psh )) && pay=$(( py + ${o["{shield_top}$X"]:--1} ))
        _scene_clear_art_at "$pay" $(( px - pal )) "$part"
        ;;
    Word)
        local len=${o["{len}$X"]:-0}
        local eff=$len
        (( px + eff > SCREEN_W - 1 )) && eff=$(( SCREEN_W - 1 - px ))
        (( eff < 0 )) && eff=0
        if (( eff > 0 )) ; then
            printf -v _t '\033[%d;%dH%*s' "$py" "$px" "$eff" ''
            FRAME_BUF+="$_t"
        fi
        ;;
    EnemyV|EnemyQ|EnemyM|EnemyB|Boss|BossSpinner|SkullKing)
        # 用上一帧的 art 擦除：Boss 换阶段/无头时，当前 art 可能比旧 art 窄，
        # 拿当前 art 去擦会留下旧头/旧腿的残影。
        local _old_art=${o["{prev_art}$X"]:-${o["{art}$X"]}}
        _scene_clear_art_at "$py" "$px" "$_old_art"
        local _bcls=${o["{CLS}$X"]}
        if [[ "$_bcls" == "Boss" ]] || [[ "$_bcls" == "BossSpinner" ]] || [[ "$_bcls" == "SkullKing" ]] || [[ "$_bcls" == "EnemyB" ]] || [[ "$_bcls" == "EnemyM" ]] ; then
            local _bh=${o["{h}$X"]:-1}
            if (( py + _bh < SCREEN_H )) ; then
                printf -v _t '\033[%d;2H\033[K\033[%d;%dH%s' $((py + _bh)) $((py + _bh)) "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
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

render () {
    local b e d eb m w _t
    local _ex _ey
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
    xo_call "OBJ_player" blink_visible || _blink_visible=0

    # ===== 阶段 1：擦除所有活对象的 prev =====
    # 玩家静止且形态未变时可跳过擦除（本帧重绘会覆盖同样格子），省一半写入
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && \
        _render_erase_one "OBJ_player" "$_blink_visible"
    # 单字符对象（子弹/导弹/敌弹/掉落）数量最多，内联擦除，
    # 省掉每个对象一次函数调用 + 一次 {CLS} 读取 + case 分派。
    for b in "${BULLETS[@]}" ; do
        [[ -n "$b" ]] || continue
        local -n _b=$b
        _ex=${_b["{prev_x}$X"]:-${_b["{x}$X"]:-0}}
        _ey=${_b["{prev_y}$X"]:-${_b["{y}$X"]:-0}}
        if (( _ex || _ey )) ; then
            printf -v _t '\033[%d;%dH ' "$_ey" "$_ex"
            FRAME_BUF+="$_t"
        fi
    done
    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" ]] || continue
        local -n _m=$m
        _ex=${_m["{prev_x}$X"]:-${_m["{x}$X"]:-0}}
        _ey=${_m["{prev_y}$X"]:-${_m["{y}$X"]:-0}}
        if (( _ex || _ey )) ; then
            printf -v _t '\033[%d;%dH ' "$_ey" "$_ex"
            FRAME_BUF+="$_t"
        fi
        _ptx=${_m["{prev_trail_x}$X"]:--1}
        _pty=${_m["{prev_trail_y}$X"]:--1}
        if (( _ptx >= 0 && _pty >= 0 )) ; then
            printf -v _t '\033[%d;%dH ' "$_pty" "$_ptx"
            FRAME_BUF+="$_t"
        fi
    done
    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" ]] || continue
        local -n _eb=$eb
        _ex=${_eb["{prev_x}$X"]:-${_eb["{x}$X"]:-0}}
        _ey=${_eb["{prev_y}$X"]:-${_eb["{y}$X"]:-0}}
        if (( _ex == ${_eb["{x}$X"]:-0} && _ey == ${_eb["{y}$X"]:-0} )) ; then
            continue
        fi
        if (( _ex || _ey )) ; then
            printf -v _t '\033[%d;%dH ' "$_ey" "$_ex"
            FRAME_BUF+="$_t"
        fi
    done
    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" ]] || continue
        # 注意：不能对 Boss/EnemyB/EnemyM 跳过擦除，它们的擦除还要顺带
        # 清空整条血条行（\033[%d;2H\033[K）；跳过会留下上一帧的残影。
        _render_erase_one "$e"
    done
    for d in "${DROPS[@]}" ; do
        [[ -n "$d" ]] || continue
        local -n _d=$d
        _ex=${_d["{prev_x}$X"]:-${_d["{x}$X"]:-0}}
        _ey=${_d["{prev_y}$X"]:-${_d["{y}$X"]:-0}}
        if (( _ex == ${_d["{x}$X"]:-0} && _ey == ${_d["{y}$X"]:-0} )) ; then
            continue
        fi
        if (( _ex || _ey )) ; then
            printf -v _t '\033[%d;%dH ' "$_ey" "$_ex"
            FRAME_BUF+="$_t"
        fi
    done
    for w in "${WORDS[@]}" ; do
        [[ -n "$w" ]] || continue
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
            if (( _ly >= 0 && _ly != WV_Y[_ws] )) ; then
                printf -v _t '\033[%d;2H%*s' "$_ly" "$(( SCREEN_W - 3 ))" ''
                FRAME_BUF+="$_t"
            fi
            WV_LAST_Y[_ws]=-1
        done
        for (( _ws=0 ; _ws<WAVE_SLOTS ; _ws++ )) ; do
            (( WV_ON[_ws] )) || continue
            printf -v _t '\033[%d;2H%s%s%s' "${WV_Y[_ws]}" "${WV_CLR[_ws]}" "${WV_LINE[_ws]}" "$C_RESET"
            FRAME_BUF+="$_t"
            WV_LAST_Y[_ws]=${WV_Y[_ws]}
        done
    else
        # 波已全部结束：把每条波最后画过的行擦掉，否则会留在画面上
        for (( _ws=0 ; _ws<WAVE_SLOTS ; _ws++ )) ; do
            local -i _ly=${WV_LAST_Y[_ws]:--1}
            (( _ly >= 0 )) || continue
            printf -v _t '\033[%d;2H%*s' "$_ly" "$(( SCREEN_W - 3 ))" ''
            FRAME_BUF+="$_t"
            WV_LAST_Y[_ws]=-1
        done
    fi

    # ===== 阶段 2：绘制所有活对象的 cur =====
    # 玩家放在阶段 2 最后画（见函数末尾）。子弹出生点就在机体上方（护盾时正是
    # 顶罩那一行），机翼又不是判定点，先画玩家会让这些对象反复盖住机体 → 闪烁。
    if (( ${#BULLETS[@]} )) ; then
        for b in "${BULLETS[@]}" ; do
            [[ -n "$b" ]] || continue
            local -n _b=$b
            local _bx=${_b["{x}$X"]} _by=${_b["{y}$X"]} _bsym=${_b["{symbol}$X"]}
            # {color} 为空就用玩家的统一弹色；激光按威力写了自己的颜色
            local _bclr=${_b["{color}$X"]:-$C_PLAYER_BULLET}
            printf -v _t '\033[%d;%dH%s%s%s' "$_by" "$_bx" "$_bclr" "$_bsym" "$C_RESET"
            FRAME_BUF+="$_t"
            _b["{prev_x}$X"]=$_bx
            _b["{prev_y}$X"]=$_by
        done
    fi

    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" ]] || continue
        local -n _m=$m
        local _mx=${_m["{x}$X"]} _my=${_m["{y}$X"]} _msym=${_m["{symbol}$X"]}
        local _ptx=${_m["{prev_x}$X"]:-} _pty=${_m["{prev_y}$X"]:-}
        if [[ -n "$_ptx" && -n "$_pty" ]] && (( _ptx != _mx || _pty != _my )) ; then
            printf -v _t '\033[%d;%dH%s.%s' "$_pty" "$_ptx" "$C_PLAYER_BULLET" "$C_RESET"
            FRAME_BUF+="$_t"
            _m["{prev_trail_x}$X"]=$_ptx
            _m["{prev_trail_y}$X"]=$_pty
        fi
        printf -v _t '\033[%d;%dH%s%s%s' "$_my" "$_mx" "$C_PLAYER_BULLET" "$_msym" "$C_RESET"
        FRAME_BUF+="$_t"
        _m["{prev_x}$X"]=$_mx
        _m["{prev_y}$X"]=$_my
    done

    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" ]] || continue
        local -n _eb=$eb
        local _ebx=${_eb["{x}$X"]} _eby=${_eb["{y}$X"]} _ebsym=${_eb["{symbol}$X"]}
        local _ebcol=${_eb["{color}$X"]:-}
        if [[ -n "$_ebcol" ]] ; then
            printf -v _t '\033[%d;%dH%s%s%s' "$_eby" "$_ebx" "$_ebcol" "$_ebsym" "$C_RESET"
        else
            printf -v _t '\033[%d;%dH%s' "$_eby" "$_ebx" "$_ebsym"
        fi
        FRAME_BUF+="$_t"
        _eb["{prev_x}$X"]=$_ebx
        _eb["{prev_y}$X"]=$_eby
    done

    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" ]] || continue
        local -n _e=$e
        local _cls=${_e["{CLS}$X"]}
        local _color=''
        case "$_cls" in
            Boss|EnemyB) _color=$C_RED ;;
            BossSpinner) _color=$C_PURPLE ;;
            SkullKing)   _color=$C_RED ;;
            EnemyM)      _color=$C_ORANGE ;;
            EnemyQ)      _color=$C_YELLOW ;;
            EnemyV)      _color=$C_GREEN ;;
        esac
        if [[ "$_cls" == "Boss" || "$_cls" == "BossSpinner" || "$_cls" == "SkullKing" ]] && \
           (( ${_e["{inv_cd}$X"]:-0} > 0 )) ; then
            _color=$C_CYAN
        fi
        local _ay=${_e["{y}$X"]} _ax=${_e["{x}$X"]}
        local _h=${_e["{h}$X"]}
        local _hp2=${_e["{hp}$X"]}
        local _maxhp=${_e["{maxhp}$X"]}
        local _art=${_e["{art}$X"]}
        _scene_art_lines "$_art"
        local -i _r=0 _rn=${_SCENE_ART_CACHE["$_art|__n"]:-0}
        while (( _r < _rn )) ; do
            local _line=${_SCENE_ART_CACHE["$_art|$_r"]}
            printf -v _t '\033[%d;%dH%s%s%s' $((_ay + _r)) "$_ax" "$_color" "$_line" "$C_RESET"
            FRAME_BUF+="$_t"
            ((_r++))
        done
        if [[ "$_cls" == "Boss" ]] || [[ "$_cls" == "BossSpinner" ]] || [[ "$_cls" == "SkullKing" ]] || [[ "$_cls" == "EnemyB" ]] || [[ "$_cls" == "EnemyM" ]] ; then
            if (( _ay + _h < SCREEN_H )) ; then
                # 动态增益标签挂在 HP 行尾（非 Boss 没有这个字段，读出来是空）
                local _buff=''
                [[ -n "${_e["{buff_str}$X"]-}" ]] && _buff=" ${_e["{buff_str}$X"]}"
                printf -v _t '\033[%d;%dH\033[K%s[%d/%d]%s%s\033[%d;%dH%s' $((_ay + _h)) "$_ax" \
                    "$_color" "$_hp2" "$_maxhp" "$C_RESET" "$_buff" $((_ay + _h)) "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
            fi
        fi
        _e["{prev_x}$X"]=$_ax
        _e["{prev_y}$X"]=$_ay
        _e["{prev_art}$X"]=$_art
    done

    for d in "${DROPS[@]}" ; do
        [[ -n "$d" ]] || continue
        local -n _d=$d
        local _dx=${_d["{x}$X"]} _dy=${_d["{y}$X"]} _dsym=${_d["{symbol}$X"]}
        printf -v _t '\033[%d;%dH%s%s%s' "$_dy" "$_dx" "$C_REVERSE" "$_dsym" "$C_RESET"
        FRAME_BUF+="$_t"
        _d["{prev_x}$X"]=$_dx
        _d["{prev_y}$X"]=$_dy
    done

    for w in "${WORDS[@]}" ; do
        [[ -n "$w" ]] || continue
        local -n _w=$w
        local _wx=${_w["{x}$X"]} _wy=${_w["{y}$X"]} _wtxt=${_w["{text}$X"]}
        printf -v _t '\033[%d;%dH%s%s%s' "$_wy" "$_wx" "$C_CYAN" "$_wtxt" "$C_RESET"
        FRAME_BUF+="$_t"
        _w["{prev_x}$X"]=$_wx
        _w["{prev_y}$X"]=$_wy
    done

    # ===== 阶段 3：玩家最后画（层级最高）=====
    # 玩家先画会被自己的子弹（出生点在 y-1，护盾时正压顶罩）和敌弹（机翼不是
    # 判定点，会飞过机翼）覆盖，表现为机体/护盾反复被遮住。放最后即不再被遮。
    local _hp=${OBJ_player["{hp}$X"]:-0}
    local _maxhp=${OBJ_player["{maxhp}$X"]:-20}
    local _ph=''
    if (( _hp >= _maxhp )) ; then _ph="${C_BLUE}${C_BOLD}"
    elif (( _hp * 2 < _maxhp )) ; then _ph="${C_RED}${C_BOLD}"
    else _ph="${C_FG_DEFAULT}${C_BOLD}"
    fi
    local _green_bold="${C_GREEN}${C_BOLD}"

    local _px=${OBJ_player["{x}$X"]} _py=${OBJ_player["{y}$X"]}
    local _part=${OBJ_player["{art}$X"]}
    local _al=${OBJ_player["{al}$X"]:-1}
    local _bal=${OBJ_player["{base_al}$X"]:-1}
    local _sht=${OBJ_player["{shield_top}$X"]:--1}
    local _sh=${OBJ_player["{shield}$X"]:-0}
    local _pax=$(( _px - _al ))
    local _pay=$_py
    (( _sh )) && _pay=$(( _pay + _sht ))
    _scene_art_lines "$_part"
    local -i _pr=0 _pn=${_SCENE_ART_CACHE["$_part|__n"]:-0}
    while (( _pr < _pn )) ; do
        local _pline=${_SCENE_ART_CACHE["$_part|$_pr"]}
        local _out='' _cur_clr='' _c _i _want
        for (( _i=0 ; _i<${#_pline} ; _i++ )) ; do
            _c=${_pline:_i:1}
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
        printf -v _t '\033[%d;%dH%s' $((_pay + _pr)) "$_pax" "$_out"
        (( _blink_visible )) && FRAME_BUF+="$_t"
        ((_pr++))
    done
    OBJ_player["{prev_x}$X"]=$_px
    OBJ_player["{prev_y}$X"]=$_py
    OBJ_player["{prev_art}$X"]=$_part
    OBJ_player["{prev_al}$X"]=$_al
    OBJ_player["{prev_shield}$X"]=$_sh
}
