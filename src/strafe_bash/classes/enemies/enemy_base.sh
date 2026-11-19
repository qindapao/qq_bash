# classes/enemies/enemy_base.sh — Enemy 基类 + _enemy_fire
[[ -n "${_STRAFE_ENEMY_BASE_SH:-}" ]] && return 0
_STRAFE_ENEMY_BASE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/soa_bullets.sh"

readonly EnemyStaticTemplate='
    EnemyObj ->
        {CLS} => Enemy
        {SUP} => Entity
        {MIX} => 
        # 位置与包围盒（w/h 单位格，碰撞与渲染都用它）
        {x} => 0
        {y} => 0
        # 单字符符号：没有 art 的极简怪用它显示
        {symbol} => 
        # 血量：归零即死；maxhp 供 UI/回血参考
        {hp} => 1
        {maxhp} => 1
        # 击杀得分基数（游戏层按分数倍率折算）
        {score} => 0
        # 通用计时器：各怪自己解释（开火节拍/换向等）
        {cd} => 0
        # 每 tick 的位移量（vx 横 vy 纵，1=向下）
        {vx} => 0
        {vy} => 1
        # 包围盒
        {w} => 1
        {h} => 1
        # 当前立绘；prev_art 是上一帧的立绘（换形态时清旧图用）
        {art} => 
        {prev_art} => 
    '
Enemy_born () {
    local -n self=$1
    local w=${self[w]:-1}
    (( w < 1 )) && w=1
    self[x]=$(( RANDOM % (SCREEN_W - 2 - w) + 2 )) \
    self[y]=$GAME_TOP self[vx]=0 self[vy]=1 \
    self[cd]=0
}

_enemy_fire () {
    local e=$1 percent=$2 esym=$3 edmg=$4
    (( RANDOM % 100 < percent )) || return 0
    local -n _e=$e
    local _fw=${_e[w]} \
          _fy=$(( ${_e[y]} + ${_e[h]} ))
    local _fx=$(( ${_e[x]} + _fw / 2 ))
    enemy_bullet_spawn EnemyBullet "$_fx" "$_fy" "$esym" "$edmg"
}
