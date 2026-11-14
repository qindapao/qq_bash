# classes/plane/plane_helpers.sh — 飞机绘制辅助（_art_clear_at, _plane_clear, _plane_set_shield）
[[ -n "${_STRAFE_PLANE_HELPERS_SH:-}" ]] && return 0
_STRAFE_PLANE_HELPERS_SH=1
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
        printf '\033[%d;%dH%*s' $((ay + r)) "$ax" "${#line}" ''
        ((r++))
    done
}

_plane_clear () {
    local p=$1
    local -n _pl_self=$p
    local _atop=${_pl_self["{y}$X"]}
    (( ${_pl_self["{shield}$X"]:-0} )) && _atop=$(( _atop - 1 ))
    _art_clear_at "$_atop" $(( ${_pl_self["{x}$X"]} - ${_pl_self["{al}$X"]} )) "${_pl_self["{art}$X"]}"
    unset -n _pl_self
}

_plane_set_shield () {
    local p=$1 on=$2
    local -n self=$p
    _plane_clear "$p"
    if (( on )) ; then
        self["{art}$X"]="$PLANE_ART_SHIELD"
        self["{al}$X"]=4
        self["{shield}$X"]=1
        self["{st}$X"]=$BONUS_ST
        local y=${self["{y}$X"]}
        (( y < GAME_TOP + 1 )) && self["{y}$X"]=$(( GAME_TOP + 1 ))
        local x=${self["{x}$X"]}
        (( x < 6 )) && self["{x}$X"]=6
        (( x > SCREEN_W - 6 )) && self["{x}$X"]=$(( SCREEN_W - 6 ))
    else
        self["{art}$X"]="$PLANE_ART_BASE"
        self["{al}$X"]=1
        self["{shield}$X"]=0
        self["{st}$X"]=0
    fi
    unset -n self
}
