# classes/base_types.sh — BulletType
[[ -n "${_STRAFE_BULLETTYPE_SH:-}" ]] && return 0
_STRAFE_BULLETTYPE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"

# 当前继承树，一旦改变继承层级需要更新这个注释
# 所有类都是 Base 的后代：Base 及其子类默认扁平（FLT=1），BaseX 是唯一的树类（FLT=0）。
# CLASS_INHER_TREE(1) -> 
#     {Base}
#         {BaseX} => null\u001c
#         {BulletType}
#             {BulletTypeAt} => null\u001c
#             {BulletTypeDefault} => null\u001c
#             {BulletTypeDollar} => null\u001c
#             {BulletTypeLaser} => null\u001c
#             {BulletTypeStar} => null\u001c
#         {Entity}
#             {BossBase}
#                 {Boss} => null\u001c
#                 {BossSpinner} => null\u001c
#                 {SkullKing} => null\u001c
#             {Bullet} => null\u001c
#             {Drop} => null\u001c
#             {Enemy}
#                 {EnemyB} => null\u001c
#                 {EnemyM} => null\u001c
#                 {EnemyQ} => null\u001c
#                 {EnemyV} => null\u001c
#             {Missile} => null\u001c
#             {Plane}
#                 {PlaneBee} => null\u001c
#                 {PlaneEagle} => null\u001c
#                 {PlaneHornet} => null\u001c
#                 {PlaneIl2} => null\u001c
#             {Word} => null\u001c
#     max_index => 29
#
# Mixin（只列名字，细节看各自文件）：
#   类级 {MIX}：     M_Blink  M_LongBlink  M_Ram
#   对象级 {OBJMIX}：M_BuffHeal  M_BuffInvuln  M_BuffMissile  M_BuffSlow  M_BuffWave

# Entity 抽象基类：所有游戏实体的公共属性
readonly EntityStaticTemplate='
    EntityObj ->
        {CLS} => Entity
        {SUP} => Base
        {MIX} => 
        # 逻辑坐标：x = 屏幕列，y = 屏幕行（都从 1 开始，画面上直接用）
        {x} => 0
        {y} => 0
        # 上一帧画过的坐标：渲染分「擦上一帧 / 画当前帧」两步，靠它定位要擦的格子
        {prev_x} => 0
        {prev_y} => 0
    '

# Entity 退役钩子：如果游戏层加载了擦除函数，擦除最后一次画面
# 纯 xo 测试环境（没加载 render 层）时 declare -F 为假，跳过。
# 注意：retire 是"离开世界"的统一钩子，bury（销毁）和 fire（返聘）都会调它。
Entity_retire () {
    if declare -F _render_erase_one >/dev/null ; then
        _render_erase_one "$1"
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
        # 档位：0=默认弹（开局自带，不参与掉落），2..5=可掉落的四档武器
        {tier} => 1
        # 单发伤害（激光用它承载「威力」，见 BulletTypeLaser）
        {damage} => 1
        # 发射冷却（tick）：越小射速越快，DPS ≈ damage × 弹道数 / cd
        {cd} => 6
        # 弹速（格/tick）：只决定命中延迟，不影响 DPS（同屏上限远大于在飞数量）
        {spd} => 2
        # 是否量子能量武器：1=只有一道，把 lanes+1 当威力与颜色等级
        {laser} => 0
        # 8 个方向的子弹字符：u=上 d=下 l=左 r=右（斜向为 ul/ur/dl/dr）
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
# 字段含义同 BulletType，差异：tier=0（不参与掉落）、laser=0 保持默认（有该字段）
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

# tier 2：量子能量武器。只有一道，lanes+1 作为威力（1..5），威力用颜色区分。
# 注意：模板值会经 str_unescape 反解一层，字面反斜杠必须写成 \\。
# 字段含义同 BulletType，差异：cd=2（改成 1 会碾压所有高档武器）、laser=1
readonly BulletTypeLaserStaticTemplate='
    BulletTypeLaserObj ->
        {CLS} => BulletTypeLaser
        {SUP} => BulletType
        {MIX} => 
        {tier} => 2
        {damage} => 1
        {cd} => 2
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
# 字段含义同 BulletType，差异：tier=3、伤害 2、cd=4、字符未用 #
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
# 字段含义同 BulletType，差异：tier=4、伤害 3、cd=5、字符 @
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
# 字段含义同 BulletType，差异：tier=5、伤害 4、cd=6、字符 $
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
