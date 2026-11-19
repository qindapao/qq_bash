# render/fb.sh — 帧缓冲：屏幕真值 + 脏格输出
#
# 用法（热路径请内联，不要调函数）：
#     idx=$(( (y-1)*FB_W + (x-1) ))
#     FB_CELL[idx]=$cell
#     FB_DIRTY+=("$idx")
#
# 约定：
#   - 格子的值 = "颜色转义 + 字符"，空串表示空白格；
#   - 坐标为 1-based（和终端一致），索引为 0-based；
#   - 静止对象不需要写：它的格子还在 FB_CELL 里；
#   - 移动对象写两格：旧格清空、新格写入；
#   - fb_emit 只输出本帧变过的格子，输出后清空脏表。
#
# 帧缓冲与旧渲染器可以并存：旧渲染器照常往 FRAME_BUF 拼，帧缓冲的
# fb_emit 在最后把脏格补上（后写覆盖先写，正好符合"对象在 art 之上"）。
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[fb]++ )) && return 0

. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/render/ansi.sh"

declare -ga FB_CELL=()      # 屏幕真值，索引 = (y-1)*FB_W + (x-1)
declare -ga FB_DIRTY=()     # 本帧写过的格（art 之前输出：子弹/导弹/敌弹）
declare -ga FB_TOP=()       # 顶层格（art 之后输出：掉落物等，旧顺序里画在 art 之上）
declare -ga FB_OWNER=()     # 每格最后写入者的句柄（0/空 = 无主），清格前要先核对
# 掉落物层：旧渲染顺序里它画在子弹之后（压住子弹），所以单独一层做合成，
# 子弹飞过时不会把掉落物覆盖掉。
declare -ga FB_DROP=()
declare -ga FB_DOWNER=()
declare -gi FB_W=0 FB_H=0 FB_N=0

# 初始化/重置（$1=宽 $2=高，默认取屏幕尺寸）
fb_init () {
    FB_W=${1:-$SCREEN_W} FB_H=${2:-$SCREEN_H} FB_N=$(( FB_W * FB_H )) \
    FB_CELL=() \
    FB_DIRTY=() \
    FB_TOP=() \
    FB_OWNER=() \
    FB_DROP=() \
    FB_DOWNER=()
    local -i i
    for (( i=0 ; i<FB_N ; i++ )) ; do FB_CELL[i]='' FB_OWNER[i]='' FB_DROP[i]='' FB_DOWNER[i]='' ; done
    return 0
}

# 写一格（非热路径用；热路径内联上面那三行）
fb_put () {
    local -i y=$1 x=$2
    local cell=$3 owner=${4:-}
    # 逐轴检查：只查 idx 范围会把 (1, W+1) 误判成合法（它正好落到下一行首）
    (( y < 1 || y > FB_H || x < 1 || x > FB_W )) && return 0
    local -i idx=$(( (y - 1) * FB_W + (x - 1) ))
    FB_CELL[idx]=$cell FB_OWNER[idx]=$owner FB_DIRTY+=("$idx")
    return 0
}

# 清一格
fb_clear () {
    fb_put "$1" "$2" ''
}

# 内部：把某个脏表输出到 FRAME_BUF，然后清空它（每帧只调一两次，绑定无所谓）
_fb_emit_list () {
    local -n _dl=$1
    local -i idx y x
    local cell _buf=''
    for idx in "${_dl[@]}" ; do
        cell=${FB_CELL[idx]} y=$(( idx / FB_W + 1 )) x=$(( idx % FB_W + 1 ))
        # 合成：掉落物层优先（旧顺序里它压在子弹之上）
        [[ -n "${FB_DROP[idx]}" ]] && cell=${FB_DROP[idx]}
        if [[ -n "$cell" ]] ; then
            _buf+="$ESC[$y;${x}H$cell"
        else
            _buf+="$ESC[$y;${x}H "
        fi
    done
    FRAME_BUF+=$_buf _dl=()
    return 0
}

# art 之前输出（子弹 / 导弹 / 敌弹）
fb_emit () { _fb_emit_list FB_DIRTY ; }

# art 之后输出（掉落物等：旧渲染顺序里它们画在敌人 art 之上）
fb_emit_top () { _fb_emit_list FB_TOP ; }

# 单格被擦掉之后（特效清格、火花消失）：该格若有帧缓冲对象，重新标脏补画。
# $1=行 $2=列
_fb_touch_cell () {
    local -i _idx=$(( ($1 - 1) * FB_W + ($2 - 1) ))
    [[ -n "${FB_CELL[_idx]}" || -n "${FB_DROP[_idx]}" ]] && FB_DIRTY+=("$_idx")
    return 0
}

# 整行被"整行擦除"擦过之后，把这一行里仍被帧缓冲对象占着的格重新标脏，
# 下一次 emit 就会补画回来（电网擦行、血条行和消息行的 \033[K 都会用）。
# $1=行 $2=起始列 $3=结束列（含）
_fb_touch_row () {
    local -i _x _idx
    for (( _x=$2 ; _x<=$3 ; _x++ )) ; do
        _idx=$(( ($1 - 1) * FB_W + (_x - 1) ))
        [[ -n "${FB_CELL[_idx]}" || -n "${FB_DROP[_idx]}" ]] && FB_DIRTY+=("$_idx")
    done
    return 0
}

# 取一格的当前内容（测试/调试用）
fb_get () {
    local -i idx=$(( ($1 - 1) * FB_W + ($2 - 1) ))
    printf '%s' "${FB_CELL[idx]}"
}

# 载入即初始化：此时 const.sh 已经确定屏幕尺寸，整局只分配一次。
# 测试里可以再调 fb_init 换成小尺寸。
fb_init
