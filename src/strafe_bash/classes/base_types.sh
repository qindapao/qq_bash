# classes/base_types.sh — BulletType
[[ -n "${_STRAFE_BULLETTYPE_SH:-}" ]] && return 0
_STRAFE_BULLETTYPE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"

# 当前继承树，一旦改变继承层级需要更新这个注释
# CLASS_INHER_TREE(1) -> 
#     {Base}
#         {BulletType} => null\u001c
#         {Entity}
#             {Missile} => null\u001c
#             {Boss} => null\u001c
#             {Bullet} => null\u001c
#             {EnemyBullet} => null\u001c
#             {Enemy}
#                 {EnemyQ} => null\u001c
#                 {EnemyV} => null\u001c
#                 {EnemyB} => null\u001c
#                 {EnemyM} => null\u001c
#             {Drop} => null\u001c
#             {Plane} => null\u001c
#             {Word} => null\u001c
#     max_index => 17

# Entity 抽象基类：所有游戏实体的公共属性
readonly EntityStaticTemplate='
    EntityObj ->
        {CLS} => Entity
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {prev_x} => 0
        {prev_y} => 0
    '


# 这个类不是一个场景实体，不参与移动
readonly BulletTypeStaticTemplate='
    BulletTypeObj ->
        {CLS} => BulletType
        {SUP} => Base
        {MIX} => 
        {symbol} => .
        {damage} => 1
    '
BulletType_born () {
    local -n self=$1
    [[ -n "$2" ]] && self["{symbol}$X"]=$2
    [[ -n "$3" ]] && self["{damage}$X"]=$3
}
