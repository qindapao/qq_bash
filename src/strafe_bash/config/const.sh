# config/const.sh — 常量定义（屏幕尺寸、帧率、奖励时长、边框字符）
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[const]++ )) && return 0

# 项目级 ESC 常量：所有转义序列都用它拼，禁止写 \033 字面量
readonly ESC=$'\033'

SCREEN_W=$(tput cols 2>/dev/null)  ; [[ -z "$SCREEN_W" ]] && SCREEN_W=80
(( SCREEN_W > 160 )) && SCREEN_W=160
SCREEN_H=$(tput lines 2>/dev/null) ; [[ -z "$SCREEN_H" ]] && SCREEN_H=24
(( SCREEN_H > 60 )) && SCREEN_H=60

# 声明为整型加速
declare -gi SCREEN_W SCREEN_H

# 空格原型字符串用于切片加速
SPACE_PROTOTYPE_STRING=
printf -v SPACE_PROTOTYPE_STRING '%*s' "$SCREEN_W" ''

STRAFE_SAVE_FILE="${STRAFE_SAVE_FILE:-./.strafe_save}"
# 游戏版本：定义在 config/version.sh（cli.sh 也要用，它在 const.sh 之前加载）
. "$STRAFE_PROJ_DIR/config/version.sh"
declare -gi GAME_TOP=5
declare -gi FPS=30
declare -gi TICK_US=$(( 1000000 / FPS ))
declare -gi ENEMY_LIMIT=40
declare -gi DROP_LIMIT=8
declare -gi WORD_LIMIT=2
declare -gi BOSS_BULLET_LIMIT=48
declare -gi BOMB_DAMAGE=20
# 全局安全阈值：只削极端峰值，不改变正常弹幕密度/HIT 反馈。
declare -gi ENEMY_BULLET_LIMIT=112
declare -gi HIT_FX_LIMIT=100
declare -gi PLAYER_BULLET_LIMIT=160
declare -gi BOSS_LIMIT=1
# Boss 每次切换伤害阶段后的无敌窗口（tick）：3 秒。
# Boss 已经有周期无敌增益，阶段切换只给一个看清换形态的缓冲，不需要 5 秒那么长。
declare -gi BOSS_INV_TICKS=90

# Boss 动态增益（对象级 Mixin）：槽位上限、无敌增益的间歇、回血比例
declare -gi BOSS_BUFF_MAX=2
# 无敌增益的节奏：4 秒无敌 + 6 秒可受伤（打起来才不至于太难）。
# 与阶段切换用的 BOSS_INV_TICKS（3 秒）分开，互不影响；两者重叠时不会叠加。
# 注意：一次循环的周期是两者之和；若把周期写成"只有持续时间"，无敌会首尾相接变成永久。
declare -gi BOSS_BUFF_INV_ON=120       # 无敌 4 秒
declare -gi BOSS_BUFF_INV_OFF=180      # 可受伤 6 秒
declare -gi BOSS_BUFF_HEAL_WAIT=300    # 回血的观察窗口：10 秒内没等到机会就卸载

# 增益：敌跟踪导弹（伤害 1、有燃料、比玩家慢、用敌方配色）
declare -gi BOSS_BUFF_MISSILE_CD=90     # 3 秒一发（稍微提高出弹频率；导弹现在可以被打掉）
declare -gi BOSS_BUFF_MISSILE_FUEL=60   # 燃料：能走 60 格（约 4 秒的移动量），烧完自毁
declare -gi BOSS_BUFF_MISSILE_STEP=3    # 每 3 tick 走 1 格（玩家导弹是每 tick 1 格）
declare -gi BOSS_BUFF_MISSILE_MAX=3     # 同时在场上限，避免叠得太狠
# 导弹字符：U+2B24 BLACK LARGE CIRCLE，East Asian Width = N（单宽，实测对齐）。
# 个别字体缺这个字时可以只改这一个常量（例如换成 'O' 或 '▪' U+25AA）。
BOSS_BUFF_MISSILE_SYM='⬤'

