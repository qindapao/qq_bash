# classes/enemies/enemy_m.sh — EnemyM
[[ -n "${_STRAFE_ENEMY_M_SH:-}" ]] && return 0
_STRAFE_ENEMY_M_SH=1
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"

readonly EnemyMStaticTemplate='
    EnemyMObj ->
        {CLS} => EnemyM
        {SUP} => Enemy
        {MIX} => 
        # 单字符符号（有 art，仅调试用）
        {symbol} => M
        # 血量 10：入门级带血条小怪
        {hp} => 10
        {maxhp} => 10
        # 击杀得分基数
        {score} => 100
        # 包围盒（5x3，与 art 同尺寸）
        {w} => 5
        {h} => 3
    '
EnemyM_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' ___ \n| M |\n|___|'
}
EnemyM_move () {
    local -n self=$1
    _enemy_fire "$1" 4 '+' 3
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 14 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    (( RANDOM % 3 == 0 )) && {
        local dx=$(( (RANDOM % 2) * 2 - 1 ))
        local x=$(( _ax + dx ))
        (( x < 2 )) && x=2
        (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
        self["{x}$X"]=$x
    }
    local vy=${self["{vy}$X"]}
    # 和 B 一样：向上状态很快翻回向下，向下状态更稳定，
    # 避免 M 长时间在空中上下飘、抢 Boss 的戏。
    if (( RANDOM % 7 == 0 )) ; then
        if (( vy < 0 )) ; then
            vy=1
        elif (( RANDOM % 3 == 0 )) ; then
            vy=-1
        fi
    fi
    self["{vy}$X"]=$vy
    local y=$(( ${self["{y}$X"]} + vy ))
    (( y < GAME_TOP )) && { y=$GAME_TOP ; self["{vy}$X"]=1 ; }
    self["{y}$X"]=$y
    (( y + _h > SCREEN_H - 1 )) && return 1
    return 0
}
