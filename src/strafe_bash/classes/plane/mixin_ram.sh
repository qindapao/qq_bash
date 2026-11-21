# classes/plane/mixin_ram.sh — M_Ram
# 撞击能力：闪烁/受伤状态中，按冷却对撞到的敌机造成 5 点伤害。
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[mixin_ram]++ )) && return 0

# Mixin 公共方法声明
declare -gA XO_MIXIN_METHODS
XO_MIXIN_METHODS[M_Ram]='ram_tick ram_ready ram_damage'

readonly M_RamStaticTemplate='
    M_RamObj ->
        {CLS} => M_Ram
        {SUP} => Base
        {MIX} => 
        # 依赖字段（当前仅作文档，不校验）：{blink} 判断是否处于无敌/受伤态，
        # {ram_cd} 是撞击冷却计时器
        {REQUIRES} => blink ram_cd
    '

M_Ram_ram_tick () {
    local -n self=$1
    local -i cd=${self[ram_cd]:-0}
    (( cd > 0 )) && self[ram_cd]=$(( cd - 1 ))
    return 0
}

M_Ram_ram_ready () {
    local -n self=$1
    local -i b=${self[blink]:-0} \
             cd=${self[ram_cd]:-0}
    (( b > 0 && cd <= 0 )) || return 1
    self[ram_cd]=10
    return 0
}

M_Ram_ram_damage () {
    REPLY=5
}
