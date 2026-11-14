# render/frame.sh — 绘制边框
[[ -n "${_STRAFE_FRAME_SH:-}" ]] && return 0
_STRAFE_FRAME_SH=1
. "${BASH_SOURCE[0]%/*}/../config/const.sh"

draw_frame () {
    local _w=$SCREEN_W _h=$SCREEN_H
    local _i _hline=''
    for (( _i=0 ; _i<_w-2 ; _i++ )) ; do _hline+="$FRAME_H" ; done
    local _out='' _t
    printf -v _t '\033[1;1H%s%s%s' "$FRAME_TL" "$_hline" "$FRAME_TR"
    _out+=$_t
    printf -v _t '\033[%d;1H%s%s%s' "$_h" "$FRAME_BL" "$_hline" "$FRAME_BR"
    _out+=$_t
    for (( _i=2 ; _i<_h ; _i++ )) ; do
        printf -v _t '\033[%d;1H%s\033[%d;%dH%s' "$_i" "$FRAME_V" "$_i" "$_w" "$FRAME_V"
        _out+=$_t
    done
    printf '%s' "$_out"
}
