# render/hud.sh — HUD 状态栏
[[ -n "${_STRAFE_HUD_SH:-}" ]] && return 0
_STRAFE_HUD_SH=1
. "$(dirname "${BASH_SOURCE[0]}")/../config/const.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../config/globals.sh"
. "$STRAFE_LIB_HOME/xo.sh"

draw_hud_line1 () {
    local -n p=$PLAYER
    local bt=${p["{bullet}$X"]}
    local weapon='.'
    if [[ -n "$bt" && -n "${XO_OBJ_POOL[$bt]+_}" ]] ; then
        local -n _bt=$bt
        weapon=${_bt["{symbol}$X"]}
        unset -n _bt
    fi
    local _s
    printf -v _s 'HP:%d/%d  SCORE:%d  W:%s  BOMB:%d/5  E:%d/%d  OBJ:%d' \
        "${p["{hp}$X"]:-0}" 20 "${p["{score}$X"]:-0}" "$weapon" "${p["{bombs}$X"]:-0}" \
        "${#ENEMIES[@]}" "$ENEMY_LIMIT" "${#XO_OBJ_POOL[@]}"
    unset -n p
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    printf '\033[2;2H\033[K%s\033[2;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
}

draw_hud_line2 () {
    local _s='ENEMY V:1 Q:5 M:10 B:30 BOSS:250   BULLET .:1 *:2 @:3 $:4 |:LASER   DROP H:+3 b:BOMB m:MISSILE L:LANE S:SHIELD'
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    printf '\033[3;2H\033[K%s\033[3;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
}

draw_bonus_hud () {
    local -n p=$PLAYER
    local t2=$(( ${p["{t2}$X"]:-0} / FPS ))
    local t3=$(( ${p["{t3}$X"]:-0} / FPS ))
    local t4=$(( ${p["{t4}$X"]:-0} / FPS ))
    local t5=$(( ${p["{t5}$X"]:-0} / FPS ))
    local mt=$(( ${p["{mt}$X"]:-0} / FPS ))
    local lt=$(( ${p["{lt}$X"]:-0} / FPS ))
    local st=$(( ${p["{st}$X"]:-0} / FPS ))
    local lcount=$(( ${p["{lanes}$X"]:-0} + 1 ))
    unset -n p
    local _s
    printf -v _s 'BONUS  *:%3d  @:%3d  $:%3d  |:%3d  M:%3d  L:%3d(%d)  S:%3d' \
        "$t2" "$t3" "$t4" "$t5" "$mt" "$lt" "$lcount" "$st"
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    printf '\033[4;2H\033[K%s\033[4;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
}
