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
ENEMY_LIMIT=20
DROP_LIMIT=8
WORD_LIMIT=2

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

