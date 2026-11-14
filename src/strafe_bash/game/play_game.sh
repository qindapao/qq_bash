# game/play_game.sh — 单局主循环（游戏核心逻辑）
[[ -n "${_STRAFE_PLAY_GAME_SH:-}" ]] && return 0
_STRAFE_PLAY_GAME_SH=1

. "$STRAFE_LIB_HOME/xo.sh"

# config 层
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/config/words.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

# classes 层
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/bullet.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/missile.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_base.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/boss_bullet.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_spinner.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_base.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_v.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_q.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_m.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/enemy_b.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss.sh"
. "$STRAFE_PROJ_DIR/classes/pickups/drop.sh"
. "$STRAFE_PROJ_DIR/classes/pickups/word.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_helpers.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_types.sh"

# render 层
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/render/frame.sh"
. "$STRAFE_PROJ_DIR/render/hud.sh"
. "$STRAFE_PROJ_DIR/render/scene.sh"
. "$STRAFE_PROJ_DIR/render/fx.sh"
. "$STRAFE_PROJ_DIR/render/clear_banner.sh"

# save 层
. "$STRAFE_PROJ_DIR/save/save.sh"

# ============================================================================
# 鼠标：xterm SGR 鼠标上报（1003 any-event + 1006 SGR）
# 只移动飞机；开火仍然是自动的。M 键可临时关闭/恢复。
# ============================================================================
_mouse_on () {
    (( G_MOUSE_ON )) && return 0
    cursor_hide
    printf '\033[?1003h\033[?1006h'
    G_MOUSE_ON=1
}
_mouse_off () {
    printf '\033[?1003l\033[?1006l'
    G_MOUSE_ON=0
}
_mouse_assert () {
    # 有些终端在失焦/切换后会悄悄丢掉鼠标上报；定期重新声明一次
    if (( G_MOUSE_ON )) ; then
        printf '\033[?1003h\033[?1006h'
    else
        _mouse_on
    fi
}
_mouse_move_to () {
    local -i tx=$1 ty=$2
    [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] || return 0
    local -n _mp=$PLAYER
    local -i cx=${_mp["{x}$X"]} cy=${_mp["{y}$X"]}
    unset -n _mp
    xo_call "$PLAYER" move "$((tx - cx))" "$((ty - cy))"
    need_render=1
}
_mouse_bomb () {
    [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] || return 0
    local -n _bp=$PLAYER
    (( ${_bp["{bombs}$X"]:-0} > 0 )) && G_WANT_BOMB=1
    unset -n _bp
}
_mouse_apply () {
    local seq=$1
    [[ "$seq" == '[<'* ]] || return 0
    [[ "$seq" == *M || "$seq" == *m ]] || return 0
    local ev=${seq: -1}
    local body=${seq:2:${#seq}-3}
    local mb mx my
    IFS=';' read -r mb mx my <<< "$body"
    [[ "$mx" =~ ^[0-9]+$ && "$my" =~ ^[0-9]+$ ]] || return 0
    (( mb & 64 )) && return 0     # 滚轮不移动飞机
    [[ "$ev" == "m" ]] && return 0 # 松开按钮不再移动
    if (( (mb & 3) == 2 && !(mb & 32) )) ; then
        _mouse_bomb
        return 0
    fi
    # 指针放在飞机正下方两格，避免挡住机体
    _mouse_move_to "$mx" "$(( my - 2 ))"
}

# ============================================================================
# _hit_fx_add — 命中火花（短命，不创建 xo 对象）
# ============================================================================
_hit_fx_add () {
    local y=$1 x=$2 ch=$3 clr=$4
    (( y >= GAME_TOP && y < SCREEN_H - 1 && x >= 2 && x <= SCREEN_W - 2 )) || return 0
    (( ${#HIT_FX[@]} >= 200 )) && return 0
    HIT_FX+=("$y" "$x" "$ch" "$clr" 3)
}

_score_bonus () {
    local amount=$1
    [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] || return 0
    local -n _bp=$PLAYER
    _bp["{score}$X"]=$(( ${_bp["{score}$X"]:-0} + amount ))
    unset -n _bp
}

# 撞击伤害：由 M_Ram 提供伤害值，游戏层负责计分/死亡/Boss 收尾。
# 返回 0 表示撞死，1 表示还活着。
_ram_enemy () {
    local eid=$1 ex=$2 ey=$3 ew=$4 eh=$5 eart=$6
    local -n _re=$eid
    local -i hp=${_re["{hp}$X"]:-1}
    local -i escore=${_re["{score}$X"]:-0}
    unset -n _re
    local -i rdmg
    REPLY=
    xo_call "$PLAYER" ram_damage
    rdmg=${REPLY:-5}
    REPLY=
    (( rdmg > 0 )) || rdmg=5
    hp=$(( hp - rdmg ))
    local -n _re2=$eid
    _re2["{hp}$X"]=$hp
    unset -n _re2
    _hit_fx_add "$py" "$px" '*' "$C_CYAN"
    (( hp <= 0 )) || return 1
    ((G_KILLS++))
    p["{score}$X"]=$(( ${p["{score}$X"]:-0} + escore * _score_pct / 100 ))
    if Base_is_a "$eid" BossBase ; then
        ((G_BOSS_KILLS++))
        _boss_on_death "$eid" "$ex" "$ey" "$ew" "$eh" "$eart"
    fi
    xo_obj_kill "$eid"
    return 0
}

# ============================================================================
# _boss_on_death — Boss 死亡统一处理（掉落 + 死亡动画参数）
# ============================================================================
_boss_on_death () {
    local obj=$1 ex=$2 ey=$3 ew=$4 eh=$5 art=$6
    local -n _b=$obj
    local -i _style=${_b["{death_style}$X"]:-0}
    local _bname=${_b["{name}$X"]:-THE BOSS}
    unset -n _b

    # 击杀 Boss 也触发全清横幅；与清场条件互相独立
    _score_bonus "$BOSS_SCORE_BONUS"
    _clear_banner_start "${_bname} WAS KILLED BY YOU!  +${BOSS_SCORE_BONUS}"

    # 如果上一个 Boss 的死亡特效还没放完，先擦掉残留火花
    local _i _t
    for (( _i=0; _i<${#BOSS_DEATH_POS[@]}; _i+=2 )) ; do
        printf -v _t '\033[%d;%dH ' "${BOSS_DEATH_POS[_i]}" "${BOSS_DEATH_POS[_i+1]}"
        FRAME_BUF+="$_t"
    done
    BOSS_DEATH_POS=()
    BOSS_DEATH_STYLE=$_style
    BOSS_DEATH_CX=$(( ex + ew / 2 ))
    BOSS_DEATH_CY=$(( ey + eh / 2 ))
    BOSS_DEATH_WAVE=0
    BOSS_DEATH_TICK=30

    # style 0：老 Boss，按 art 的非空格子放随机火花
    if (( _style == 0 )) ; then
        local _dr=0 _drest=$art
        while [[ -n "$_drest" ]] ; do
            local _dl=${_drest%%$'\n'*}
            if [[ "$_drest" == *$'\n'* ]] ; then _drest=${_drest#*$'\n'}
            else _drest=''
            fi
            local _dc=0 _dlen=${#_dl}
            while (( _dc < _dlen )) ; do
                local _dch=${_dl:_dc:1}
                [[ "$_dch" != " " ]] && BOSS_DEATH_POS+=($((ey + _dr)) $((ex + _dc)))
                ((_dc++))
            done
            ((_dr++))
        done
    fi

    local _bdt=(2 3 4 5 H b m L S)
    local _bdc="${_bdt[RANDOM % 9]}"
    xo_obj_born Drop "$_bdc"
    local -n _bd=$REPLY
    _bd["{x}$X"]=$(( ex + ew / 2 ))
    _bd["{y}$X"]=$(( ey + eh - 1 ))
    unset -n _bd
    DROPS+=("$REPLY")
}

# 随机挑一个 Boss 类（50/50）
_boss_random_class () {
    if (( RANDOM % 2 )) ; then
        REPLY=BossSpinner
    else
        REPLY=Boss
    fi
}

# ============================================================================
# _play_game_tick — 单个逻辑 tick（纯计算，绝不碰终端）
# ============================================================================
_play_game_tick () {
    local b e d eb m w
    ((G_RUN_TICKS++))
    [[ -n "$PLAYER" ]] && xo_call "$PLAYER" blink_tick
    if [[ -n "$PLAYER" ]] && declare -F "${XO_OBJ_POOL[$PLAYER]}_ram_tick" >/dev/null 2>&1 ; then
        xo_call "$PLAYER" ram_tick
    fi
    (( G_RUN_TICKS % 30 == 0 )) && _mouse_assert

    # ---- 0. 奖励计时器递减（每 tick 减 1）----
    local -n _pb=$PLAYER
    local -i _score_pct=${_pb["{score_pct}$X"]:-100}
    local _tk _tv
    for _tk in "{t2}$X" "{t3}$X" "{t4}$X" "{t5}$X" "{mt}$X" "{lt}$X" "{st}$X" ; do
        _tv=${_pb[$_tk]:-0}
        (( _tv > 0 )) && _pb["$_tk"]=$(( _tv - 1 ))
    done
    (( ${_pb["{lt}$X"]:-0} == 0 )) && _pb["{lanes}$X"]=0
    if (( ${_pb["{shield}$X"]:-0} && ${_pb["{st}$X"]:-0} == 0 )) ; then
        unset -n _pb
        _plane_set_shield "$PLAYER" 0
        local -n _pb=$PLAYER
    fi

    # ---- 0.5 武器过期检测 ----
    # 当前武器是一个独立的 BulletType 子类对象；过期后只切回默认武器，
    # 不再像旧实现那样每 tick 动态 kill/born 一个 BulletType。
    local _bt=${_pb["{bullet}$X"]}
    local _tier=1
    if [[ -n "$_bt" && -n "${XO_OBJ_POOL[$_bt]+_}" ]] ; then
        local -n _bo=$_bt
        _tier=${_bo["{tier}$X"]:-1}
        unset -n _bo
    fi
    local _tk_cur="{t$_tier}$X"
    if (( _tier >= 2 && _tier <= 5 )) && (( ${_pb[$_tk_cur]:-0} == 0 )) ; then
        _pb["{bullet}$X"]=${_pb["{w1}$X"]}
    fi
    unset -n _pb

    # ---- 1. 冷却递减 ----
    (( G_FIRE_CD > 0 )) && ((G_FIRE_CD--))
    (( G_MISSILE_CD > 0 )) && ((G_MISSILE_CD--))
    (( G_INV > 0 )) && ((G_INV--))

    # ---- 2. 玩家移动 ----
    (( G_DX || G_DY )) && xo_call "$PLAYER" move "$G_DX" "$G_DY"

    # ---- 3. 玩家开火 ----
    # 射速由当前武器类的 {cd} 决定，Plane_fire 内部会设置 G_FIRE_CD
    if (( G_FIRE_CD == 0 )) ; then
        xo_call "$PLAYER" fire
    fi

    # ---- 4. 玩家导弹发射 ----
    local -n _pm=$PLAYER
    if (( ${_pm["{mt}$X"]:-0} > 0 && G_MISSILE_CD == 0 )) ; then
        local _my=$(( ${_pm["{y}$X"]} - 1 ))
        local _mx
        if (( G_MISSILE_SIDE )) ; then
            _mx=$(( ${_pm["{x}$X"]} - 1 ))
            G_MISSILE_SIDE=0
        else
            _mx=$(( ${_pm["{x}$X"]} + 1 ))
            G_MISSILE_SIDE=1
        fi
        (( _mx < 2 )) && _mx=2
        (( _mx > SCREEN_W - 2 )) && _mx=$(( SCREEN_W - 2 ))
        xo_obj_born Missile "$_mx" "$_my" 2
        MISSILES+=("$REPLY")
        G_MISSILE_CD=10
    fi
    unset -n _pm

    # ---- 5. 所有对象 move ----
    local -a alive_b=()
    for b in "${BULLETS[@]}" ; do
        [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
        xo_call "$b" move
        if (( $? == 0 )) ; then alive_b+=("$b") ; else xo_obj_kill "$b" ; fi
    done
    BULLETS=("${alive_b[@]}")

    local -a alive_m=()
    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        xo_call "$m" move
        if (( $? == 0 )) ; then alive_m+=("$m") ; else xo_obj_kill "$m" ; fi
    done
    MISSILES=("${alive_m[@]}")

    local -a alive_eb=()
    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
        xo_call "$eb" move
        if (( $? == 0 )) ; then alive_eb+=("$eb") ; else xo_obj_kill "$eb" ; fi
    done
    ENEMY_BULLETS=("${alive_eb[@]}")

    local -a alive_e=()
    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
        xo_call "$e" move
        if (( $? == 0 )) ; then alive_e+=("$e") ; else xo_obj_kill "$e" ; fi
    done
    ENEMIES=("${alive_e[@]}")

    local -a alive_d=()
    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        xo_call "$d" move
        if (( $? == 0 )) ; then alive_d+=("$d") ; else xo_obj_kill "$d" ; fi
    done
    DROPS=("${alive_d[@]}")

    local -a alive_w=()
    for w in "${WORDS[@]}" ; do
        [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
        xo_call "$w" move
        if (( $? == 0 )) ; then alive_w+=("$w") ; else xo_obj_kill "$w" ; fi
    done
    WORDS=("${alive_w[@]}")

    # ---- 6. 敌人快照（几何/血量/奖励），供子弹、导弹、玩家碰撞共用 ----
    # 每 tick 只绑定每个敌人一次。旧实现每对 (子弹, 敌人) 都要
    # nameref 绑定 + 读 4 个字段；80 子弹 × 20 敌人时是 1600 次绑定、
    # 6400 次关联数组读取，是本 tick 最大的热点。
    local -a _eid=() _ex=() _ey=() _ew=() _eh=() _ehp=() _escore=() _eart=() _ecls=()
    local -a _edead=()
    local -i _ne=0 _ndead=0 _j _r _newhp
    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
        local -n _e=$e
        _eid[_ne]=$e
        _ex[_ne]=${_e["{x}$X"]}
        _ey[_ne]=${_e["{y}$X"]}
        _ew[_ne]=${_e["{w}$X"]}
        _eh[_ne]=${_e["{h}$X"]}
        _ehp[_ne]=${_e["{hp}$X"]}
        _escore[_ne]=${_e["{score}$X"]}
        _eart[_ne]=${_e["{art}$X"]}
        _ecls[_ne]=${_e["{CLS}$X"]}
        unset -n _e
        ((_ne++))
    done

    # 行索引：敌人是稀疏的（最多 20 个，每个 2~5 行），把「敌人索引」
    # 按覆盖的屏幕行分桶。子弹/导弹只检查自己所在行的桶，
    # 每对检测只剩纯算术比较，不再遍历全部敌人。
    local -A _row_e=()
    for (( _j=0 ; _j<_ne ; _j++ )) ; do
        for (( _r=_ey[_j] ; _r<_ey[_j] + _eh[_j] ; _r++ )) ; do
            _row_e[$_r]+=" $_j"
        done
    done

    # ---- 7. 子弹 vs 敌人 ----
    local -A killed_b=() killed_m=()
    local -i score_gain=0

    for b in "${BULLETS[@]}" ; do
        [[ -n "${killed_b[$b]+_}" ]] && continue
        [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
        local -n _b=$b
        local bx=${_b["{x}$X"]} by=${_b["{y}$X"]}
        local bdmg=${_b["{damage}$X"]}
        unset -n _b

        for _j in ${_row_e[$by]:-} ; do
            (( _edead[_j] )) && continue
            if (( bx >= _ex[_j] && bx < _ex[_j] + _ew[_j] )) ; then
                _newhp=$(( _ehp[_j] - bdmg ))
                _ehp[_j]=$_newhp
                killed_b[$b]=1
                _hit_fx_add "$by" "$bx" '*' "$C_ORANGE"
                if (( _newhp <= 0 )) ; then
                    _edead[_j]=1
                    ((_ndead++))
                    ((G_KILLS++))
                    score_gain=$(( score_gain + _escore[_j] * _score_pct / 100 ))
                    if Base_is_a "${_eid[_j]}" BossBase ; then
                        ((G_BOSS_KILLS++))
                        _boss_on_death "${_eid[_j]}" "${_ex[_j]}" "${_ey[_j]}" "${_ew[_j]}" "${_eh[_j]}" "${_eart[_j]}"
                    fi
                else
                    local -n _e=${_eid[_j]}
                    _e["{hp}$X"]=$_newhp
                    unset -n _e
                fi
                break
            fi
        done
    done

    # ---- 8. 导弹 vs 敌人 ----
    for m in "${MISSILES[@]}" ; do
        [[ -n "${killed_m[$m]+_}" ]] && continue
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        local -n _m=$m
        local mx=${_m["{x}$X"]} my=${_m["{y}$X"]}
        local mdmg=${_m["{damage}$X"]}
        unset -n _m

        for _j in ${_row_e[$my]:-} ; do
            (( _edead[_j] )) && continue
            if (( mx >= _ex[_j] && mx < _ex[_j] + _ew[_j] )) ; then
                _newhp=$(( _ehp[_j] - mdmg ))
                _ehp[_j]=$_newhp
                killed_m[$m]=1
                _hit_fx_add "$my" "$mx" '*' "$C_ORANGE"
                if (( _newhp <= 0 )) ; then
                    _edead[_j]=1
                    ((_ndead++))
                    ((G_KILLS++))
                    score_gain=$(( score_gain + _escore[_j] * _score_pct / 100 ))
                    if Base_is_a "${_eid[_j]}" BossBase ; then
                        ((G_BOSS_KILLS++))
                        _boss_on_death "${_eid[_j]}" "${_ex[_j]}" "${_ey[_j]}" "${_ew[_j]}" "${_eh[_j]}" "${_eart[_j]}"
                    fi
                else
                    local -n _e=${_eid[_j]}
                    _e["{hp}$X"]=$_newhp
                    unset -n _e
                fi
                break
            fi
        done
    done

    # ---- 9. 清理被击中的子弹/导弹/敌人 ----
    if ((${#killed_b[@]})) ; then
        local -a nb=()
        for b in "${BULLETS[@]}" ; do
            if [[ -n "${killed_b[$b]+_}" ]] ; then
                [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
                xo_obj_kill "$b"
            else
                nb+=("$b")
            fi
        done
        BULLETS=("${nb[@]}")
    fi

    if ((${#killed_m[@]})) ; then
        local -a nm=()
        for m in "${MISSILES[@]}" ; do
            if [[ -n "${killed_m[$m]+_}" ]] ; then
                [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
                xo_obj_kill "$m"
            else
                nm+=("$m")
            fi
        done
        MISSILES=("${nm[@]}")
    fi

    # 敌人延迟到所有碰撞结束后统一 kill：快照数组在子弹/导弹/玩家
    # 三个阶段之间保持有效，_edead 就是「本 tick 已死」标记。
    if (( _ndead )) ; then
        local -a ne=()
        for (( _j=0 ; _j<_ne ; _j++ )) ; do
            if (( _edead[_j] )) ; then
                xo_obj_kill "${_eid[_j]}"
            else
                ne+=("${_eid[_j]}")
            fi
        done
        ENEMIES=("${ne[@]}")
    fi

    # ---- 9. 玩家受伤 ----
    local -n p=$PLAYER
    local px=${p["{x}$X"]} py=${p["{y}$X"]}
    local -i player_dmg=0

    local _sh=$(( ${p["{shield}$X"]:-0} ))
    local -i _shw=${p["{shield_w}$X"]:-9}
    local -i _shh=${p["{shield_h}$X"]:-3}
    local -i _sht=${p["{shield_top}$X"]:--1}
    local _sx1=$(( px - _shw / 2 )) _sx2=$(( px + _shw / 2 ))
    local _sy1=$(( py + _sht ))
    local _sy2=$(( _sy1 + _shh - 1 ))

    local -a survive_eb=()
    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
        local -n _eb=$eb
        local _ebx=${_eb["{x}$X"]} _eby=${_eb["{y}$X"]}
        local -i _hit=0
        if (( _sh )) ; then
            (( _ebx >= _sx1 && _ebx <= _sx2 && _eby >= _sy1 && _eby <= _sy2 )) && _hit=1
        else
            (( _ebx == px && _eby == py )) && _hit=1
        fi
        if (( _hit )) ; then
            if (( _sh )) ; then
                _hit_fx_add "$_eby" "$_ebx" '*' "$C_GREEN"
            else
                _hit_fx_add "$_eby" "$_ebx" '*' "$C_RED"
            fi
            (( ! _sh )) && player_dmg=$(( player_dmg + ${_eb["{damage}$X"]} ))
            unset -n _eb
            xo_obj_kill "$eb"
        else
            unset -n _eb
            survive_eb+=("$eb")
        fi
    done
    ENEMY_BULLETS=("${survive_eb[@]}")

    for (( _j=0 ; _j<_ne ; _j++ )) ; do
        (( _edead[_j] )) && continue
        (( px >= _ex[_j] && px < _ex[_j] + _ew[_j] &&
           py >= _ey[_j] && py < _ey[_j] + _eh[_j] )) && {
            player_dmg=$(( player_dmg + 3 ))
            _hit_fx_add "$py" "$px" '*' "$C_RED"
        }
    done

    # 撞击型飞机：M_Ram 在闪烁/受伤状态中提供额外撞击伤害
    local -i _has_ram=0
    if [[ -n "$PLAYER" ]] && declare -F "${XO_OBJ_POOL[$PLAYER]}_ram_ready" >/dev/null 2>&1 ; then
        _has_ram=1
    fi
    local -A _ram_killed=()
    if (( _has_ram )) ; then
        for (( _j=0 ; _j<_ne ; _j++ )) ; do
            (( _edead[_j] )) && continue
            (( px >= _ex[_j] && px < _ex[_j] + _ew[_j] &&
               py >= _ey[_j] && py < _ey[_j] + _eh[_j] )) || continue
            if xo_call "$PLAYER" ram_ready ; then
                _ram_enemy "${_eid[_j]}" "${_ex[_j]}" "${_ey[_j]}" "${_ew[_j]}" "${_eh[_j]}" "${_eart[_j]}" && \
                    _ram_killed["${_eid[_j]}"]=1
            fi
        done
    fi
    if (( ${#_ram_killed[@]} )) ; then
        local -a _kept=()
        for e in "${ENEMIES[@]}" ; do
            [[ -n "${_ram_killed[$e]+_}" ]] && continue
            _kept+=("$e")
        done
        ENEMIES=("${_kept[@]}")
    fi

    if (( player_dmg > 0 && G_INV == 0 )) ; then
        p["{hp}$X"]=$(( ${p["{hp}$X"]} - player_dmg ))
        xo_call "$PLAYER" blink_start
        G_INV=${p["{blink}$X"]:-90}
        if (( ${p["{lt}$X"]:-0} > 0 && ${p["{lanes}$X"]:-0} > 0 )) ; then
            local _nl=$(( ${p["{lanes}$X"]} - 1 ))
            p["{lanes}$X"]=$_nl
            (( _nl == 0 )) && p["{lt}$X"]=0
        fi
    fi

    if (( score_gain > 0 )) ; then
        p["{score}$X"]=$(( ${p["{score}$X"]} + score_gain ))
    fi

    # ---- 10. 掉落物拾取 ----
    # 拾取用整架飞机的 art 包围盒；护盾形态用护盾 art 的包围盒。
    local -i _pick_al _pick_h _pick_top
    if (( _sh )) ; then
        _pick_al=$(( _shw / 2 )) ; _pick_h=$_shh ; _pick_top=$(( py + _sht ))
    else
        _pick_al=$(( ${p["{w}$X"]:-3} / 2 )) ; _pick_h=${p["{h}$X"]:-2} ; _pick_top=$py
    fi
    local _px1=$(( px - _pick_al )) _px2=$(( px + _pick_al ))
    local _py1=$_pick_top _py2=$(( _pick_top + _pick_h - 1 ))

    local -a survive_d2=()
    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        local -n _d=$d
        if (( ${_d["{x}$X"]} >= _px1 && ${_d["{x}$X"]} <= _px2 && \
              ${_d["{y}$X"]} >= _py1 && ${_d["{y}$X"]} <= _py2 )) ; then
            local dtype=${_d["{dtype}$X"]}
            unset -n _d
            xo_obj_kill "$d"
            case "$dtype" in
                2|3|4|5)
                    # 切换到本局该档位的武器对象；武器对象常驻，不销毁。
                    # dtype 现在直接对应 tier（2..5），t2..t5 一一对应。
                    local _wnew=${p["{w$dtype}$X"]}
                    if [[ -n "$_wnew" && -n "${XO_OBJ_POOL[$_wnew]+_}" ]] ; then
                        p["{t2}$X"]=0 ; p["{t3}$X"]=0 ; p["{t4}$X"]=0 ; p["{t5}$X"]=0
                        p["{bullet}$X"]=$_wnew
                        case "$dtype" in
                            2) p["{t2}$X"]=$BONUS_T2 ;;
                            3) p["{t3}$X"]=$BONUS_T3 ;;
                            4) p["{t4}$X"]=$BONUS_T4 ;;
                            5) p["{t5}$X"]=$BONUS_T5 ;;
                        esac
                    fi
                    ;;
                H)
                    p["{hp}$X"]=$(( ${p["{hp}$X"]} + 3 ))
                    (( ${p["{hp}$X"]} > ${p["{maxhp}$X"]:-20} )) && p["{hp}$X"]=${p["{maxhp}$X"]:-20}
                    ;;
                b)
                    (( ${p["{bombs}$X"]:-0} < 5 )) && \
                        p["{bombs}$X"]=$(( ${p["{bombs}$X"]:-0} + 1 ))
                    ;;
                m)
                    p["{mt}$X"]=$BONUS_MT
                    ;;
                L)
                    local _cur_lanes=${p["{lanes}$X"]:-0}
                    case "$_cur_lanes" in
                        0) p["{lanes}$X"]=1 ; p["{lanes_side}$X"]=$(( RANDOM % 2 )) ; p["{lt}$X"]=$BONUS_LT ;;
                        1) p["{lanes}$X"]=2 ; p["{lt}$X"]=$BONUS_LT ;;
                        2) p["{lanes}$X"]=3 ; p["{lanes_side}$X"]=$(( RANDOM % 2 )) ; p["{lt}$X"]=$BONUS_LT ;;
                        3) p["{lanes}$X"]=4 ; p["{lt}$X"]=$BONUS_LT ;;
                        *) p["{lt}$X"]=$BONUS_LT ;;
                    esac
                    ;;
                S)
                    unset -n p
                    _plane_set_shield "$PLAYER" 1
                    local -n p=$PLAYER
                    ;;
            esac
        else
            unset -n _d
            survive_d2+=("$d")
        fi
    done
    DROPS=("${survive_d2[@]}")

    # ---- 10.5 单词拾取：碰到即消失并加分 ----
    local -a survive_w=()
    for w in "${WORDS[@]}" ; do
        [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
        local -n _w=$w
        local _wx=${_w["{x}$X"]} _wy=${_w["{y}$X"]} _wlen=${_w["{len}$X"]}
        unset -n _w
        if (( _wy >= _py1 && _wy <= _py2 && \
              _wx + _wlen - 1 >= _px1 && _wx <= _px2 )) ; then
            local _wscore=$(( _wlen * 10 * _score_pct / 100 ))
            p["{score}$X"]=$(( ${p["{score}$X"]} + _wscore ))
            xo_obj_kill "$w"
        else
            survive_w+=("$w")
        fi
    done
    WORDS=("${survive_w[@]}")

    # ---- 11. 死亡判定 ----
    local -i _hp_final=${p["{hp}$X"]}
    unset -n p
    (( _hp_final <= 0 )) && { G_GAME_OVER=1 ; return 0 ; }

    # ---- 12. 刷怪 ----
    if (( _ne >= 5 && ${#ENEMIES[@]} == 0 )) ; then
        _score_bonus "$CLEAR_SCORE_BONUS"
        if (( CLEAR_BANNER_TICK > 0 )) ; then
            CLEAR_BANNER_TEXT+="  +${CLEAR_SCORE_BONUS} CLEAR"
        else
            _clear_banner_start "ALL ENEMIES CLEARED  +${CLEAR_SCORE_BONUS}"
        fi
    fi
    (( G_ENEMY_TICK++ % 50 == 0 )) && (( ${#ENEMIES[@]} < ENEMY_LIMIT )) && {
        local alive_B=0 alive_Boss=0
        for e in "${ENEMIES[@]}" ; do
            [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
            local -n _e=$e
            local _c=${_e["{CLS}$X"]}
            [[ "$_c" == "EnemyB" ]] && ((alive_B++))
            Base_is_a "$e" BossBase && ((alive_Boss++))
            unset -n _e
        done

        local spawn_cls=''
        local _r=$(( RANDOM % 1000 ))
        # 场上最多 2 个 Boss；达到 2 个后只刷小怪
        if (( alive_Boss >= 2 )) ; then
            # 2 Boss 时的小怪配比：V45% / Q25% / M15% / B15%
            if (( _r < 450 )) ; then spawn_cls=EnemyV
            elif (( _r < 700 )) ; then spawn_cls=EnemyQ
            elif (( _r < 850 )) ; then spawn_cls=EnemyM
            else                       spawn_cls=EnemyB
            fi
        else
            if (( G_BOSS_DRY >= 300 )) ; then
                _boss_random_class ; spawn_cls=$REPLY ; G_BOSS_DRY=0
            elif (( G_B_DRY >= 30 && alive_B == 0 )) ; then
                spawn_cls=EnemyB ; G_B_DRY=0
            # 0/1 Boss 时的小怪配比：V40% / Q25% / M15% / B18% / Boss2%
            elif (( _r < 400 )) ; then spawn_cls=EnemyV
            elif (( _r < 650 )) ; then spawn_cls=EnemyQ
            elif (( _r < 800 )) ; then spawn_cls=EnemyM
            elif (( _r < 980 )) ; then spawn_cls=EnemyB
            else                       _boss_random_class ; spawn_cls=$REPLY
            fi
        fi

        if [[ "$spawn_cls" == "Boss" || "$spawn_cls" == "BossSpinner" ]] ; then G_BOSS_DRY=0
        else ((G_BOSS_DRY++)) ; fi
        if [[ "$spawn_cls" == "EnemyB" ]] ; then G_B_DRY=0
        elif [[ "$spawn_cls" != "Boss" && "$spawn_cls" != "BossSpinner" ]] ; then ((G_B_DRY++)) ; fi

        xo_obj_born "$spawn_cls"
        ENEMIES+=("$REPLY")
    }

    # ---- 13. 刷掉落物 ----
    (( G_DROP_TICK++ % 100 == 0 )) && (( RANDOM % 100 < 60 )) && \
        (( ${#DROPS[@]} < DROP_LIMIT )) && {
        local -n _pdl=$PLAYER
        local _lanes_now=${_pdl["{lanes}$X"]:-0}
        unset -n _pdl
        local _drop_type=''
        local _r=$(( RANDOM % 100 ))
        if (( _lanes_now >= 1 && _lanes_now <= 3 )) ; then
            if (( _r < 25 )) ; then _drop_type='L'
            elif (( _r < 40 )) ; then _drop_type='S'
            else
                local _others=(2 3 4 5 H b m)
                _drop_type="${_others[RANDOM % 7]}"
            fi
        elif (( _lanes_now == 0 )) ; then
            if (( _r < 15 )) ; then _drop_type='L'
            elif (( _r < 30 )) ; then _drop_type='S'
            else
                local _others=(2 3 4 5 H b m)
                _drop_type="${_others[RANDOM % 7]}"
            fi
        else
            local _all=(2 3 4 5 H b m L S)
            _drop_type="${_all[RANDOM % 9]}"
        fi
        xo_obj_born Drop "$_drop_type"
        DROPS+=("$REPLY")
    }

    # ---- 14. 刷飘字 ----
    (( G_WORD_TICK++ % 250 == 0 )) && (( ${#WORDS[@]} < WORD_LIMIT )) && {
        local _wtext="${WORD_LIST[RANDOM % ${#WORD_LIST[@]}]}"
        local _ww
        str_display_width "$_wtext" _ww
        if (( _ww <= SCREEN_W - 4 )) ; then
            xo_obj_born Word "$_wtext"
            WORDS+=("$REPLY")
        fi
    }

    return 0
}

# ============================================================================
# play_game — 单局主循环（帧循环，输入/逻辑/渲染三频率独立）
# ============================================================================
play_game () {
    local key running=1
    local -i paused=0 paused_drawn=0
    local msg= msg_tick=0
    local -i bomb_fx_tick=0
    local -i hud_tick=0
    local last_bonus_str='__init__'
    # 注意：这里不能声明为 local -i。下面多处用 printf -v _t 写入 ANSI
    # 转义字符串，integer 属性会让 bash 把字符串当算术表达式求值并报错。
    local _t

    local LAST_US=${EPOCHREALTIME/./}
    local -i LOGIC_ACC_US=0
    local -i RENDER_ACC_US=$RENDER_US
    # 只有逻辑 tick 会改变场景；两个 tick 之间的重复渲染是纯浪费。
    # 需要重画时置 1（首次 / 每次 tick / load 后）。
    local -i need_render=1

    screen_clear
    _mouse_on
    FRAME_BUF=""
    draw_frame
    draw_hud_line2
    printf '%s' "$FRAME_BUF"
    FRAME_BUF=""

    while : ; do
        # ---- 采样时间，两个累加器独立 ----
        local NOW_US=${EPOCHREALTIME/./}
        local DELTA_US=$(( NOW_US - LAST_US ))
        LAST_US=$NOW_US
        (( DELTA_US > TICK_US * 5 )) && DELTA_US=$(( TICK_US * 5 ))
        LOGIC_ACC_US=$(( LOGIC_ACC_US + DELTA_US ))
        RENDER_ACC_US=$(( RENDER_ACC_US + DELTA_US ))

        # ---- 读输入（高频 100Hz）----
        G_DX=0 ; G_DY=0
        local -i paused_changed=0 _in_n=0
        while IFS= read -rsn1 -t 0.01 key ; do
            (( _in_n++ ))
            (( _in_n > 64 )) && break
            case "$key" in
                $'\e')
                    local _mseq='' _mc
                    while IFS= read -rsn1 -t 0.05 _mc ; do
                        _mseq+=$_mc
                        [[ "$_mc" == M || "$_mc" == m ]] && break
                    done
                    if (( G_MOUSE_ON && ! paused )) ; then
                        _mouse_apply "$_mseq"
                    fi
                    continue
                    ;;
                m|M)
                    ;;
                p|P)
                    if (( paused )) ; then
                        # 恢复游戏时保留 paused_drawn，让下面的清行逻辑擦掉 PAUSED 行
                        paused=0
                        msg="" ; msg_tick=0
                        need_render=1
                    else
                        paused=1
                        paused_drawn=0
                    fi
                    paused_changed=1
                    ;;
                q|Q) running=0 ; break ;;
                s|S)
                    if (( paused )) ; then
                        if save_game ; then msg="SAVED" ; else msg="SAVE FAILED" ; fi
                        msg_tick=50
                    else
                        G_DY=1
                    fi
                    ;;
                l|L)
                    if (( paused )) ; then
                        if load_game ; then
                            # 读档成功后立刻回到游戏，不再停在暂停画面
                            paused=0
                            paused_drawn=0
                            msg="" ; msg_tick=0
                            screen_clear
                            FRAME_BUF=""
                            draw_frame
                            draw_hud_line2
                            printf '%s' "$FRAME_BUF"
                            FRAME_BUF=""
                            need_render=1
                            # 读档后屏幕已清空，强制下一帧重画 bonus 行，
                            # 否则 last_bonus_str 可能和读档前的值相同而跳过绘制。
                            last_bonus_str='__load__'
                        else
                            msg="LOAD FAILED"
                            msg_tick=50
                        fi
                    else
                        G_DX=1
                    fi
                    ;;
                a|A|h|H) (( paused )) || G_DX=-1 ;;
                d|D)     (( paused )) || G_DX=1  ;;
                w|W|k|K) (( paused )) || G_DY=-1 ;;
                j|J)     (( paused )) || G_DY=1  ;;
                y|Y)     (( paused )) || { G_DX=-1 ; G_DY=-1 ; } ;;
                u|U)     (( paused )) || { G_DX=1  ; G_DY=-1 ; } ;;
                b|B)     (( paused )) || { G_DX=-1 ; G_DY=1  ; } ;;
                n|N)     (( paused )) || { G_DX=1  ; G_DY=1  ; } ;;
                ' ')
                    if (( !paused )) ; then
                        local -n _bp_tmp=$PLAYER
                        (( ${_bp_tmp["{bombs}$X"]:-0} > 0 )) && G_WANT_BOMB=1
                        unset -n _bp_tmp
                    fi
                    ;;
            esac
        done
        ((running)) || { _mouse_off ; return 1 ; }

        # ---- want_bomb ----
        if (( G_WANT_BOMB )) ; then
            G_WANT_BOMB=0
            local -n _bp=$PLAYER
            _bp["{bombs}$X"]=$(( ${_bp["{bombs}$X"]:-0} - 1 ))
            unset -n _bp

            local _ceb
            for _ceb in "${ENEMY_BULLETS[@]}" ; do
                [[ -n "$_ceb" && -n "${XO_OBJ_POOL[$_ceb]+_}" ]] || continue
                xo_obj_kill "$_ceb"
            done
            ENEMY_BULLETS=()

            local -a bomb_alive=()
            local -i bomb_score=0
            local -i _bomb_n=${#ENEMIES[@]}
            local -i _bomb_pct=100
            local -n _bp_pct=$PLAYER
            _bomb_pct=${_bp_pct["{score_pct}$X"]:-100}
            unset -n _bp_pct
            for e in "${ENEMIES[@]}" ; do
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local new_hp=$(( ${_e["{hp}$X"]} - 10 ))
                _e["{hp}$X"]=$new_hp
                local escore=${_e["{score}$X"]}
                local _ex=${_e["{x}$X"]} _ey=${_e["{y}$X"]}
                local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}
                local _eart=${_e["{art}$X"]}
                unset -n _e
                if (( new_hp <= 0 )) ; then
                    bomb_score=$(( bomb_score + escore * _bomb_pct / 100 ))
                    ((G_KILLS++))
                    if Base_is_a "$e" BossBase ; then
                        ((G_BOSS_KILLS++))
                        _boss_on_death "$e" "$_ex" "$_ey" "$_ew" "$_eh" "$_eart"
                    fi
                    xo_obj_kill "$e"
                else
                    bomb_alive+=("$e")
                fi
            done
            ENEMIES=("${bomb_alive[@]}")
            if (( _bomb_n >= 5 && ${#ENEMIES[@]} == 0 )) ; then
                _score_bonus "$CLEAR_SCORE_BONUS"
                if (( CLEAR_BANNER_TICK > 0 )) ; then
                    CLEAR_BANNER_TEXT+="  +${CLEAR_SCORE_BONUS} CLEAR"
                else
                    _clear_banner_start "ALL ENEMIES CLEARED  +${CLEAR_SCORE_BONUS}"
                fi
            fi
            local -n _bp2=$PLAYER
            _bp2["{score}$X"]=$(( ${_bp2["{score}$X"]:-0} + bomb_score ))
            unset -n _bp2
            bomb_fx_tick=50
        fi

        # ---- 暂停 ----
        if (( paused )) ; then
            if (( !paused_drawn )) ; then
                local _s='PAUSED  (p=resume  q=quit  s=save  l=load)'
                local _maxw=$(( SCREEN_W - 2 ))
                _s="${_s:0:_maxw}"
                local _t
                printf -v _t '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
                paused_drawn=1
            fi
            if (( msg_tick > 0 )) ; then
                local _s="$msg"
                local _maxw=$(( SCREEN_W - 2 ))
                _s="${_s:0:_maxw}"
                local _t
                printf -v _t '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
                ((msg_tick--))
                if (( msg_tick == 0 )) ; then
                    local _t2
                    printf -v _t2 '\033[5;2H\033[K\033[5;%dH%s' "$SCREEN_W" "$FRAME_V"
                    FRAME_BUF+="$_t2"
                    paused_drawn=0
                fi
            fi
            if [[ -n "$FRAME_BUF" ]] ; then
                printf '%s' "$FRAME_BUF"
                FRAME_BUF=""
            fi
            LOGIC_ACC_US=0
            continue
        fi
        if (( paused_drawn )) ; then
            local _t
            printf -v _t '\033[5;2H\033[K\033[5;%dH%s' "$SCREEN_W" "$FRAME_V"
            FRAME_BUF+="$_t"
            paused_drawn=0
        fi

        # ---- 逻辑 tick（独立频率）----
        while (( LOGIC_ACC_US >= TICK_US )) ; do
            LOGIC_ACC_US=$(( LOGIC_ACC_US - TICK_US ))
            _play_game_tick
            need_render=1
            (( G_GAME_OVER )) && break
        done

        # ---- 渲染帧（独立频率）----
        if (( RENDER_ACC_US >= RENDER_US )) ; then
            RENDER_ACC_US=$(( RENDER_ACC_US - RENDER_US ))

            # 场景与 HUD 的数值都只在 tick 后变化；没有 tick 时整块跳过，
            # 避免以 2 倍逻辑帧率做完全相同的重画。
            if (( need_render )) ; then
                if (( hud_tick % 3 == 0 )) ; then
                    draw_hud_line1
                fi
                ((hud_tick++))

                local -n _pbh=$PLAYER
                local _cbs="$(( ${_pbh["{t2}$X"]:-0} / FPS )) $(( ${_pbh["{t3}$X"]:-0} / FPS )) $(( ${_pbh["{t4}$X"]:-0} / FPS )) $(( ${_pbh["{t5}$X"]:-0} / FPS )) $(( ${_pbh["{mt}$X"]:-0} / FPS )) $(( ${_pbh["{lt}$X"]:-0} / FPS )) $(( ${_pbh["{st}$X"]:-0} / FPS )) ${_pbh["{lanes}$X"]:-0}"
                unset -n _pbh
                if [[ "$_cbs" != "$last_bonus_str" ]] ; then
                    draw_bonus_hud
                    last_bonus_str=$_cbs
                fi

                render_hit_fx_clear_expired
                render
                render_hit_fx
                need_render=0
            fi

            if (( msg_tick > 0 )) ; then
                local _s="$msg"
                local _maxw=$(( SCREEN_W - 2 ))
                _s="${_s:0:_maxw}"
                local _t
                printf -v _t '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
                FRAME_BUF+="$_t"
                ((msg_tick--))
                if (( msg_tick == 0 )) ; then
                    local _t2
                    printf -v _t2 '\033[5;2H\033[K\033[5;%dH%s' "$SCREEN_W" "$FRAME_V"
                    FRAME_BUF+="$_t2"
                fi
            fi

            if (( bomb_fx_tick > 0 )) ; then
                render_bomb_fx
                ((bomb_fx_tick--))
            elif (( ${#BOMB_FX_POS[@]} > 0 )) ; then
                local _bi _t
                for (( _bi=0; _bi<${#BOMB_FX_POS[@]}; _bi+=2 )) ; do
                    printf -v _t '\033[%d;%dH ' "${BOMB_FX_POS[_bi]}" "${BOMB_FX_POS[_bi+1]}"
                    FRAME_BUF+="$_t"
                done
                BOMB_FX_POS=()
            fi

            if (( BOSS_DEATH_TICK > 0 )) ; then
                render_boss_death
                ((BOSS_DEATH_TICK--))
            elif (( ${#BOSS_DEATH_POS[@]} > 0 )) ; then
                local _bi _t
                for (( _bi=0; _bi<${#BOSS_DEATH_POS[@]}; _bi+=2 )) ; do
                    printf -v _t '\033[%d;%dH ' "${BOSS_DEATH_POS[_bi]}" "${BOSS_DEATH_POS[_bi+1]}"
                    FRAME_BUF+="$_t"
                done
                BOSS_DEATH_POS=()
            fi

            (( CLEAR_BANNER_TICK > 0 )) && render_clear_banner

            if [[ -n "$FRAME_BUF" ]] ; then
                printf '%s' "$FRAME_BUF"
                FRAME_BUF=""
            fi
        fi

        (( G_GAME_OVER )) && { _mouse_off ; return 0 ; }
    done
}
