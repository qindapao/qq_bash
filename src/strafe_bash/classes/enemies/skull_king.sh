# classes/enemies/skull_king.sh — SkullKing（骷髅王）
# 500 HP；4 段伤害 art；8 方向 O/X 弹幕。
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[skull_king]++ )) && return 0
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_base.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/soa_bullets.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_pattern.sh"

IFS= read -r -d '' SKULL_ART_0 <<'EOF' || true
     .-.
    (o.o)
     |=|
  //.=|=.\\
 // .=|=. \\
 \\ .=|=. //
  \\(_=_)//
   (:| |:)
    () ()
    || ||
   ==' '==
EOF

IFS= read -r -d '' SKULL_ART_1 <<'EOF' || true
     .-.
    (o.o)
     |=|
  //.=|=.\\
 // .=|=. \\
 \\ .=|=. //
  \\(_=_)//
   (:|
    ()
    ||
   =='
EOF

IFS= read -r -d '' SKULL_ART_2 <<'EOF' || true
     .-.
    (o.o)
     |=|
  //.=|=.\\
 // .=|=. \\
 \\ .=|=. //
  \\(_=_)//
EOF

IFS= read -r -d '' SKULL_ART_3 <<'EOF' || true



  //.=|=.\\
 // .=|=. \\
 \\ .=|=. //
  \\(_=_)//
EOF

declare -gA SkullKingObj=(
    [{CLS}$X]='SkullKing'
    [{SUP}$X]='BossBase'
    [{MIX}$X]=''
    # 死亡横幅上的名字
    [name]='THE SKULL KING'
    # 包围盒（13x11，立绘很高）
    [w]='13'
    [h]='11'
    # 血量：最终 Boss 级（600）
    [hp]='600'
    [maxhp]='600'
    # 击杀得分基数（最高）
    [score]='20000'
    # 单字符符号（立绘走 art，仅调试用）
    [symbol]='K'
    # 阶段边界百分比
    [pcut1]='75'
    [pcut2]='50'
    [pcut3]='25'
    # 死亡演出样式
    [death_style]='0'
    # 射击冷却：归零打一波 8 方向
    [shot_cd]='0'
    # 本波还剩几轮 8 方向连发
    [ring_left]='0'
    # 走位模式计时器/步号/模式号
    [pat_cd]='0'
    [pat_step]='-1'
    [pat_mode]='0'
)

SkullKing_born () {
    _boss_set_arts "$1" "$SKULL_ART_0" "$SKULL_ART_1" "$SKULL_ART_2" "$SKULL_ART_3"
    BossBase_born "$1"
    local -n _self=$1
    _self[shot_cd]=$SKULL_KING_FIRST_SHOT \
    _self[ring_left]=$SKULL_KING_BURST_RINGS \
    _self[pat_cd]=120 \
    _self[pat_step]=-1 \
    _self[pat_mode]=0
}

# 8 方向 O/X：每波 8 发，连发 4 波，然后休息约 3 秒。
SkullKing_move () {
    _boss_update_phase "$1"
    local -n self=$1
    local -i w=${self[w]} h=${self[h]}

    # 参考旋刃：更频繁地改目标点，并主动打屏幕左右边缘；
    # 纵向目标压在上半屏（好打），留 15% 的机会俯冲到底部。
    local -i _ymin=$GAME_TOP \
             _ymax=$(( SCREEN_H - 3 - h )) \
             _yhi=$(( _ymin + (_ymax - _ymin) / 2 ))
    _boss_move_target "$1" 4 "$_yhi" 2 60 20 3 1 15

    if (( EB_LIVE + SKULL_KING_WAVE_BULLETS <= ENEMY_BULLET_LIMIT )) ; then
        local -i sc=$(( ${self[shot_cd]:-0} - 1 ))
        if (( sc <= 0 )) ; then
            local -i x=${self[x]} y=${self[y]}
            local -i cx=$(( x + w / 2 )) cy=$(( y + h / 2 )) _i
            local _sym

            # 向下的一整排：X O X O X O X O
            local -i by=$(( y + h ))
            (( by > SCREEN_H - 2 )) && by=$(( SCREEN_H - 2 ))
            local -i start=$(( cx - 7 ))
            for (( _i=0; _i<SKULL_KING_ROW_BULLETS; _i++ )) ; do
                local -i sx=$(( start + _i * 2 ))
                if (( _i % 2 == 0 )) ; then
                    _sym='X'
                    enemy_bullet_spawn BossBullet "$sx" "$by" 0 1 "$_sym" 3 2 "$C_ORANGE"
                else
                    _sym='O'
                    enemy_bullet_spawn BossBullet "$sx" "$by" 0 1 "$_sym" 3 2 "$C_YELLOW"
                fi
            done

            # 其余 7 个方向，不含向下（向下已由上面的长排负责）
            local -a _dx=(1 1 1 0 -1 -1 -1) _dy=(1 0 -1 -1 -1 0 1)
            for (( _i=0; _i<SKULL_KING_RADIAL_BULLETS; _i++ )) ; do
                if (( _i % 2 == 0 )) ; then
                    _sym='O'
                    enemy_bullet_spawn BossBullet "$cx" "$cy" "${_dx[_i]}" "${_dy[_i]}" "$_sym" 3 2 "$C_YELLOW"
                else
                    _sym='X'
                    enemy_bullet_spawn BossBullet "$cx" "$cy" "${_dx[_i]}" "${_dy[_i]}" "$_sym" 3 2 "$C_ORANGE"
                fi
            done

            local -i rl=$(( ${self[ring_left]:-1} - 1 ))
            if (( rl > 0 )) ; then
                self[shot_cd]=$SKULL_KING_RING_GAP \
                self[ring_left]=$rl
            else
                self[shot_cd]=$SKULL_KING_REST \
                self[ring_left]=$SKULL_KING_BURST_RINGS
            fi
        else
            self[shot_cd]=$sc
        fi
    fi

    local -i _ps=${self[pat_step]:--1}
    if (( _ps >= 0 )) ; then
        _boss_pattern_spawn_step "$1" "$_ps" "${self[pat_mode]:-0}" 4
        ((_ps++))
        if (( _ps >= ${#BOSS_AIM_PATTERN_STEPS[@]} )) ; then
            self[pat_step]=-1 \
            self[pat_cd]=240
        else
            self[pat_step]=$_ps
        fi
    else
        local -i _pc=$(( ${self[pat_cd]:-0} - 1 ))
        if (( _pc <= 0 )) ; then
            _boss_pattern_mode "$1"
            self[pat_mode]=$REPLY
            _boss_pattern_spawn_step "$1" 0 "$REPLY" 4
            self[pat_step]=1 \
            self[pat_cd]=240
        else
            self[pat_cd]=$_pc
        fi
    fi
    return 0
}
