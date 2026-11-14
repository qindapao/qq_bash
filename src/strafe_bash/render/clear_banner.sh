# render/clear_banner.sh — 全清提示横幅（静态 FIGlet 风格，不创建对象）
[[ -n "${_STRAFE_CLEAR_BANNER_SH:-}" ]] && return 0
_STRAFE_CLEAR_BANNER_SH=1
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

declare -a CLEAR_BANNER_LINES=(
' ___  __ __  ___   ___   _     _     ___   _  _  _____  _ '
'| __| \ V / / __| | __| | |   | |   | __| | \ |    |   | |'
'| _|   > <  | |   | _|  | |   | |   | _|  |  \|    |   | |'
'| |_  / . \ | |__ | |_  | |_  | |_  | |_  | |\     |   |_|'
'|___| \_/\_ \___| |___| |___| |___| |___| |_| \_   |_| (_)'
)
CLEAR_BANNER_W=0
for _cb_line in "${CLEAR_BANNER_LINES[@]}" ; do
    (( ${#_cb_line} > CLEAR_BANNER_W )) && CLEAR_BANNER_W=${#_cb_line}
done
unset _cb_line

_clear_banner_start () {
    CLEAR_BANNER_TEXT=${1:-ALL ENEMIES CLEARED}
    CLEAR_BANNER_TICK=60
    CLEAR_BANNER_FRAME=0
}

_clear_banner_clear () {
    local -i y=$1 w=$2 rows=$3
    local -i r
    local _t
    for (( r=0 ; r<rows ; r++ )) ; do
        printf -v _t '\033[%d;%dH%*s' "$((y + r))" "$4" "$w" ''
        FRAME_BUF+="$_t"
    done
}

render_clear_banner () {
    (( CLEAR_BANNER_TICK > 0 )) || return 0

    local -i rows=8
    local -i box_w=$(( CLEAR_BANNER_W + 4 ))
    (( box_w > SCREEN_W - 2 )) && box_w=$(( SCREEN_W - 2 ))
    local -i x=$(( (SCREEN_W - box_w) / 2 + 1 ))
    local -i y=7
    (( y + rows > SCREEN_H )) && y=$(( SCREEN_H - rows ))

    # 先擦掉上一帧的横幅区域
    _clear_banner_clear "$y" "$box_w" "$rows" "$x"

    if (( CLEAR_BANNER_TICK <= 1 )) ; then
        CLEAR_BANNER_TICK=0
        CLEAR_BANNER_FRAME=0
        return 0
    fi

    local _t _line _dash _part
    local _border=$C_CYAN
    local _art=$C_YELLOW
    (( (CLEAR_BANNER_FRAME / 4) % 2 )) && _art=$C_MAGENTA
    local -i reveal=$(( CLEAR_BANNER_FRAME * 7 ))
    (( reveal > CLEAR_BANNER_W )) && reveal=$CLEAR_BANNER_W

    printf -v _dash '%*s' $(( box_w - 2 )) ''
    _dash=${_dash// /-}
    printf -v _t '\033[%d;%dH%s+%s+%s' "$y" "$x" "$_border" "$_dash" "$C_RESET"
    FRAME_BUF+="$_t"

    local -i r=0
    local -i art_y=$(( y + 1 ))
    local -i art_x=$(( x + 1 + (box_w - 2 - CLEAR_BANNER_W) / 2 ))
    local -i left_pad=$(( art_x - x - 1 ))
    local -i right_pad=$(( box_w - 2 - left_pad - CLEAR_BANNER_W ))
    local _artfield
    for _line in "${CLEAR_BANNER_LINES[@]}" ; do
        _part=${_line:0:reveal}
        printf -v _artfield '%-*s' "$CLEAR_BANNER_W" "$_part"
        printf -v _t '\033[%d;%dH%s|%*s%s%s%s%*s%s|%s' \
            "$((art_y + r))" "$x" "$_border" \
            "$left_pad" '' "$_art" "$_artfield" "$C_RESET" \
            "$right_pad" '' "$_border" "$C_RESET"
        FRAME_BUF+="$_t"
        ((r++))
    done

    # 副标题行也要保留左右竖线
    local -i sub_y=$(( y + 6 ))
    printf -v _t '\033[%d;%dH%s|%s' "$sub_y" "$x" "$_border" "$C_RESET"
    FRAME_BUF+="$_t"
    printf -v _t '\033[%d;%dH%s|%s' "$sub_y" "$(( x + box_w - 1 ))" "$_border" "$C_RESET"
    FRAME_BUF+="$_t"

    # 副标题在打字动画完成后出现
    local _sub=${CLEAR_BANNER_TEXT:-ALL ENEMIES CLEARED}
    _sub=${_sub:0:$(( box_w - 2 ))}
    if (( reveal >= CLEAR_BANNER_W )) ; then
        local -i sub_x=$(( x + 1 + (box_w - 2 - ${#_sub}) / 2 ))
        printf -v _t '\033[%d;%dH%s%s%s%s' \
            "$sub_y" "$sub_x" "$C_GREEN" "$C_BOLD" "$_sub" "$C_RESET"
        FRAME_BUF+="$_t"
    fi

    printf -v _t '\033[%d;%dH%s+%s+%s' "$((y + rows - 1))" "$x" "$_border" "$_dash" "$C_RESET"
    FRAME_BUF+="$_t"

    ((CLEAR_BANNER_FRAME++))
    ((CLEAR_BANNER_TICK--))
}
