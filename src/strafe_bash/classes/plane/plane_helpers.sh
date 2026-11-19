# classes/plane/plane_helpers.sh — 飞机绘制辅助（_art_clear_at, _plane_clear, _plane_set_shield）
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[plane_helpers]++ )) && return 0
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"

_art_clear_at () {
    local ay=$1 ax=$2 art=$3
    local r=0 line rest=$art
    while [[ -n "$rest" ]] ; do
        line=${rest%%$'\n'*}
        if [[ "$rest" == *$'\n'* ]] ; then
            rest=${rest#*$'\n'}
        else
            rest=''
        fi
        # 夹到可玩区：贴左/贴右时不能擦到边框
        local -i _cx=$ax _cw=${#line}
        if (( _cx < 2 )) ; then
            _cw=$(( _cw - (2 - _cx) )) _cx=2
        fi
        (( _cx + _cw > SCREEN_W - 1 )) && _cw=$(( SCREEN_W - 1 - _cx ))
        if (( _cw > 0 )) ; then
            printf '%s' "$ESC[$((ay + r));${_cx}H${SPACE_PROTOTYPE_STRING:0:_cw}"
        fi
        ((r++))
    done
}

_plane_clear () {
    local -n _pl_self=$1
    local _atop=${_pl_self[y]}
    (( ${_pl_self[shield]:-0} )) && _atop=$(( _atop - 1 ))
    _art_clear_at "$_atop" $(( ${_pl_self[x]} - ${_pl_self[al]} )) "${_pl_self[art]}"
}

_plane_set_shield () {
    local p=$1 on=$2
    local -n self=$p
    if (( on )) ; then
        self[art]=${self[shield_art]} \
        self[al]=${self[shield_al]:-4} \
        self[shield]=1 \
        self[st]=$BONUS_ST
        local y=${self[y]}
        local -i _al=${self[al]}
        (( y < GAME_TOP + 1 )) && self[y]=$(( GAME_TOP + 1 ))
        local x=${self[x]}
        (( x < _al + 2 )) && self[x]=$(( _al + 2 ))
        (( x > SCREEN_W - _al - 2 )) && self[x]=$(( SCREEN_W - _al - 2 ))
    else
        self[art]=${self[base_art]} \
        self[al]=${self[base_al]:-1} \
        self[shield]=0 \
        self[st]=0
    fi
}
