# classes/projectiles/boss_bullet.sh — BossBullet
[[ -n "${_STRAFE_BOSS_BULLET_SH:-}" ]] && return 0
_STRAFE_BOSS_BULLET_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"

readonly BossBulletStaticTemplate='
    BossBulletObj ->
        {CLS} => BossBullet
        {SUP} => EnemyBullet
        {MIX} => 
        # 符号：按方向取，默认小圆点
        {symbol} => o
        # 单发伤害
        {damage} => 1
        # 每 step 个 tick 走一格的位移量（-1/0/1）
        {vx} => 0
        {vy} => 1
        # 移动间隔（tick）：越大越慢
        {step} => 2
        # 颜色覆盖：空 = 用敌方子弹默认色
        {color} => 
        # 帧缓冲用的成品串（颜色+字符+复位）
        {glyph} => 
    '
BossBullet_born () {
    local -n self=$1
    self["{x}$X"]=$2 self["{y}$X"]=$3 self["{vx}$X"]=$4 self["{vy}$X"]=$5 \
    self["{symbol}$X"]=$6 self["{damage}$X"]=$7 self["{step}$X"]=${8:-2} \
    self["{color}$X"]=${9:-} self["{cd}$X"]=0
    # 帧缓冲：出生即占一格
    self["{glyph}$X"]="${self["{color}$X"]}${self["{symbol}$X"]}$C_RESET"
    local -i _fi=$(( ($3 - 1) * FB_W + ($2 - 1) ))
    FB_CELL[_fi]=${self["{glyph}$X"]} FB_OWNER[_fi]=$1 FB_DIRTY+=("$_fi")
}

# 易变字段（复用前要恢复）：只有渲染写入的位置句柄。
# 其余字段（含 color）每次 _born 都按参数重设。
readonly BossBulletResetFields='prev_x prev_y'
BossBullet_move () {
    local -n self=$1
    local -i cd=$(( ${self["{cd}$X"]:-0} + 1 )) _step=${self["{step}$X"]:-2}
    (( _step < 1 )) && _step=1
    (( cd < _step )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0

    local -i _ox=${self["{x}$X"]} _oy=${self["{y}$X"]}
    local -i x=$(( _ox + ${self["{vx}$X"]:-0} )) \
             y=$(( _oy + ${self["{vy}$X"]:-0} ))
    self["{x}$X"]=$x self["{y}$X"]=$y
    # 帧缓冲：清旧格；新格在场内才写
    local -i _fi
    _fi=$(( (_oy - 1) * FB_W + (_ox - 1) ))
    if [[ "${FB_OWNER[_fi]}" == "$1" ]] ; then
        FB_CELL[_fi]='' ; FB_OWNER[_fi]='' ; FB_DIRTY+=("$_fi")
    fi
    if (( x >= 2 && x <= SCREEN_W - 2 && y >= GAME_TOP && y <= SCREEN_H - 2 )) ; then
        _fi=$(( (y - 1) * FB_W + (x - 1) ))
        FB_CELL[_fi]=${self["{glyph}$X"]} ; FB_OWNER[_fi]=$1 ; FB_DIRTY+=("$_fi")
    fi
    (( x < 2 || x > SCREEN_W - 2 || y < GAME_TOP || y >= SCREEN_H - 1 )) && return 1
    return 0
}
