# config/color.sh — ANSI 256 色
[[ -n "${_STRAFE_COLOR_SH:-}" ]] && return 0
_STRAFE_COLOR_SH=1

C_RESET=$'\033[0m'
C_BLUE=$'\033[38;5;33m'
C_RED=$'\033[38;5;196m'
C_ORANGE=$'\033[38;5;208m'
C_YELLOW=$'\033[38;5;226m'
C_GREEN=$'\033[38;5;46m'
C_PURPLE=$'\033[38;5;129m'
C_MAGENTA=$'\033[38;5;201m'
C_CYAN=$'\033[38;5;51m'