# 扫描电网（Boss 增益 / 我方拾取物 W）
# 每 WAVE_STEP_TICKS 个 tick 走一行：慢速扫描，玩家有时机躲开/看清
declare -gi WAVE_STEP_TICKS=3
declare -gi BOSS_WAVE_DAMAGE=3          # Boss 电网打玩家的伤害
declare -gi BOSS_WAVE_STRIP_SHIELD=1    # 电网无视护盾：命中时把护盾直接打掉
declare -gi PLAYER_WAVE_DAMAGE=30       # 我方电网对敌人的伤害（每敌人每条波只结算一次）
WAVE_SYMBOL='~'             # 电网用的字符（ASCII，宽度无风险）
# Boss 电网的逃生缝：每条波随机挖 WAVE_GAP_COUNT 个 WAVE_GAP_W 格宽的洞。
# 玩家判定点只有中心 1 格，3 格宽的洞足够站；洞里的子弹也不清。
declare -gi WAVE_GAP_COUNT=2
declare -gi WAVE_GAP_W=3
# Boss 电网连发：一次能力放 2..4 根，相邻两根间隔 1..3 秒。
# 允许同屏多条（最多 WAVE_SLOTS 条），缝隙每根重新随机 → 玩家要连续换位躲。
# 24 行终端扫一屏约 1.8 秒、30 行约 2.4 秒，所以 1 秒间隔时最多同时 2~3 条。
declare -gi BOSS_WAVE_BURST_MIN=2
declare -gi BOSS_WAVE_BURST_MAX=4
declare -gi BOSS_WAVE_GAP_MIN=1
declare -gi BOSS_WAVE_GAP_MAX=3

# 增益：我方子弹减速
declare -gi BOSS_BUFF_SLOW_PCT=50       # 弹速降到 50%
declare -gi BOSS_BUFF_SLOW_CD_PCT=150   # 同时射速压到 2/3（cd ×1.5）：只降弹速不会减少输出
declare -gi BONUS_SLOW=$(( 30 * FPS ))  # 持续 30 秒

# 骷髅王 O/X：下方 8 发长排 + 其余 7 个方向，连发 5 波，然后休息约 2.7 秒。
declare -gi SKULL_KING_ROW_BULLETS=8
declare -gi SKULL_KING_RADIAL_BULLETS=7
declare -gi SKULL_KING_WAVE_BULLETS=15
declare -gi SKULL_KING_BURST_RINGS=5
declare -gi SKULL_KING_RING_GAP=7
declare -gi SKULL_KING_REST=80
declare -gi SKULL_KING_FIRST_SHOT=30

# 子弹库：tier 1 预留（暂不使用），tier 2..5 每档在开局时随机抽一个类。
# 默认子弹是独立的 BulletTypeDefault（tier 0），不在这些库里，始终由玩家携带。
# 以后给某一档加变体，只需往对应数组里追加类名。
# 当前 4 种（默认除外）：quantum / star / at / dollar，对应 tier 2..5。
declare -a BULLET_LIB_1=()
declare -a BULLET_LIB_2=(BulletTypeLaser)
declare -a BULLET_LIB_3=(BulletTypeStar)
declare -a BULLET_LIB_4=(BulletTypeAt)
declare -a BULLET_LIB_5=(BulletTypeDollar)

declare -gi BONUS_T2=$(( 60 * FPS ))
declare -gi BONUS_T3=$(( 50 * FPS ))
declare -gi BONUS_T4=$(( 40 * FPS ))
declare -gi BONUS_T5=$(( 30 * FPS ))
declare -gi BONUS_MT=$(( 45 * FPS ))
declare -gi BONUS_LT=$(( 60 * FPS ))
declare -gi BONUS_ST=$(( 30 * FPS ))
declare -gi CLEAR_SCORE_BONUS=1000
declare -gi BOSS_SCORE_BONUS=2000

FRAME_H='─'
FRAME_V='│'
FRAME_TL='┌'
FRAME_TR='┐'
FRAME_BL='└'
FRAME_BR='┘'

LOCALE_UTF8=0
case "${LC_ALL:-${LC_CTYPE:-$LANG}}" in
    *UTF-8*|*utf8*|*UTF8*) LOCALE_UTF8=1 ;;
esac

# 渲染帧率（独立于逻辑帧率，控制画面刷新频率）
declare -gi RENDER_FPS=30
declare -gi RENDER_US=$(( 1000000 / RENDER_FPS ))

