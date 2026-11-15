# render/hud.sh — HUD 状态栏（拼接 FRAME_BUF）
[[ -n "${_STRAFE_HUD_SH:-}" ]] && return 0
_STRAFE_HUD_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

draw_hud_line1 () {
    local bt=${OBJ_player["{bullet}$X"]}
    local weapon='.'
    if [[ -n "$bt" && -n "${XO_OBJ_POOL[$bt]+_}" ]] ; then
        local -n _bt=$bt
        weapon=${_bt["{u}$X"]}
        unset -n _bt
    fi
    local _s
    printf -v _s 'HP:%d/%d  SCORE:%d  W:%s  BOMB:%d/5  E:%d/%d  OBJ:%d' \
        "${OBJ_player["{hp}$X"]:-0}" "${OBJ_player["{maxhp}$X"]:-20}" "${OBJ_player["{score}$X"]:-0}" "$weapon" "${OBJ_player["{bombs}$X"]:-0}" \
        "${#ENEMIES[@]}" "$ENEMY_LIMIT" "${#XO_OBJ_POOL[@]}"
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    local _t
    printf -v _t '\033[2;2H%*s\033[2;2H%s\033[2;%dH%s' "$_maxw" '' "$_s" "$SCREEN_W" "$FRAME_V"
    FRAME_BUF+="$_t"
}

draw_hud_line2 () {
    # 只显示本局实际抽到的 4 种掉落武器（tier 2..5），默认子弹不占位。
    local _s='BULLET'
    local _i _w
    if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        for _i in 2 3 4 5 ; do
            _w=${OBJ_player["{w$_i}$X"]}
            [[ -n "$_w" && -n "${XO_OBJ_POOL[$_w]+_}" ]] || continue
            local -n _wobj=$_w
            local _wu=${_wobj["{u}$X"]} _wd=${_wobj["{damage}$X"]}
            _s+=" ${_wu}:${_wd}"
            unset -n _wobj
        done
    fi
    _s+='  DROP H:+3 b:BOMB m:MISSILE L:LANE S:SHIELD'
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    local _t
    printf -v _t '\033[3;2H%*s\033[3;2H%s\033[3;%dH%s' "$_maxw" '' "$_s" "$SCREEN_W" "$FRAME_V"
    FRAME_BUF+="$_t"
}

draw_bonus_hud () {
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] || return 0
    local _s='BONUS'
    local _i _w _wu _tv _part
    # 4 种武器按 tier 2..5 动态取实际字符和倒计时，
    # 不能像旧版那样写死 * @ $ |，否则武器和数字会错位。
    for _i in 2 3 4 5 ; do
        _w=${OBJ_player["{w$_i}$X"]}
        _wu='?'
        if [[ -n "$_w" && -n "${XO_OBJ_POOL[$_w]+_}" ]] ; then
            local -n _wobj=$_w
            _wu=${_wobj["{u}$X"]}
            unset -n _wobj
        fi
        _tv=$(( ${OBJ_player["{t$_i}$X"]:-0} / FPS ))
        printf -v _part '  %s:%3d' "$_wu" "$_tv"
        _s+=$_part
    done
    local mt=$(( ${OBJ_player["{mt}$X"]:-0} / FPS ))
    local lt=$(( ${OBJ_player["{lt}$X"]:-0} / FPS ))
    local st=$(( ${OBJ_player["{st}$X"]:-0} / FPS ))
    local lcount=$(( ${OBJ_player["{lanes}$X"]:-0} + 1 ))
    printf -v _part '  m:%3d  L:%3d(%d)  S:%3d' "$mt" "$lt" "$lcount" "$st"
    _s+=$_part
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    local _t
    printf -v _t '\033[4;2H%*s\033[4;2H%s\033[4;%dH%s' "$_maxw" '' "$_s" "$SCREEN_W" "$FRAME_V"
    FRAME_BUF+="$_t"
}
