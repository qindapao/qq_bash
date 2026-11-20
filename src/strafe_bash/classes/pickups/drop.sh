# classes/pickups/drop.sh — Drop
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[drop]++ )) && return 0
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"

readonly DropStaticTemplate='
    DropObj ->
        {CLS} => Drop
        {SUP} => Entity
        {MIX} => 
        # 位置（每 6 tick 落一行）
        {x} => 0
        {y} => 0
        # 显示字符：默认等于 dtype；武器档位掉落显示该武器的主字符
        {symbol} => 1
        # 掉落类型：H 回血 / b 炸弹 / m 导弹 / L 弹道 / S 护盾 / W 电网 /
        #           2..5 对应四档武器（直接就是 tier）
        {dtype} => 1
        # 下落节拍计时器
        {cd} => 0
        # 帧缓冲用的成品串（反色+字符+复位）
        {glyph} => 
    '
Drop_born () {
    local -n self=$1
    local t=$2
    local _px=${3:-} _py=${4:-}
    self[dtype]=$t \
        self[symbol]=$t

    # 武器掉落（tier 1..5）显示对应武器的主字符，而不是数字。
    # 武器对象在本局 init_game 时已经创建好，这里只查它的 {u}。
    case "$t" in
        1|2|3|4|5)
            if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
                local _w=${OBJ_player["w$t"]}
                if [[ -n "$_w" && -n "${XO_OBJ_POOL[$_w]+_}" ]] ; then
                    local -n _wobj=$_w
                    self[symbol]=${_wobj[u]}
                fi
            fi
            ;;
    esac

    # 位置：默认在顶部随机列；调用方可以指定（Boss 死亡掉落就在 Boss 尸体处）。
    # 必须一次定好位置再写帧缓冲：先 born 再改 x/y 会在出生格留下一个永不消失的残影。
    if [[ -n "$_px" ]] ; then self[x]=$_px ; else self[x]=$(( (RANDOM % (SCREEN_W - 4)) + 2 )) ; fi
    if [[ -n "$_py" ]] ; then self[y]=$_py ; else self[y]=$GAME_TOP ; fi
    self[cd]=0
    # 帧缓冲（顶层）：出生即占一格
    self[glyph]="$C_REVERSE${self[symbol]}$C_RESET"
    local -i _fi=$(( (${self[y]} - 1) * FB_W + (${self[x]} - 1) ))
    FB_DROP[_fi]=${self[glyph]} FB_DOWNER[_fi]=$1 FB_TOP+=("$_fi")
}
# 退役：清掉它在顶层帧缓冲占的那一格（owner 校验，避免误清别人的格）。
# 拾取（bury）和落到屏幕底（bury）都走这里；少了这一步，掉落物被吃掉后
# 它的字符会留在屏幕上，直到别的对象恰好覆盖那一格 —— 就是"静止残影"。
Drop_retire () {
    local -n _dr=$1
    local -i _dx=${_dr[x]} _dy=${_dr[y]}
    (( _dx >= 2 && _dx <= SCREEN_W - 2 && _dy >= GAME_TOP && _dy <= SCREEN_H - 1 )) || return 0
    local -i _di=$(( (_dy - 1) * FB_W + (_dx - 1) ))
    if [[ "${FB_DOWNER[_di]}" == "$1" ]] ; then
        FB_DROP[_di]='' FB_DOWNER[_di]='' FB_TOP+=("$_di")
    fi
    return 0
}

Drop_move () {
    local -n self=$1
    local cd=$(( ${self[cd]} + 1 ))
    (( cd < 6 )) && { self[cd]=$cd ; return 0 ; }
    local -i _oy=${self[y]} _x=${self[x]} _fi
    self[cd]=0 \
    self[y]=$(( _oy + 1 ))
    local -i _ny=${self[y]}
    # 帧缓冲（顶层）：清旧格 + 写新格
    _fi=$(( (_oy - 1) * FB_W + (_x - 1) ))
    if [[ "${FB_DOWNER[_fi]}" == "$1" ]] ; then
        FB_DROP[_fi]='' FB_DOWNER[_fi]='' FB_TOP+=("$_fi")
    fi
    if (( _ny < SCREEN_H - 1 )) ; then
        _fi=$(( (_ny - 1) * FB_W + (_x - 1) ))
        FB_DROP[_fi]=${self[glyph]} FB_DOWNER[_fi]=$1 FB_TOP+=("$_fi")
    fi
    (( _ny >= SCREEN_H - 1 )) && return 1
    return 0
}
