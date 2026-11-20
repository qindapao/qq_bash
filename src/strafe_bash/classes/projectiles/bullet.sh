# classes/projectiles/bullet.sh — Bullet
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[bullet]++ )) && return 0
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"

readonly BulletStaticTemplate='
    BulletObj ->
        {CLS} => Bullet
        {SUP} => Entity
        {MIX} => 
        # 位置（每 tick 按 vx/vy 前进）
        {x} => 0
        {y} => 0
        # 子弹字符：由武器类的方向字符决定
        {symbol} => .
        # 单发伤害（激光用它承载威力）
        {damage} => 1
        # 每 tick 的位移量（vx 横 / vy 纵，负数向上）
        {vx} => 0
        {vy} => -1
        # 颜色覆盖：空 = 用玩家子弹默认色；激光按威力写入颜色
        {color} => 
        # 帧缓冲用的成品串（颜色+字符+复位），出生时拼一次
        {glyph} => 
    '
Bullet_born () {
    local -n self=$1
    self[x]=$2 self[y]=$3 self[symbol]=$4 \
    self[damage]=$5 self[vx]=${6:-0} self[vy]=${7:--1}
    # 帧缓冲：出生即占一格（颜色空时用玩家统一弹色，和旧渲染一致）
    self[glyph]="${self[color]:-$C_PLAYER_BULLET}${self[symbol]}$C_RESET"
    local -i _fi=$(( ($3 - 1) * FB_W + ($2 - 1) ))
    FB_CELL[_fi]=${self[glyph]} FB_OWNER[_fi]=$1 FB_DIRTY+=("$_fi")
}

# 退役：清掉它在帧缓冲占的那一格（owner 校验，避免误清别人的格）。
# fire（被电网扫掉、打中敌人）和 bury 都走这里，是子弹格的唯一出口；
# 少了这一步，帧缓冲里会留下"死子弹"的幽灵格，之后该格被别的事件标脏时会把它重画出来。
Bullet_retire () {
    local -n _br=$1
    local -i _bx=${_br[x]} _by=${_br[y]}
    (( _bx >= 2 && _bx <= SCREEN_W - 2 && _by >= GAME_TOP && _by < SCREEN_H - 1 )) || return 0
    local -i _bi=$(( (_by - 1) * FB_W + (_bx - 1) ))
    if [[ "${FB_OWNER[_bi]}" == "$1" ]] ; then
        FB_CELL[_bi]='' FB_OWNER[_bi]='' FB_DIRTY+=("$_bi")
    fi
    return 0
}

# 可回收类的易变字段：fire 时只把这几个恢复成模板默认值（其余字段每次 _born 都重设）。
#   prev_x/prev_y —— 渲染每帧写入；不清会让返聘出来的第一帧擦错格子
#   color        —— 激光按威力写入颜色；不清会让普通子弹继承上一任的激光色
readonly BulletResetFields='prev_x prev_y color'

Bullet_move () {
    local -n self=$1
    self[x]=$(( ${self[x]} + ${self[vx]} )) \
    self[y]=$(( ${self[y]} + ${self[vy]} ))
    (( ${self[y]} < GAME_TOP )) && return 1
    (( ${self[x]} < 2 )) && return 1
    (( ${self[x]} > SCREEN_W - 2 )) && return 1
    return 0
}
