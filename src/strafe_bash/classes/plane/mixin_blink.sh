# classes/plane/mixin_blink.sh — M_Blink
# 受伤后的短暂无敌闪烁；方法由 xo_init 注入 Plane 及其子类。
[[ -n "${_STRAFE_MIXIN_BLINK_SH:-}" ]] && return 0
_STRAFE_MIXIN_BLINK_SH=1

readonly M_BlinkStaticTemplate='
    M_BlinkObj ->
        {CLS} => M_Blink
        {SUP} => Base
        {MIX} => 
        {REQUIRES} => blink
    '

M_Blink_blink_start () {
    local -n self=$1
    local -i frames=${2:-$(( 3 * FPS ))}
    self["{blink}$X"]=$frames
}

M_Blink_blink_tick () {
    local -n self=$1
    local -i b=${self["{blink}$X"]:-0}
    (( b > 0 )) && self["{blink}$X"]=$(( b - 1 ))
    return 0
}

M_Blink_blink_visible () {
    local -n self=$1
    local -i b=${self["{blink}$X"]:-0}
    (( b <= 0 )) && return 0
    # 3 ticks visible, 3 ticks hidden
    (( (b / 3) % 2 == 0 ))
}
