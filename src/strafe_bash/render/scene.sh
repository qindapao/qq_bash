# render/scene.sh — 主场景渲染（飞机/子弹/敌机/掉落/文字）
[[ -n "${_STRAFE_SCENE_SH:-}" ]] && return 0
_STRAFE_SCENE_SH=1
. "$(dirname "${BASH_SOURCE[0]}")/../config/const.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../config/color.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../config/globals.sh"
. "$STRAFE_LIB_HOME/xo.sh"

render () {
    local -n p=$PLAYER
    local _hp=${p["{hp}$X"]:-0}
    local _ph=''
    if (( _hp >= 20 )) ; then
        _ph=$C_BLUE
    elif (( _hp <= 10 )) ; then
        _ph=$C_RED
    else
        _ph=$C_RESET
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
                if (( _pr == 0 )) ; then
                    _want=$C_GREEN
                elif (( _pr == 1 )) && [[ "$_c" != "o" && "$_c" != "|" ]] ; then
                    _want=$C_GREEN
                else
                    _want=$_ph
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
        printf '\033[%d;%dH%s' $((_pay + _pr)) "$_pax" "$_out"
        ((_pr++))
    done
    unset -n p

    local b e d eb m w

    if (( ${#BULLETS[@]} )) ; then
        local _buf='' _bt
        for b in "${BULLETS[@]}" ; do
            [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
            local -n _b=$b
            local _bsym=${_b["{symbol}$X"]}
            if [[ "$_bsym" == "|" || "$_bsym" == "/" || "$_bsym" == '\' || "$_bsym" == '-' ]] ; then
                printf -v _bt '\033[%d;%dH%s%s%s' "${_b["{y}$X"]}" "${_b["{x}$X"]}" "$C_PURPLE" "$_bsym" "$C_RESET"
            else
                printf -v _bt '\033[%d;%dH%s' "${_b["{y}$X"]}" "${_b["{x}$X"]}" "$_bsym"
            fi
            _buf+=$_bt
            unset -n _b
        done
        [[ -n "$_buf" ]] && printf '%s' "$_buf"
    fi

    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        local -n _m=$m
        printf '\033[%d;%dH%s%s%s' "${_m["{y}$X"]}" "${_m["{x}$X"]}" "$C_MAGENTA" "${_m["{symbol}$X"]}" "$C_RESET"
        unset -n _m
    done

    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
        local -n _eb=$eb
        printf '\033[%d;%dH%s' "${_eb["{y}$X"]}" "${_eb["{x}$X"]}" "${_eb["{symbol}$X"]}"
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
            if [[ "$_rest" == *$'\n'* ]] ; then
                _rest=${_rest#*$'\n'}
            else
                _rest=''
            fi
            printf '\033[%d;%dH%s%s%s' $((_ay + _r)) "$_ax" "$_color" "$_line" "$C_RESET"
            ((_r++))
        done

        if [[ "$_cls" == "Boss" ]] || [[ "$_cls" == "EnemyB" ]] || [[ "$_cls" == "EnemyM" ]] ; then
            if (( _ay + _h < SCREEN_H )) ; then
                printf '\033[%d;%dH\033[K%s[%d/%d]%s\033[%d;%dH%s' $((_ay + _h)) "$_ax" \
                    "$_color" "$_hp2" "$_maxhp" "$C_RESET" $((_ay + _h)) "$SCREEN_W" "$FRAME_V"
            fi
        fi
        unset -n _e
    done

    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        local -n _d=$d
        printf '\033[%d;%dH%s' "${_d["{y}$X"]}" "${_d["{x}$X"]}" "${_d["{symbol}$X"]}"
        unset -n _d
    done

    for w in "${WORDS[@]}" ; do
        [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
        local -n _w=$w
        printf '\033[%d;%dH%s%s%s' "${_w["{y}$X"]}" "${_w["{x}$X"]}" "$C_CYAN" "${_w["{text}$X"]}" "$C_RESET"
        unset -n _w
    done
}
