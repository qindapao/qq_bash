# config/globals.sh — 全局状态
[[ -n "${_STRAFE_GLOBALS_SH:-}" ]] && return 0
_STRAFE_GLOBALS_SH=1

declare -a BULLETS=() ENEMIES=() DROPS=() ENEMY_BULLETS=() MISSILES=()
declare -a BOMB_FX_POS=()
declare -a BOSS_DEATH_POS=()
declare -i BOSS_DEATH_TICK=0
declare -i BOSS_DEATH_STYLE=0
declare -i BOSS_DEATH_CX=0
declare -i BOSS_DEATH_CY=0
declare -i BOSS_DEATH_WAVE=0
declare -a WORDS=()
declare PLAYER=

# 游戏逻辑状态（tick 内使用）
declare -i G_FIRE_CD=0
declare -i G_MISSILE_CD=0
declare -i G_MISSILE_SIDE=0
declare -i G_INV=0
declare -i G_ENEMY_TICK=0
declare -i G_DROP_TICK=0
declare -i G_WORD_TICK=0
declare -i G_B_DRY=0
declare -i G_BOSS_DRY=0
declare -i G_DX=0
declare -i G_DY=0
declare -i G_WANT_BOMB=0
declare -i G_GAME_OVER=0

declare -g FRAME_BUF=""

