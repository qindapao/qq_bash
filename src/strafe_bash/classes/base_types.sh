# classes/base_types.sh — BulletType
[[ -n "${_STRAFE_BULLETTYPE_SH:-}" ]] && return 0
_STRAFE_BULLETTYPE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"

# 当前继承树，一旦改变继承层级需要更新这个注释
# CLASS_INHER_TREE(1) -> 
#     {Base}
#         {BulletType} => null\u001c
#             {BulletTypeDefault} => null\u001c
#             {BulletTypeLaser} => null\u001c
#             {BulletTypeStar} => null\u001c
#             {BulletTypeAt} => null\u001c
#             {BulletTypeDollar} => null\u001c
#         {Entity}
#             {BossBase} => null\u001c
#                 {Boss} => null\u001c
#                 {BossSpinner} => null\u001c
#             {Missile} => null\u001c
#             {Bullet} => null\u001c
#             {EnemyBullet} => null\u001c
#                 {BossBullet} => null\u001c
#             {Enemy}
#                 {EnemyQ} => null\u001c
#                 {EnemyV} => null\u001c
#                 {EnemyB} => null\u001c
#                 {EnemyM} => null\u001c
#             {Drop} => null\u001c
#             {Plane}
#                 {PlaneBee} => null\u001c
#                 {PlaneHornet} => null\u001c
#                 {PlaneEagle} => null\u001c
#                 {PlaneIl2} => null\u001c
#             {Word} => null\u001c
#     max_index => 31

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


# 武器描述类（不是场景实体）：每个子弹类型一个独立类。
# 8 个方向各有一个字符；如果所有方向外观一样，就把 8 个字段填成同一个字符。
# 发射时按方向取对应字符，不再在运行时改 {symbol}/{damage}。
readonly BulletTypeStaticTemplate='
    BulletTypeObj ->
        {CLS} => BulletType
        {SUP} => Base
        {MIX} => 
        {tier} => 1
        {damage} => 1
        {cd} => 6
        {spd} => 2
        {laser} => 0
        {u} => .
        {d} => .
        {l} => .
        {r} => .
        {ul} => .
        {ur} => .
        {dl} => .
        {dr} => .
    '

# tier 0：默认子弹（独立于 1..5 号库；玩家开局自带，不参与掉落/随机）
readonly BulletTypeDefaultStaticTemplate='
    BulletTypeDefaultObj ->
        {CLS} => BulletTypeDefault
        {SUP} => BulletType
        {MIX} => 
        {tier} => 0
        {damage} => 1
        {cd} => 6
        {spd} => 2
        {u} => .
        {d} => .
        {l} => .
        {r} => .
        {ul} => .
        {ur} => .
        {dl} => .
        {dr} => .
    '

# tier 2：激光。射速最快，单发伤害最低；8 个方向各自有字符。
# 注意：模板值会经 str_unescape 反解一层，字面反斜杠必须写成 \\。
readonly BulletTypeLaserStaticTemplate='
    BulletTypeLaserObj ->
        {CLS} => BulletTypeLaser
        {SUP} => BulletType
        {MIX} => 
        {tier} => 2
        {damage} => 1
        {cd} => 1
        {spd} => 2
        {laser} => 1
        {u} => |
        {d} => |
        {l} => -
        {r} => -
        {ul} => \\
        {ur} => /
        {dl} => /
        {dr} => \\
    '

# tier 3：星形弹，中等射速 / 中等伤害
readonly BulletTypeStarStaticTemplate='
    BulletTypeStarObj ->
        {CLS} => BulletTypeStar
        {SUP} => BulletType
        {MIX} => 
        {tier} => 3
        {damage} => 2
        {cd} => 4
        {spd} => 2
        {u} => #
        {d} => #
        {l} => #
        {r} => #
        {ul} => #
        {ur} => #
        {dl} => #
        {dr} => #
    '

# tier 4：@ 弹，射速更慢、伤害更高
readonly BulletTypeAtStaticTemplate='
    BulletTypeAtObj ->
        {CLS} => BulletTypeAt
        {SUP} => BulletType
        {MIX} => 
        {tier} => 4
        {damage} => 3
        {cd} => 5
        {spd} => 2
        {u} => @
        {d} => @
        {l} => @
        {r} => @
        {ul} => @
        {ur} => @
        {dl} => @
        {dr} => @
    '

# tier 5：$ 弹，射速最慢、单发伤害最高
readonly BulletTypeDollarStaticTemplate='
    BulletTypeDollarObj ->
        {CLS} => BulletTypeDollar
        {SUP} => BulletType
        {MIX} => 
        {tier} => 5
        {damage} => 4
        {cd} => 6
        {spd} => 2
        {u} => $
        {d} => $
        {l} => $
        {r} => $
        {ul} => $
        {ur} => $
        {dl} => $
        {dr} => $
    '
