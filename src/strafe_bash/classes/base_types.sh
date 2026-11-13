# classes/base_types.sh — BulletType
[[ -n "${_STRAFE_BULLETTYPE_SH:-}" ]] && return 0
_STRAFE_BULLETTYPE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"

readonly BulletTypeStaticTemplate='
    BulletTypeObj ->
        {CLS} => BulletType
        {SUP} => Base
        {MIX} => 
        {symbol} => .
        {damage} => 1
    '
BulletType_born () {
    local -n self=$1
    [[ -n "$2" ]] && self["{symbol}$X"]=$2
    [[ -n "$3" ]] && self["{damage}$X"]=$3
}
