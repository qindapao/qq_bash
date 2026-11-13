# config/globals.sh — 全局状态数组
[[ -n "${_STRAFE_GLOBALS_SH:-}" ]] && return 0
_STRAFE_GLOBALS_SH=1

declare -a BULLETS=() ENEMIES=() DROPS=() ENEMY_BULLETS=() MISSILES=()
declare -a BOMB_FX_POS=()
declare -a BOSS_DEATH_POS=()
declare -i BOSS_DEATH_TICK=0
declare -a CLEAR_BATCH=()
declare -a WORDS=()
declare PLAYER=

