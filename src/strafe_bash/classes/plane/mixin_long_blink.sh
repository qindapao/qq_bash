# classes/plane/mixin_long_blink.sh — M_LongBlink
# 伊尔-2 专用：受伤后的闪烁/无敌窗口延长到 8 秒。
# {MIX} 列表中放在 M_Blink 前面，覆盖后者的 blink_start。
[[ -n "${_STRAFE_MIXIN_LONG_BLINK_SH:-}" ]] && return 0
_STRAFE_MIXIN_LONG_BLINK_SH=1

readonly M_LongBlinkStaticTemplate='
    M_LongBlinkObj ->
        {CLS} => M_LongBlink
        {SUP} => Base
        {MIX} => 
        {REQUIRES} => blink
    '

M_LongBlink_blink_start () {
    local -n self=$1
    self["{blink}$X"]=$(( 8 * FPS ))
}
