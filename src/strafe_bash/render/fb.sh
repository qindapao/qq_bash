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
[[ -n "${_STRAFE_FB_SH:-}" ]] && return 0
_STRAFE_FB_SH=1

. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/render/ansi.sh"

declare -ga FB_CELL=()      # 屏幕真值，索引 = (y-1)*FB_W + (x-1)
declare -ga FB_DIRTY=()     # 本帧写过的格索引（可能有重复，后写的生效）
declare -ga FB_OWNER=()     # 每格最后写入者的句柄（0/空 = 无主），清格前要先核对
declare -gi FB_W=0 FB_H=0 FB_N=0

# 初始化/重置（$1=宽 $2=高，默认取屏幕尺寸）
fb_init () {
    FB_W=${1:-$SCREEN_W} FB_H=${2:-$SCREEN_H} FB_N=$(( FB_W * FB_H )) \
    FB_CELL=() \
    FB_DIRTY=() \
    FB_OWNER=()
    local -i i
    for (( i=0 ; i<FB_N ; i++ )) ; do FB_CELL[i]='' ; FB_OWNER[i]='' ; done
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

# 把脏格输出到 FRAME_BUF，然后清空脏表
fb_emit () {
    local -i idx y x
    local cell _buf=''
    for idx in "${FB_DIRTY[@]}" ; do
        cell=${FB_CELL[idx]} y=$(( idx / FB_W + 1 )) x=$(( idx % FB_W + 1 ))
        if [[ -n "$cell" ]] ; then
            _buf+="$ESC[$y;${x}H$cell"
        else
            _buf+="$ESC[$y;${x}H "
        fi
    done
    FRAME_BUF+=$_buf FB_DIRTY=()
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
