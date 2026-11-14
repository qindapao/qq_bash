# render/scene.sh — 主场景渲染（拼接 FRAME_BUF，不直接 printf）
[[ -n "${_STRAFE_SCENE_SH:-}" ]] && return 0
_STRAFE_SCENE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

_scene_clear_art_at () {
    local ay=$1 ax=$2 art=$3
    local r=0 line rest=$art
    local _buf='' _t
    while [[ -n "$rest" ]] ; do
        line=${rest%%$'\n'*}
        if [[ "$rest" == *$'\n'* ]] ; then
            rest=${rest#*$'\n'}
        else
            rest=''
        fi
        printf -v _t '\033[%d;%dH%*s' $((ay + r)) "$ax" "${#line}" ''
        _buf+=$_t
        ((r++))
    done
    FRAME_BUF+="$_buf"
}

_render_erase_one () {
    local obj=$1
    local -i skip_static=${2:-0}
    local -n o=$obj
    local px=${o["{prev_x}$X"]:-${o["{x}$X"]:-0}}
    local py=${o["{prev_y}$X"]:-${o["{y}$X"]:-0}}

    # 新对象首帧 prev=(0,0)，跳过擦除
    if (( px == 0 && py == 0 )) ; then
        unset -n o
        return 0
    fi

    # skip_static=1：位置没变时不必擦除，本帧的绘制会把这块重新盖住。
    # 擦除只会留下空格，而绘制本来就要覆盖同样的格子，省掉一次写。
    if (( skip_static )) && \
       (( px == ${o["{x}$X"]:-0} && py == ${o["{y}$X"]:-0} )) ; then
        unset -n o
        return 0
    fi

    local cls=${o["{CLS}$X"]}
    local _t
    case "$cls" in
    Bullet|Missile|EnemyBullet|BossBullet|Drop)
        printf -v _t '\033[%d;%dH ' "$py" "$px"
        FRAME_BUF+="$_t"
        ;;
    Plane)
        local psh=${o["{prev_shield}$X"]:-0}
        local pal=1
        local part="$PLANE_ART_BASE"
        (( psh )) && { pal=4 ; part="$PLANE_ART_SHIELD" ; }
        local pay=$py
        (( psh )) && pay=$(( py - 1 ))
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
    EnemyV|EnemyQ|EnemyM|EnemyB|Boss|BossSpinner)
        _scene_clear_art_at "$py" "$px" "${o["{art}$X"]}"
        local _bcls=${o["{CLS}$X"]}
        if [[ "$_bcls" == "Boss" ]] || [[ "$_bcls" == "BossSpinner" ]] || [[ "$_bcls" == "EnemyB" ]] || [[ "$_bcls" == "EnemyM" ]] ; then
            local _bh=${o["{h}$X"]:-1}
            if (( py + _bh < SCREEN_H )) ; then
                printf -v _t '\033[%d;2H\033[K\033[%d;%dH%s' $((py + _bh)) $((py + _bh)) "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
            fi
        fi
        ;;
    esac
    unset -n o
}

