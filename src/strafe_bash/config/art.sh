# config/art.sh — ASCII 立绘
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[art]++ )) && return 0

PLANE_ART_BASE=$'o|o\n-\'-'
PLANE_ART_SHIELD=$' .---.\n/ o|o \\\n  -\'-'

# 5 列机型
PLANE_ART_HORNET=$'(o|o)\n -\'-'
PLANE_ART_EAGLE=$'--|--\n -\'-'
PLANE_ART_IL2=$'==|==\n -\'-'

# 对应的护盾（3 行）：Bee 7 列，其余 9 列；底行就是飞机尾翼，不额外加长
PLANE_ART_SHIELD_HORNET=$' .-----. \n/ (o|o) \\\n   -\'-'
PLANE_ART_SHIELD_EAGLE=$' .-----. \n/ --|-- \\\n   -\'-'
PLANE_ART_SHIELD_IL2=$' .-----. \n/ ==|== \\\n   -\'-'

