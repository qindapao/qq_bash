# classes/enemies/enemy_v.sh — EnemyV
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[enemy_v]++ )) && return 0
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"

# 类变量和方法声明
declare -gA XO_CLASS_FLAT_OBJ_VARS XO_CLASS_METHODS
XO_CLASS_FLAT_OBJ_VARS[EnemyVObj]=1
XO_CLASS_METHODS[EnemyV]='born move'

declare -gA EnemyVObj=(
    [{CLS}$X]='EnemyV'
    [{SUP}$X]='Enemy'
    [{MIX}$X]=''
    # 单字符符号（有 art，仅调试用）
    [symbol]='v'
    # 血量 1：一碰就碎的最基础杂兵
    [hp]='1'
    [maxhp]='1'
    # 击杀得分基数
    [score]='10'
    # 包围盒（3x2，与 art 同尺寸）
    [w]='3'
    [h]='2'
)
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