render () {
    local b e d eb m w _t
    local _ex _ey

    # ===== 阶段 1：擦除所有活对象的 prev =====
    [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] && \
        _render_erase_one "$PLAYER"
    # 单字符对象（子弹/导弹/敌弹/掉落）数量最多，内联擦除，
    # 省掉每个对象一次函数调用 + 一次 {CLS} 读取 + case 分派。
    for b in "${BULLETS[@]}" ; do
        [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
        local -n _b=$b
        _ex=${_b["{prev_x}$X"]:-${_b["{x}$X"]:-0}}
        _ey=${_b["{prev_y}$X"]:-${_b["{y}$X"]:-0}}
        if (( _ex || _ey )) ; then
            printf -v _t '\033[%d;%dH ' "$_ey" "$_ex"
            FRAME_BUF+="$_t"
        fi
        unset -n _b
    done
    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        local -n _m=$m
        _ex=${_m["{prev_x}$X"]:-${_m["{x}$X"]:-0}}
        _ey=${_m["{prev_y}$X"]:-${_m["{y}$X"]:-0}}
        if (( _ex || _ey )) ; then
            printf -v _t '\033[%d;%dH ' "$_ey" "$_ex"
            FRAME_BUF+="$_t"
        fi
        unset -n _m
    done
    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
        local -n _eb=$eb
        _ex=${_eb["{prev_x}$X"]:-${_eb["{x}$X"]:-0}}
        _ey=${_eb["{prev_y}$X"]:-${_eb["{y}$X"]:-0}}
        if (( _ex == ${_eb["{x}$X"]:-0} && _ey == ${_eb["{y}$X"]:-0} )) ; then
            unset -n _eb
            continue
        fi
        if (( _ex || _ey )) ; then
            printf -v _t '\033[%d;%dH ' "$_ey" "$_ex"
            FRAME_BUF+="$_t"
        fi
        unset -n _eb
    done
    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
        # 注意：不能对 Boss/EnemyB/EnemyM 跳过擦除，它们的擦除还要顺带
        # 清空整条血条行（\033[%d;2H\033[K）；跳过会留下上一帧的残影。
        _render_erase_one "$e"
    done
    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        local -n _d=$d
        _ex=${_d["{prev_x}$X"]:-${_d["{x}$X"]:-0}}
        _ey=${_d["{prev_y}$X"]:-${_d["{y}$X"]:-0}}
        if (( _ex == ${_d["{x}$X"]:-0} && _ey == ${_d["{y}$X"]:-0} )) ; then
            unset -n _d
            continue
        fi
        if (( _ex || _ey )) ; then
            printf -v _t '\033[%d;%dH ' "$_ey" "$_ex"
            FRAME_BUF+="$_t"
        fi
        unset -n _d
    done
    for w in "${WORDS[@]}" ; do
        [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
        _render_erase_one "$w" 1
    done

    # ===== 阶段 2：绘制所有活对象的 cur =====
    local -n p=$PLAYER
    local _hp=${p["{hp}$X"]:-0}
    local _ph=''
    if (( _hp >= 20 )) ; then _ph=$C_BLUE
    elif (( _hp <= 10 )) ; then _ph=$C_RED
    else _ph=$C_RESET
    fi

    local _px=${p["{x}$X"]} _py=${p["{y}$X"]}
    local _part=${p["{art}$X"]}
    local _al=${p["{al}$X"]:-1}
    local _sh=${p["{shield}$X"]:-0}
    local _pax=$(( _px - _al ))
    local _pay=$_py
    (( _sh )) && _pay=$(( _pay - 1 ))
    local _pr=0 _prest=$_part
    while [[ -n "$_prest" ]] ; do
        local _pline=${_prest%%$'\n'*}
        if [[ "$_prest" == *$'\n'* ]] ; then
            _prest=${_prest#*$'\n'}
        else
            _prest=''
        fi
        local _out='' _cur_clr='' _c _i _want
        for (( _i=0 ; _i<${#_pline} ; _i++ )) ; do
            _c=${_pline:_i:1}
            if [[ "$_c" == " " ]] ; then
                _out+=' '
                continue
            fi
            if (( _sh )) ; then
                if (( _pr == 0 )) ; then _want=$C_GREEN
                elif (( _pr == 1 )) && [[ "$_c" != "o" && "$_c" != "|" ]] ; then _want=$C_GREEN
                else _want=$_ph
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
        FRAME_BUF+="$_t"
        ((_pr++))
    done
    p["{prev_x}$X"]=$_px
    p["{prev_y}$X"]=$_py
    p["{prev_shield}$X"]=$_sh
    unset -n p

    if (( ${#BULLETS[@]} )) ; then
        for b in "${BULLETS[@]}" ; do
            [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
            local -n _b=$b
            local _bx=${_b["{x}$X"]} _by=${_b["{y}$X"]} _bsym=${_b["{symbol}$X"]}
            if [[ "$_bsym" == "|" || "$_bsym" == "/" || "$_bsym" == '\' || "$_bsym" == '-' ]] ; then
                printf -v _t '\033[%d;%dH%s%s%s' "$_by" "$_bx" "$C_PURPLE" "$_bsym" "$C_RESET"
            else
                printf -v _t '\033[%d;%dH%s' "$_by" "$_bx" "$_bsym"
            fi
            FRAME_BUF+="$_t"
            _b["{prev_x}$X"]=$_bx
            _b["{prev_y}$X"]=$_by
            unset -n _b
        done
    fi

    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        local -n _m=$m
        local _mx=${_m["{x}$X"]} _my=${_m["{y}$X"]} _msym=${_m["{symbol}$X"]}
        printf -v _t '\033[%d;%dH%s%s%s' "$_my" "$_mx" "$C_MAGENTA" "$_msym" "$C_RESET"
        FRAME_BUF+="$_t"
        _m["{prev_x}$X"]=$_mx
        _m["{prev_y}$X"]=$_my
        unset -n _m
    done

    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
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
        unset -n _eb
    done

    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
        local -n _e=$e
        local _cls=${_e["{CLS}$X"]}
        local _color=''
        case "$_cls" in
            Boss|EnemyB) _color=$C_RED ;;
            BossSpinner) _color=$C_PURPLE ;;
            EnemyM)      _color=$C_ORANGE ;;
            EnemyQ)      _color=$C_YELLOW ;;
            EnemyV)      _color=$C_GREEN ;;
        esac
        local _ay=${_e["{y}$X"]} _ax=${_e["{x}$X"]}
        local _h=${_e["{h}$X"]}
        local _hp2=${_e["{hp}$X"]}
        local _maxhp=${_e["{maxhp}$X"]}
        local _art=${_e["{art}$X"]}
        local _r=0 _rest=$_art
        while [[ -n "$_rest" ]] ; do
            local _line=${_rest%%$'\n'*}
            if [[ "$_rest" == *$'\n'* ]] ; then _rest=${_rest#*$'\n'}
            else _rest=''
            fi
            printf -v _t '\033[%d;%dH%s%s%s' $((_ay + _r)) "$_ax" "$_color" "$_line" "$C_RESET"
            FRAME_BUF+="$_t"
            ((_r++))
        done
        if [[ "$_cls" == "Boss" ]] || [[ "$_cls" == "BossSpinner" ]] || [[ "$_cls" == "EnemyB" ]] || [[ "$_cls" == "EnemyM" ]] ; then
            if (( _ay + _h < SCREEN_H )) ; then
                printf -v _t '\033[%d;%dH\033[K%s[%d/%d]%s\033[%d;%dH%s' $((_ay + _h)) "$_ax" \
                    "$_color" "$_hp2" "$_maxhp" "$C_RESET" $((_ay + _h)) "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
            fi
        fi
        _e["{prev_x}$X"]=$_ax
        _e["{prev_y}$X"]=$_ay
        unset -n _e
    done

    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        local -n _d=$d
        local _dx=${_d["{x}$X"]} _dy=${_d["{y}$X"]} _dsym=${_d["{symbol}$X"]}
        printf -v _t '\033[%d;%dH%s%s%s' "$_dy" "$_dx" "$C_REVERSE" "$_dsym" "$C_RESET"
        FRAME_BUF+="$_t"
        _d["{prev_x}$X"]=$_dx
        _d["{prev_y}$X"]=$_dy
        unset -n _d
    done

    for w in "${WORDS[@]}" ; do
        [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
        local -n _w=$w
        local _wx=${_w["{x}$X"]} _wy=${_w["{y}$X"]} _wtxt=${_w["{text}$X"]}
        printf -v _t '\033[%d;%dH%s%s%s' "$_wy" "$_wx" "$C_CYAN" "$_wtxt" "$C_RESET"
        FRAME_BUF+="$_t"
        _w["{prev_x}$X"]=$_wx
        _w["{prev_y}$X"]=$_wy
        unset -n _w
    done
}
