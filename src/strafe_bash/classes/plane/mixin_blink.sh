# classes/plane/mixin_blink.sh — M_Blink
# 受伤后的短暂无敌闪烁；方法由 xo_init 注入 Plane 及其子类。
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[mixin_blink]++ )) && return 0

# Mixin 公共方法声明
declare -gA XO_MIXIN_METHODS
XO_MIXIN_METHODS[M_Blink]='blink_start blink_tick blink_visible'


readonly M_BlinkStaticTemplate='
    M_BlinkObj ->
        {CLS} => M_Blink
        {SUP} => Base
        {MIX} => 
        # 依赖字段（当前仅作文档，不校验）：使用方必须有 {blink} 这个计时器字段
        # 扁平属性要求
        {REQUIRES} => FLT=1 blink
    '

M_Blink_blink_start () {
    local -n self=$1
    local -i frames=${2:-$(( 3 * FPS ))}
    self[blink]=$frames
}

M_Blink_blink_tick () {
    local -n self=$1
    local -i b=${self[blink]:-0}
    (( b > 0 )) && self[blink]=$(( b - 1 ))
    return 0
}

M_Blink_blink_visible () {
    local -n self=$1
    local -i b=${self[blink]:-0}
    (( b <= 0 )) && return 0
    # 3 ticks visible, 3 ticks hidden
    (( (b / 3) % 2 == 0 ))
}
