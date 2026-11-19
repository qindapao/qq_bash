# config/globals.sh — 全局状态
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[globals]++ )) && return 0

declare -a BULLETS=() ENEMIES=() DROPS=() MISSILES=() MISSILE_TRAIL_CLEAR=()
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

# 扫描电网：固定槽位表，**允许同屏多条**（Boss 连发 2..4 条 + 我方净 1 条）。
# owner 0 = Boss（红，自上而下，打玩家）；1 = 我方（绿，自下而上，打敌人）
# WAVE_SLOTS 要 >= 4（Boss 一次连发上限）+ 1（我方）。1 秒间隔 + 约 2 秒扫屏时
# 最多同时 3 条在屏上，5 个槽足够。
declare -gi WAVE_SLOTS=5
# 派生标量：是否有任何波存活（热路径早退用，不要手工维护）
declare -gi WAVE_ON=0
declare -gai WV_ON=()        # 每槽：1=活 0=空
declare -gai WV_Y=()         # 当前行
declare -gai WV_DIR=()       # +1 向下 / -1 向上
declare -gai WV_OWNER=()     # 0=Boss 1=我方
declare -gai WV_DMG=()       # 伤害
declare -gai WV_CD=()        # 每 WAVE_STEP_TICKS 走一行的计数
declare -gai WV_LAST_Y=()    # 渲染用：上一帧画在哪行（-1 = 没画过）
declare -gai WV_HIT=()       # 本波是否已经打过玩家（Boss 波用，每波只结算一次）
declare -gai WV_GAP1=()      # 逃生缝（字符串下标，0 = 屏幕第 2 列）；我方波为负
declare -gai WV_GAP2=()
declare -gai WV_CLEAR_LO=()  # 本 tick 扫过的行区间（清弹用）
declare -gai WV_CLEAR_HI=()
declare -ga WV_CLR=()        # 颜色转义串
declare -ga WV_LINE=()       # 整行字符（每条波自己的洞）
# 我方电网对敌人的命中表："slot|敌人句柄" => 1（每条波对每个敌人只结算一次）
declare -gA WAVE_HIT_ENEMY=()
# 本 tick 电网对玩家造成的伤害累计（伤害结算时并入 player_dmg）
declare -gi G_WAVE_DMG_PENDING=0

# 玩家命中几何：tick 每帧算一次，敌弹的 _move 里直接拿来判命中
# （避免逐弹去读 OBJ_player 的关联数组，那才是热路径上真正贵的部分）
declare -gi _HL_ON=0        # 1 = 玩家在场，可以判命中
declare -gi _HL_X=0 _HL_Y=0 # 玩家中心格
declare -gi _HL_SH=0        # 1 = 有护盾（判定用矩形）
declare -gi _HL_X1=0 _HL_X2=0 _HL_Y1=0 _HL_Y2=0
# 本 tick 敌弹命中玩家累计的伤害（结算时并入 player_dmg）
declare -gi G_PLAYER_DMG_PENDING=0

# 上一帧消息行（第 5 行）占的宽度：只清这么宽，不再用 \033[K 清整行
# （清整行会擦掉第 5 行的掉落物/敌弹，而帧缓冲并不知道格子被擦了 → 闪烁）
declare -gi MSG_LEN=0


# 初始把每槽的"上一帧行"标成 -1，其余数值元素默认 0
globals_init_WV () {
    local -i _wv_i
    for (( _wv_i=0 ; _wv_i<WAVE_SLOTS ; _wv_i++ )) ; do
        WV_LAST_Y[_wv_i]=-1
        WV_GAP1[_wv_i]=-99
        WV_GAP2[_wv_i]=-99
    done
}
globals_init_WV

