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

# Entity 析构钩子：如果游戏层加载了擦除函数，擦除最后一次画面
# 纯 xo 测试环境（没加载 render 层）时 declare -F 为假，跳过
Entity_kill () {
    local obj=$1
    if declare -F _render_erase_one >/dev/null ; then
        _render_erase_one "$obj"
    fi
}


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
