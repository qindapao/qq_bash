# classes/pickups/drop.sh — Drop
[[ -n "${_STRAFE_DROP_SH:-}" ]] && return 0
_STRAFE_DROP_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
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
    self["{dtype}$X"]=$2
    self["{symbol}$X"]=$2
    self["{x}$X"]=$(( (RANDOM % (SCREEN_W - 4)) + 2 ))
    self["{y}$X"]=$GAME_TOP
    self["{cd}$X"]=0
}
Drop_move () {
    local -n self=$1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 6 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    printf '\033[%d;%dH ' "${self["{y}$X"]}" "${self["{x}$X"]}"
    self["{y}$X"]=$(( ${self["{y}$X"]} + 1 ))
    (( ${self["{y}$X"]} >= SCREEN_H - 1 )) && return 1
    return 0
}
