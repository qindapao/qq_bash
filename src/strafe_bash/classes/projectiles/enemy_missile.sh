# classes/projectiles/enemy_missile.sh — 敌方跟踪导弹（Boss 增益产物）
#
# 与玩家 Missile 的区别：伤害只有 1、有燃料（烧完自毁）、每 2 tick 走 1 格（更慢）、
# 用敌方子弹的配色。
# 继承 EnemyBullet：因此自动进 ENEMY_BULLETS、自动被护盾吸收、自动复用现有的
# 碰撞 / 擦除 / 渲染路径 —— 不需要为它加任何新的集合或分支。
[[ -n "${_STRAFE_ENEMY_MISSILE_SH:-}" ]] && return 0
_STRAFE_ENEMY_MISSILE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"

readonly EnemyMissileStaticTemplate='
    EnemyMissileObj ->
        {CLS} => EnemyMissile
        {SUP} => EnemyBullet
        {MIX} => 
        # 位置（贪心追踪玩家，每 step tick 走一格）
        {x} => 0
        {y} => 0
        # 符号：统一实心大圆点（单宽 N 类字符），方向看移动即可
        {symbol} => v
        # 伤害固定 1：靠数量而不是单体爆发施压
        {damage} => 1
        # 燃料：每走一格 -1，烧完自毁（不会无限追）
        {fuel} => 30
        # 移动间隔（tick）：每 step tick 走一格
        {step} => 2
        # 颜色覆盖：出生时写入加粗亮红
        {color} => 
    '
EnemyMissile_born () {
    local -n self=$1
    self["{x}$X"]=$2 self["{y}$X"]=$3 \
         self["{fuel}$X"]=${4:-$BOSS_BUFF_MISSILE_FUEL} \
         self["{step}$X"]=${5:-$BOSS_BUFF_MISSILE_STEP} \
         self["{damage}$X"]=1
    # 实心大圆点（单宽）+ 加粗亮红：在弹幕里最容易分辨；颜色是直接拼进渲染的前缀
    self["{symbol}$X"]=$BOSS_BUFF_MISSILE_SYM
    self["{color}$X"]="${C_BOLD}${C_RED}"
    self["{cd}$X"]=0
}

# 易变字段（复用前要恢复）：只有渲染写入的位置句柄；其余字段每次 _born 都重设。
readonly EnemyMissileResetFields='prev_x prev_y'

# 死亡清理统一由 play_game 的 _enemy_bullet_bury 负责（它会在 bury 前登记擦除格），
# 所以这里只负责返回 1 表示"我该消失了"。

# 贪心追踪玩家：每 step 个 tick 走一格，燃料每走一格 -1，烧完返回 1（自毁）。
EnemyMissile_move () {
    local -n self=$1
    local -i cd=$(( ${self["{cd}$X"]:-0} + 1 )) step=${self["{step}$X"]:-2}
    (( step < 1 )) && step=1
    if (( cd < step )) ; then
        self["{cd}$X"]=$cd
        return 0
    fi
    self["{cd}$X"]=0

    local -i fuel=$(( ${self["{fuel}$X"]:-0} - 1 ))
    if (( fuel <= 0 )) ; then
        return 1                     # 燃料烧完：消失
    fi
    self["{fuel}$X"]=$fuel

    local -i x=${self["{x}$X"]} y=${self["{y}$X"]} vx=0 vy=0
    if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        local -i px=${OBJ_player["{x}$X"]} py=${OBJ_player["{y}$X"]}
        (( px < x )) && vx=-1 ; (( px > x )) && vx=1
        (( py < y )) && vy=-1 ; (( py > y )) && vy=1
    else
        vy=1
    fi
    # 符号固定为实心大圆点：方向看它怎么移动即可，不占用字符宽度去表达朝向
    x=$(( x + vx )) ; y=$(( y + vy ))
    self["{x}$X"]=$x self["{y}$X"]=$y
    if (( x < 2 || x > SCREEN_W - 2 || y < GAME_TOP || y >= SCREEN_H - 1 )) ; then
        return 1
    fi
    return 0
}
