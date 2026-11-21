# classes/enemies/enemy_b.sh — EnemyB
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[enemy_b]++ )) && return 0
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"

# 类变量和方法声明
declare -gA XO_CLASS_FLAT_OBJ_VARS XO_CLASS_METHODS
XO_CLASS_FLAT_OBJ_VARS[EnemyBObj]=1
XO_CLASS_METHODS[EnemyB]='born move'


declare -gA EnemyBObj=(
    [{CLS}$X]='EnemyB'
    [{SUP}$X]='Enemy'
    [{MIX}$X]=''
    # 单字符符号（有 art，仅调试用）
    [symbol]='B'
    # 血量 40：中 bosses 的小 BOSS，会掉武器
    [hp]='40'
    [maxhp]='40'
    # 击杀得分基数
    [score]='500'
    # 包围盒（5x3，与 art 同尺寸）
    [w]='5'
    [h]='3'
)
EnemyB_born () {
    local -n self=$1
    Enemy_born "$1"
    self[art]=$' ___ \n| B |\n|___|'
}
EnemyB_move () {
    local -n self=$1
    _enemy_fire "$1" 3 '+' 3
    local cd=$(( ${self[cd]} + 1 ))
    (( cd < 14 )) && { self[cd]=$cd ; return 0 ; }
    self[cd]=0
    local _ax=${self[x]} _w=${self[w]} _h=${self[h]} \
          vx=${self[vx]}
    (( RANDOM % 4 == 0 )) && vx=$(( (RANDOM % 3) - 1 ))
    self[vx]=$vx
    local x=$(( _ax + vx ))
    (( x < 2 )) && x=2
    (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
    self[x]=$x
    local vy=${self[vy]}
    # 向下状态更稳定：向上约 8 次移动就会翻回向下，
    # 向下只有 1/3 的变向概率转向上，让 B 更容易触底。
    if (( RANDOM % 8 == 0 )) ; then
        if (( vy < 0 )) ; then
            vy=1
        elif (( RANDOM % 3 == 0 )) ; then
            vy=-1
        fi
    fi
    local y=$(( ${self[y]} + vy ))
    if (( y + _h >= SCREEN_H - 1 )) ; then
        # 概率从底部离场，给刷新新怪（尤其第二只 Boss）腾出位置
        (( RANDOM % 100 < 40 )) && return 1
        y=$(( SCREEN_H - 2 - _h )) ; vy=-1
    elif (( y < GAME_TOP )) ; then
        y=$GAME_TOP ; vy=1
    fi
    self[vy]=$vy self[y]=$y
    return 0
}
