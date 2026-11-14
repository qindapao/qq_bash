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
    local -n o=$obj
    local px=${o["{prev_x}$X"]:-${o["{x}$X"]:-0}}
    local py=${o["{prev_y}$X"]:-${o["{y}$X"]:-0}}

    # 新对象首帧 prev=(0,0)，跳过擦除
    if (( px == 0 && py == 0 )) ; then
        unset -n o
        return 0
    fi

    local cls=${o["{CLS}$X"]}
    local _t
    case "$cls" in
    Bullet|Missile|EnemyBullet|Drop)
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
    EnemyV|EnemyQ|EnemyM|EnemyB|Boss)
        _scene_clear_art_at "$py" "$px" "${o["{art}$X"]}"
        local _bcls=${o["{CLS}$X"]}
        if [[ "$_bcls" == "Boss" ]] || [[ "$_bcls" == "EnemyB" ]] || [[ "$_bcls" == "EnemyM" ]] ; then
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

    # ===== 阶段 1：擦除所有活对象的 prev =====
    [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] && \
        _render_erase_one "$PLAYER"
    for b in "${BULLETS[@]}" ; do
        [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
        _render_erase_one "$b"
    done
    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        _render_erase_one "$m"
    done
    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
        _render_erase_one "$eb"
    done
    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
        _render_erase_one "$e"
    done
    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        _render_erase_one "$d"
    done
    for w in "${WORDS[@]}" ; do
        [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
        _render_erase_one "$w"
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
    unset -n p

    if (( ${#BULLETS[@]} )) ; then
        for b in "${BULLETS[@]}" ; do
            [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
            local -n _b=$b
            local _bsym=${_b["{symbol}$X"]}
            if [[ "$_bsym" == "|" || "$_bsym" == "/" || "$_bsym" == '\' || "$_bsym" == '-' ]] ; then
                printf -v _t '\033[%d;%dH%s%s%s' "${_b["{y}$X"]}" "${_b["{x}$X"]}" "$C_PURPLE" "$_bsym" "$C_RESET"
            else
                printf -v _t '\033[%d;%dH%s' "${_b["{y}$X"]}" "${_b["{x}$X"]}" "$_bsym"
            fi
            FRAME_BUF+="$_t"
            unset -n _b
        done
    fi

    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        local -n _m=$m
        printf -v _t '\033[%d;%dH%s%s%s' "${_m["{y}$X"]}" "${_m["{x}$X"]}" "$C_MAGENTA" "${_m["{symbol}$X"]}" "$C_RESET"
        FRAME_BUF+="$_t"
        unset -n _m
    done

    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
        local -n _eb=$eb
        printf -v _t '\033[%d;%dH%s' "${_eb["{y}$X"]}" "${_eb["{x}$X"]}" "${_eb["{symbol}$X"]}"
        FRAME_BUF+="$_t"
        unset -n _eb
    done

    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
        local -n _e=$e
        local _cls=${_e["{CLS}$X"]}
        local _color=''
        case "$_cls" in
            Boss|EnemyB) _color=$C_RED ;;
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
        if [[ "$_cls" == "Boss" ]] || [[ "$_cls" == "EnemyB" ]] || [[ "$_cls" == "EnemyM" ]] ; then
            if (( _ay + _h < SCREEN_H )) ; then
                printf -v _t '\033[%d;%dH\033[K%s[%d/%d]%s\033[%d;%dH%s' $((_ay + _h)) "$_ax" \
                    "$_color" "$_hp2" "$_maxhp" "$C_RESET" $((_ay + _h)) "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
            fi
        fi
        unset -n _e
    done

    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        local -n _d=$d
        printf -v _t '\033[%d;%dH%s' "${_d["{y}$X"]}" "${_d["{x}$X"]}" "${_d["{symbol}$X"]}"
        FRAME_BUF+="$_t"
        unset -n _d
    done

    for w in "${WORDS[@]}" ; do
        [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
        local -n _w=$w
        printf -v _t '\033[%d;%dH%s%s%s' "${_w["{y}$X"]}" "${_w["{x}$X"]}" "$C_CYAN" "${_w["{text}$X"]}" "$C_RESET"
        FRAME_BUF+="$_t"
        unset -n _w
    done

    # ===== 阶段 3：prev = cur =====
    local _obj
    for _obj in "$PLAYER" "${BULLETS[@]}" "${MISSILES[@]}" "${ENEMY_BULLETS[@]}" "${ENEMIES[@]}" "${DROPS[@]}" "${WORDS[@]}" ; do
        [[ -n "$_obj" && -n "${XO_OBJ_POOL[$_obj]+_}" ]] || continue
        local -n _o=$_obj
        _o["{prev_x}$X"]=${_o["{x}$X"]}
        _o["{prev_y}$X"]=${_o["{y}$X"]}
        [[ -n "${_o[{shield}$X]+_}" ]] && _o["{prev_shield}$X"]=${_o["{shield}$X"]}
        unset -n _o
    done
}
