# classes/enemies/enemy_b.sh — EnemyB
[[ -n "${_STRAFE_ENEMY_B_SH:-}" ]] && return 0
_STRAFE_ENEMY_B_SH=1
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"

readonly EnemyBStaticTemplate='
    EnemyBObj ->
        {CLS} => EnemyB
        {SUP} => Enemy
        {MIX} => 
        {symbol} => B
        {hp} => 30
        {maxhp} => 30
        {score} => 500
        {w} => 5
        {h} => 3
    '
EnemyB_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' ___ \n| B |\n|___|'
}
EnemyB_move () {
    local -n self=$1
    _enemy_fire "$1" 3 '+' 3
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 14 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    local vx=${self["{vx}$X"]}
    (( RANDOM % 4 == 0 )) && vx=$(( (RANDOM % 3) - 1 ))
    self["{vx}$X"]=$vx
    local x=$(( _ax + vx ))
    (( x < 2 )) && x=2
    (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
    self["{x}$X"]=$x
    local vy=${self["{vy}$X"]}
    # 向下状态更稳定：向上约 8 次移动就会翻回向下，
    # 向下只有 1/3 的变向概率转向上，让 B 更容易触底。
    if (( RANDOM % 8 == 0 )) ; then
        if (( vy < 0 )) ; then
            vy=1
        elif (( RANDOM % 3 == 0 )) ; then
            vy=-1
        fi
    fi
    local y=$(( ${self["{y}$X"]} + vy ))
    if (( y + _h >= SCREEN_H - 1 )) ; then
        # 概率从底部离场，给刷新新怪（尤其第二只 Boss）腾出位置
        (( RANDOM % 100 < 40 )) && return 1
        y=$(( SCREEN_H - 2 - _h )) ; vy=-1
    elif (( y < GAME_TOP )) ; then
        y=$GAME_TOP ; vy=1
    fi
    self["{vy}$X"]=$vy
    self["{y}$X"]=$y
    return 0
}
