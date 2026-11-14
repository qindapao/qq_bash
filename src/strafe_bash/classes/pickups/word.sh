# classes/pickups/word.sh — Word
[[ -n "${_STRAFE_WORD_SH:-}" ]] && return 0
_STRAFE_WORD_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"

readonly WordStaticTemplate='
    WordObj ->
        {CLS} => Word
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {text} => 
        {len} => 0
        {vx} => 0
        {cd} => 0
    '
Word_born () {
    local -n self=$1
    self["{text}$X"]=$2
    local _w
    str_display_width "$2" _w
    self["{len}$X"]=$_w
    self["{y}$X"]=$GAME_TOP
    local _maxx=$(( SCREEN_W - 3 - _w ))
    (( _maxx < 2 )) && _maxx=2
    self["{x}$X"]=$(( RANDOM % (_maxx - 2 + 1) + 2 ))
    self["{vx}$X"]=0
    self["{cd}$X"]=0
}
Word_move () {
    local -n self=$1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 4 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0

    local _x=${self["{x}$X"]} _y=${self["{y}$X"]} _len=${self["{len}$X"]}

    local _len_eff=$_len
    (( _x + _len_eff > SCREEN_W - 1 )) && _len_eff=$(( SCREEN_W - 1 - _x ))
    (( _len_eff < 0 )) && _len_eff=0
    (( _len_eff > 0 )) && printf '\033[%d;%dH%*s' "$_y" "$_x" "$_len_eff" ''

    if (( RANDOM % 4 == 0 )) ; then
        self["{vx}$X"]=$(( (RANDOM % 3) - 1 ))
    fi
    local vx=${self["{vx}$X"]}
    local nx=$(( _x + vx ))
    (( nx < 2 )) && { nx=2 ; self["{vx}$X"]=0 ; }
    local _maxx=$(( SCREEN_W - 3 - _len ))
    (( nx > _maxx )) && { nx=$_maxx ; self["{vx}$X"]=0 ; }
    self["{x}$X"]=$nx

    self["{y}$X"]=$(( _y + 1 ))
    (( ${self["{y}$X"]} >= SCREEN_H - 1 )) && return 1
    return 0
}
