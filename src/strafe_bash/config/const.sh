# config/const.sh — 常量定义（屏幕尺寸、帧率、奖励时长、边框字符）
[[ -n "${_STRAFE_CONST_SH:-}" ]] && return 0
_STRAFE_CONST_SH=1

SCREEN_W=$(tput cols 2>/dev/null)  ; [[ -z "$SCREEN_W" ]] && SCREEN_W=80
(( SCREEN_W > 160 )) && SCREEN_W=160
SCREEN_H=$(tput lines 2>/dev/null) ; [[ -z "$SCREEN_H" ]] && SCREEN_H=24
(( SCREEN_H > 60 )) && SCREEN_H=60

STRAFE_SAVE_FILE="${STRAFE_SAVE_FILE:-./.strafe_save}"
GAME_TOP=5
FPS=30
TICK_US=$(( 1000000 / FPS ))
ENEMY_LIMIT=25
DROP_LIMIT=8
WORD_LIMIT=2
BOSS_BULLET_LIMIT=48

# 子弹库：tier 1 预留（暂不使用），tier 2..5 每档在开局时随机抽一个类。
# 默认子弹是独立的 BulletTypeDefault（tier 0），不在这些库里，始终由玩家携带。
# 以后给某一档加变体，只需往对应数组里追加类名。
# 当前 4 种（默认除外）：laser / star / at / dollar，对应 tier 2..5。
declare -a BULLET_LIB_1=()
declare -a BULLET_LIB_2=(BulletTypeLaser)
declare -a BULLET_LIB_3=(BulletTypeStar)
declare -a BULLET_LIB_4=(BulletTypeAt)
declare -a BULLET_LIB_5=(BulletTypeDollar)

BONUS_T2=$(( 60 * FPS ))
BONUS_T3=$(( 50 * FPS ))
BONUS_T4=$(( 40 * FPS ))
BONUS_T5=$(( 30 * FPS ))
BONUS_MT=$(( 30 * FPS ))
BONUS_LT=$(( 60 * FPS ))
BONUS_ST=$(( 30 * FPS ))

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
RENDER_FPS=60
RENDER_US=$(( 1000000 / RENDER_FPS ))

