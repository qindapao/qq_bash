# classes/enemies/enemy_q.sh — EnemyQ
[[ -n "${_STRAFE_ENEMY_Q_SH:-}" ]] && return 0
_STRAFE_ENEMY_Q_SH=1
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"

readonly EnemyQStaticTemplate='
    EnemyQObj ->
        {CLS} => EnemyQ
        {SUP} => Enemy
        {MIX} => 
        # 单字符符号（有 art，仅调试用）
        {symbol} => Q
        # 血量 5：普通杂兵
        {hp} => 5
        {maxhp} => 5
        # 击杀得分基数
        {score} => 30
        # 包围盒（3x2，与 art 同尺寸）
        {w} => 3
        {h} => 2
    '
EnemyQ_born () {
    local -n self=$1
    Enemy_born "$1"
    self[art]=$' Q \n[_]'
}
EnemyQ_move () {
    local -n self=$1
    _enemy_fire "$1" 3 '.' 1
    local cd=$(( ${self[cd]} + 1 ))
    (( cd < 10 )) && { self[cd]=$cd ; return 0 ; }
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
