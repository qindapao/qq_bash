# config/color.sh — ANSI 256 色
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[color]++ )) && return 0

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_FG_DEFAULT=$'\033[39m'

# Dark terminal palette (default)
C_BLUE=$'\033[38;5;33m'
C_RED=$'\033[38;5;196m'
C_ORANGE=$'\033[38;5;208m'
C_YELLOW=$'\033[38;5;226m'
C_GREEN=$'\033[38;5;46m'
C_PURPLE=$'\033[38;5;129m'
C_MAGENTA=$'\033[38;5;201m'
C_CYAN=$'\033[38;5;51m'
# 玩家弹：低饱和暗蓝灰，和敌方高饱和弹幕拉开
C_PLAYER_BULLET=$'\033[38;5;60m'

# On a light terminal the neon palette is hard to read, especially yellow.
# STRAFE_THEME=light forces this palette; auto reads COLORFGBG when available.
_strafe_theme=${STRAFE_THEME:-auto}
if [[ "$_strafe_theme" == "auto" ]] ; then
    _strafe_theme=dark
    if [[ "${COLORFGBG:-}" =~ ^[0-9]+\;([0-9]+)$ ]] ; then
        (( BASH_REMATCH[1] >= 7 )) && _strafe_theme=light
    fi
fi
if [[ "$_strafe_theme" == "light" ]] ; then
    C_BLUE=$'\033[38;5;25m'
    C_RED=$'\033[38;5;124m'
    C_ORANGE=$'\033[38;5;130m'
    C_YELLOW=$'\033[38;5;94m'
    C_GREEN=$'\033[38;5;28m'
    C_PURPLE=$'\033[38;5;55m'
    C_MAGENTA=$'\033[38;5;90m'
    C_CYAN=$'\033[38;5;30m'
    C_PLAYER_BULLET=$'\033[38;5;24m'
fi
unset _strafe_theme

# 反色（SGR 7）：用于掉落物，和敌弹区分开
C_REVERSE=$'\033[7m'
