# classes/plane/mixin_ram.sh — M_Ram
# 撞击能力：闪烁/受伤状态中，按冷却对撞到的敌机造成 5 点伤害。
[[ -n "${_STRAFE_MIXIN_RAM_SH:-}" ]] && return 0
_STRAFE_MIXIN_RAM_SH=1

readonly M_RamStaticTemplate='
    M_RamObj ->
        {CLS} => M_Ram
        {SUP} => Base
        {MIX} => 
        {REQUIRES} => blink ram_cd
    '

M_Ram_ram_tick () {
    local -n self=$1
    local -i cd=${self["{ram_cd}$X"]:-0}
    (( cd > 0 )) && self["{ram_cd}$X"]=$(( cd - 1 ))
    return 0
}

M_Ram_ram_ready () {
    local -n self=$1
    local -i b=${self["{blink}$X"]:-0}
    local -i cd=${self["{ram_cd}$X"]:-0}
    (( b > 0 && cd <= 0 )) || return 1
    self["{ram_cd}$X"]=10
    return 0
}

M_Ram_ram_damage () {
    printf '5'
}
