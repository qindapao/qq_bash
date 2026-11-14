# render/fx.sh — 特效渲染（拼接 FRAME_BUF）
[[ -n "${_STRAFE_FX_SH:-}" ]] && return 0
_STRAFE_FX_SH=1
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

render_bomb_fx () {
    local i
    local _t
    for (( i=0; i<${#BOMB_FX_POS[@]}; i+=2 )) ; do
        printf -v _t '\033[%d;%dH ' "${BOMB_FX_POS[i]}" "${BOMB_FX_POS[i+1]}"
        FRAME_BUF+="$_t"
    done
    BOMB_FX_POS=()

    local _chars='@#$%&*?!'
    local _colors=("$C_RED" "$C_YELLOW" "$C_ORANGE" "$C_PURPLE" "$C_BLUE")
    local _n=$(( 15 + RANDOM % 10 ))
    local _i2 _cx _cy _ch _ci
    for (( _i2=0; _i2<_n; _i2++ )) ; do
        _cx=$(( RANDOM % (SCREEN_W - 2) + 2 ))
        _cy=$(( RANDOM % (SCREEN_H - GAME_TOP) + GAME_TOP ))
        _ch=${_chars:RANDOM % ${#_chars}:1}
        _ci=$(( RANDOM % 5 ))
        printf -v _t '\033[%d;%dH%s%s%s' "$_cy" "$_cx" "${_colors[_ci]}" "$_ch" "$C_RESET"
        FRAME_BUF+="$_t"
        BOMB_FX_POS+=("$_cy" "$_cx")
    done
}

render_hit_fx_clear_expired () {
    (( ${#HIT_FX[@]} )) || return 0
    local -a _keep=()
    local i _y _x _ch _clr _ttl _t
    for (( i=0; i<${#HIT_FX[@]}; i+=5 )) ; do
        _y=${HIT_FX[i]}
        _x=${HIT_FX[i+1]}
        _ch=${HIT_FX[i+2]}
        _clr=${HIT_FX[i+3]}
        _ttl=${HIT_FX[i+4]}
        if (( _ttl > 0 )) ; then
            _keep+=("$_y" "$_x" "$_ch" "$_clr" "$_ttl")
        else
            printf -v _t '\033[%d;%dH ' "$_y" "$_x"
            FRAME_BUF+="$_t"
        fi
    done
    HIT_FX=("${_keep[@]}")
}

render_hit_fx () {
    (( ${#HIT_FX[@]} )) || return 0
    local -a _keep=()
    local i _y _x _ch _clr _ttl _t
    for (( i=0; i<${#HIT_FX[@]}; i+=5 )) ; do
        _y=${HIT_FX[i]}
        _x=${HIT_FX[i+1]}
        _ch=${HIT_FX[i+2]}
        _clr=${HIT_FX[i+3]}
        _ttl=${HIT_FX[i+4]}
        (( _ttl > 0 )) || continue
        printf -v _t '\033[%d;%dH%s%s%s%s' \
            "$_y" "$_x" "$_clr" "$C_BOLD" "$_ch" "$C_RESET"
        FRAME_BUF+="$_t"
        _keep+=("$_y" "$_x" "$_ch" "$_clr" "$((_ttl - 1))")
    done
    HIT_FX=("${_keep[@]}")
}
render_boss_death () {
    local _chars='@#*%&!?'
    local _colors=("$C_RED" "$C_YELLOW" "$C_ORANGE" "$C_PURPLE")
    local i _n _t

    # style 1：旋刃，向外扩散的三圈火花 + 核心爆裂
    if (( BOSS_DEATH_STYLE == 1 )) ; then
        # 擦掉上一波
        for (( i=0; i<${#BOSS_DEATH_POS[@]}; i+=2 )) ; do
            printf -v _t '\033[%d;%dH ' "${BOSS_DEATH_POS[i]}" "${BOSS_DEATH_POS[i+1]}"
            FRAME_BUF+="$_t"
        done
        BOSS_DEATH_POS=()

        local -i _r=$(( 1 + BOSS_DEATH_WAVE / 6 ))
        local -a _dx=(0 1 1 1 0 -1 -1 -1)
        local -a _dy=(-1 -1 0 1 1 1 0 -1)
        local -i _cx=$BOSS_DEATH_CX _cy=$BOSS_DEATH_CY
        local -i _px _py _ci
        local _ch
        for (( i=0; i<8; i++ )) ; do
            _px=$(( _cx + _dx[i] * _r ))
            _py=$(( _cy + _dy[i] * _r ))
            if (( _px >= 2 && _px <= SCREEN_W - 2 && _py >= GAME_TOP && _py < SCREEN_H )) ; then
                _ch=${_chars:RANDOM % ${#_chars}:1}
                _ci=$(( RANDOM % 4 ))
                printf -v _t '\033[%d;%dH%s%s%s' "$_py" "$_px" "${_colors[_ci]}" "$_ch" "$C_RESET"
                FRAME_BUF+="$_t"
                BOSS_DEATH_POS+=("$_py" "$_px")
            fi
        done
        # 前 8 帧中心核心爆闪
        if (( BOSS_DEATH_WAVE < 8 )) ; then
            _px=$_cx ; _py=$_cy
            if (( _px >= 2 && _px <= SCREEN_W - 2 && _py >= GAME_TOP && _py < SCREEN_H )) ; then
                printf -v _t '\033[%d;%dH%s@%s' "$_py" "$_px" "$C_YELLOW" "$C_RESET"
                FRAME_BUF+="$_t"
                BOSS_DEATH_POS+=("$_py" "$_px")
            fi
        fi
        ((BOSS_DEATH_WAVE++))
        return 0
    fi

    _n=${#BOSS_DEATH_POS[@]}
    for (( i=0; i<_n; i+=2 )) ; do
        local _cy=${BOSS_DEATH_POS[i]}
        local _cx=${BOSS_DEATH_POS[i+1]}
        local _ch=${_chars:RANDOM % ${#_chars}:1}
        local _ci=$(( RANDOM % 4 ))
        printf -v _t '\033[%d;%dH%s%s%s' "$_cy" "$_cx" "${_colors[_ci]}" "$_ch" "$C_RESET"
        FRAME_BUF+="$_t"
    done
}
