# config/globals.sh — 全局状态
[[ -n "${_STRAFE_GLOBALS_SH:-}" ]] && return 0
_STRAFE_GLOBALS_SH=1

declare -a BULLETS=() ENEMIES=() DROPS=() ENEMY_BULLETS=() MISSILES=() MISSILE_TRAIL_CLEAR=()
declare -a BOMB_FX_POS=()
declare -a HIT_FX=()
declare -a BOSS_DEATH_POS=()
declare -i CLEAR_BANNER_TICK=0
declare -i CLEAR_BANNER_FRAME=0
declare CLEAR_BANNER_TEXT=''
declare -i BOSS_DEATH_TICK=0
declare -i BOSS_DEATH_STYLE=0
declare -i BOSS_DEATH_CX=0
declare -i BOSS_DEATH_CY=0
declare -i BOSS_DEATH_WAVE=0
declare -a WORDS=()

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
declare -i G_MOUSE_ON=0
declare -i G_WANT_BOMB=0
declare -i G_FREE_BOMB=0
declare -i G_GAME_OVER=0
declare -i G_RUN_TICKS=0
declare -i G_KILLS=0
declare -i G_BOSS_KILLS=0
declare -i G_LAST_ESCAPE_TICK=0
declare -i G_LAST_ACE_TICK=0

declare -g FRAME_BUF=""

# 扫描电网：同一时刻只允许一条（Boss 的和我方的互斥，后来的覆盖）
# owner 0 = Boss（红，自上而下，打玩家）；1 = 我方（绿，自下而上，打敌人）
declare -i WAVE_ON=0
declare -i WAVE_Y=0
declare -i WAVE_DIR=1
declare -i WAVE_OWNER=0
declare -i WAVE_DMG=0
declare -i WAVE_CD=0
declare -i WAVE_LAST_Y=-1
declare -i G_WAVE_HIT_PLAYER=0
declare -i WAVE_CLEAR_LO=0
declare -i WAVE_CLEAR_HI=0
# 逃生缝（字符串下标，0 = 屏幕第 2 列）。我方电网没有缝，两个值都是负数。
declare -i WAVE_GAP1=-99
declare -i WAVE_GAP2=-99
declare -g WAVE_CLR=''
declare -g WAVE_LINE=''
declare -gA WAVE_HIT_ENEMY=()

