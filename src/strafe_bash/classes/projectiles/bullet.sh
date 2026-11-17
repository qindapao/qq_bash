# classes/projectiles/bullet.sh — Bullet
[[ -n "${_STRAFE_BULLET_SH:-}" ]] && return 0
_STRAFE_BULLET_SH=1
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
    '
Bullet_born () {
    local -n self=$1
    self["{x}$X"]=$2 self["{y}$X"]=$3 self["{symbol}$X"]=$4 \
         self["{damage}$X"]=$5 self["{vx}$X"]=${6:-0} self["{vy}$X"]=${7:--1}
}

# 可回收类的易变字段：fire 时只把这几个恢复成模板默认值（其余字段每次 _born 都重设）。
#   prev_x/prev_y —— 渲染每帧写入；不清会让返聘出来的第一帧擦错格子
#   color        —— 激光按威力写入颜色；不清会让普通子弹继承上一任的激光色
readonly BulletResetFields='prev_x prev_y color'
Bullet_move () {
    local -n self=$1
    self["{x}$X"]=$(( ${self["{x}$X"]} + ${self["{vx}$X"]} )) \
         self["{y}$X"]=$(( ${self["{y}$X"]} + ${self["{vy}$X"]} ))
    (( ${self["{y}$X"]} < GAME_TOP )) && return 1
    (( ${self["{x}$X"]} < 2 )) && return 1
    (( ${self["{x}$X"]} > SCREEN_W - 2 )) && return 1
    return 0
}
