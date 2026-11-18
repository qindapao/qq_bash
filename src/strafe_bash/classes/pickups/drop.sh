# classes/pickups/drop.sh — Drop
[[ -n "${_STRAFE_DROP_SH:-}" ]] && return 0
_STRAFE_DROP_SH=1
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
    self["{dtype}$X"]=$t \
        self["{symbol}$X"]=$t

    # 武器掉落（tier 1..5）显示对应武器的主字符，而不是数字。
    # 武器对象在本局 init_game 时已经创建好，这里只查它的 {u}。
    case "$t" in
        1|2|3|4|5)
            if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
                local _w=${OBJ_player["{w$t}$X"]}
                if [[ -n "$_w" && -n "${XO_OBJ_POOL[$_w]+_}" ]] ; then
                    local -n _wobj=$_w
                    self["{symbol}$X"]=${_wobj["{u}$X"]}
                fi
            fi
            ;;
    esac

    self["{x}$X"]=$(( (RANDOM % (SCREEN_W - 4)) + 2 )) \
        self["{y}$X"]=$GAME_TOP \
        self["{cd}$X"]=0
    # 帧缓冲（顶层）：出生即占一格
    self["{glyph}$X"]="$C_REVERSE${self["{symbol}$X"]}$C_RESET"
    local -i _fi=$(( (${self["{y}$X"]} - 1) * FB_W + (${self["{x}$X"]} - 1) ))
    FB_DROP[_fi]=${self["{glyph}$X"]} FB_DOWNER[_fi]=$1 FB_TOP+=("$_fi")
}
Drop_move () {
    local -n self=$1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 6 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    local -i _oy=${self["{y}$X"]} _x=${self["{x}$X"]} _fi
    self["{cd}$X"]=0 \
    self["{y}$X"]=$(( _oy + 1 ))
    local -i _ny=${self["{y}$X"]}
    # 帧缓冲（顶层）：清旧格 + 写新格
    _fi=$(( (_oy - 1) * FB_W + (_x - 1) ))
    if [[ "${FB_DOWNER[_fi]}" == "$1" ]] ; then
        FB_DROP[_fi]='' FB_DOWNER[_fi]='' FB_TOP+=("$_fi")
    fi
    if (( _ny < SCREEN_H - 1 )) ; then
        _fi=$(( (_ny - 1) * FB_W + (_x - 1) ))
        FB_DROP[_fi]=${self["{glyph}$X"]} FB_DOWNER[_fi]=$1 FB_TOP+=("$_fi")
    fi
    (( _ny >= SCREEN_H - 1 )) && return 1
    return 0
}
