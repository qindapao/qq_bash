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
        {x} => 0
        {y} => 0
        {symbol} => 1
        {dtype} => 1
        {cd} => 0
    '
Drop_born () {
    local -n self=$1
    local t=$2
    self["{dtype}$X"]=$t
    self["{symbol}$X"]=$t

    # 武器掉落（tier 1..5）显示对应武器的主字符，而不是数字。
    # 武器对象在本局 init_game 时已经创建好，这里只查它的 {u}。
    case "$t" in
        1|2|3|4|5)
            if [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] ; then
                local -n _p=$PLAYER
                local _w=${_p["{w$t}$X"]}
                unset -n _p
                if [[ -n "$_w" && -n "${XO_OBJ_POOL[$_w]+_}" ]] ; then
                    local -n _wobj=$_w
                    self["{symbol}$X"]=${_wobj["{u}$X"]}
                    unset -n _wobj
                fi
            fi
            ;;
    esac

    self["{x}$X"]=$(( (RANDOM % (SCREEN_W - 4)) + 2 ))
    self["{y}$X"]=$GAME_TOP
    self["{cd}$X"]=0
}
Drop_move () {
    local -n self=$1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 6 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    self["{y}$X"]=$(( ${self["{y}$X"]} + 1 ))
    (( ${self["{y}$X"]} >= SCREEN_H - 1 )) && return 1
    return 0
}
