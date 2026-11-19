# render/frame.sh — 绘制边框
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[frame]++ )) && return 0
. "${BASH_SOURCE[0]%/*}/../config/const.sh"

draw_frame () {
    # 首次构建后缓存成一条字符串；之后 draw_frame 只付一次 append（开局/读档时用）。
    if [[ -n "${FRAME_BORDER_CACHE:-}" ]] ; then
        FRAME_BUF+=$FRAME_BORDER_CACHE
        return 0
    fi
    local _w=$SCREEN_W _h=$SCREEN_H _hline=''
    local -i _i
    for (( _i=0 ; _i<_w-2 ; _i++ )) ; do _hline+="$FRAME_H" ; done
    local _out='' _t
    _t="$ESC[1;1H$FRAME_TL$_hline$FRAME_TR"
    _out+=$_t
    _out+="$ESC[${_h};1H$FRAME_BL$_hline$FRAME_BR"
    for (( _i=2 ; _i<_h ; _i++ )) ; do
        _out+="$ESC[${_i};1H$FRAME_V$ESC[${_i};${_w}H$FRAME_V"
    done
    FRAME_BORDER_CACHE=$_out
    FRAME_BUF+="$_out"
}
