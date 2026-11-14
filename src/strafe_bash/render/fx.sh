# render/fx.sh — 特效渲染（炸弹爆炸 / Boss 死亡）
[[ -n "${_STRAFE_FX_SH:-}" ]] && return 0
_STRAFE_FX_SH=1
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

render_bomb_fx () {
    local i
    for (( i=0; i<${#BOMB_FX_POS[@]}; i+=2 )) ; do
        printf '\033[%d;%dH ' "${BOMB_FX_POS[i]}" "${BOMB_FX_POS[i+1]}"
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
        printf '\033[%d;%dH%s%s%s' "$_cy" "$_cx" "${_colors[_ci]}" "$_ch" "$C_RESET"
        BOMB_FX_POS+=("$_cy" "$_cx")
    done
}

render_boss_death () {
    local _chars='@#*%&!?'
    local _colors=("$C_RED" "$C_YELLOW" "$C_ORANGE" "$C_PURPLE")
    local i _n=${#BOSS_DEATH_POS[@]}
    for (( i=0; i<_n; i+=2 )) ; do
        local _cy=${BOSS_DEATH_POS[i]}
        local _cx=${BOSS_DEATH_POS[i+1]}
        local _ch=${_chars:RANDOM % ${#_chars}:1}
        local _ci=$(( RANDOM % 4 ))
        printf '\033[%d;%dH%s%s%s' "$_cy" "$_cx" "${_colors[_ci]}" "$_ch" "$C_RESET"
    done
}
