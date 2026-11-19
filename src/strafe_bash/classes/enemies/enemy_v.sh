# classes/enemies/enemy_v.sh — EnemyV
[[ -n "${_STRAFE_ENEMY_V_SH:-}" ]] && return 0
_STRAFE_ENEMY_V_SH=1
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"

readonly EnemyVStaticTemplate='
    EnemyVObj ->
        {CLS} => EnemyV
        {SUP} => Enemy
        {MIX} => 
        # 单字符符号（有 art，仅调试用）
        {symbol} => v
        # 血量 1：一碰就碎的最基础杂兵
        {hp} => 1
        {maxhp} => 1
        # 击杀得分基数
        {score} => 10
        # 包围盒（3x2，与 art 同尺寸）
        {w} => 3
        {h} => 2
    '
EnemyV_born () {
    local -n self=$1
    Enemy_born "$1"
    self[art]=$' v \n/ \\'
}
EnemyV_move () {
    local -n self=$1
    _enemy_fire "$1" 2 '.' 1
    local cd=$(( ${self[cd]} + 1 ))
    (( cd < 6 )) && { self[cd]=$cd ; return 0 ; }
    self[cd]=0
    local _ax=${self[x]} _w=${self[w]} _h=${self[h]}
    (( RANDOM % 3 == 0 )) && {
        local dx=$(( (RANDOM % 2) * 2 - 1 ))
        local x=$(( _ax + dx ))
        (( x < 2 )) && x=2
        (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
        self[x]=$x
    }
    self[y]=$(( ${self[y]} + 1 ))
    (( ${self[y]} + _h > SCREEN_H - 1 )) && return 1
    return 0
}
