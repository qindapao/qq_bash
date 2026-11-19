# classes/plane/mixin_long_blink.sh — M_LongBlink
# 伊尔-2 专用：受伤后的闪烁/无敌窗口延长到 4 秒。
# {MIX} 列表中放在 M_Blink 前面，覆盖后者的 blink_start。
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[mixin_long_blink]++ )) && return 0

readonly M_LongBlinkStaticTemplate='
    M_LongBlinkObj ->
        {CLS} => M_LongBlink
        {SUP} => Base
        {MIX} => 
        # 依赖字段（当前仅作文档，不校验）：使用方必须有 {blink} 这个计时器字段
        {REQUIRES} => blink
    '

M_LongBlink_blink_start () {
    local -n self=$1
    self[blink]=$(( 4 * FPS ))
}
