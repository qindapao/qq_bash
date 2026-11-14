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

# render 层
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/render/frame.sh"
. "$STRAFE_PROJ_DIR/render/hud.sh"
. "$STRAFE_PROJ_DIR/render/scene.sh"
. "$STRAFE_PROJ_DIR/render/fx.sh"

# save 层
. "$STRAFE_PROJ_DIR/save/save.sh"

# ============================================================================
# _play_game_tick — 单个逻辑 tick（纯计算，绝不碰终端）
# ============================================================================
_play_game_tick () {
    local b e d eb m w

    # ---- 0. 奖励计时器递减（每 tick 减 1）----
    local -n _pb=$PLAYER
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
                if (( _newhp <= 0 )) ; then
                    _edead[_j]=1
                    ((_ndead++))
                    score_gain=$(( score_gain + _escore[_j] ))
                    if [[ "${_ecls[_j]}" == "Boss" ]] ; then
                        BOSS_DEATH_POS=()
                        local _dr=0 _drest=${_eart[_j]}
                        while [[ -n "$_drest" ]] ; do
                            local _dl=${_drest%%$'\n'*}
                            if [[ "$_drest" == *$'\n'* ]] ; then _drest=${_drest#*$'\n'}
                            else _drest=''
                            fi
                            local _dc=0 _dlen=${#_dl}
                            while (( _dc < _dlen )) ; do
                                local _dch=${_dl:_dc:1}
                                [[ "$_dch" != " " ]] && BOSS_DEATH_POS+=($((_ey[_j] + _dr)) $((_ex[_j] + _dc)))
                                ((_dc++))
                            done
                            ((_dr++))
                        done
                        BOSS_DEATH_TICK=30
                        local _bdt=(2 3 4 5 H b m L S)
                        local _bdc="${_bdt[RANDOM % 9]}"
                        xo_obj_born Drop "$_bdc"
                        local -n _bd=$REPLY
                        _bd["{x}$X"]=$(( _ex[_j] + _ew[_j] / 2 ))
                        _bd["{y}$X"]=$(( _ey[_j] + _eh[_j] - 1 ))
                        unset -n _bd
                        DROPS+=("$REPLY")
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
                if (( _newhp <= 0 )) ; then
                    _edead[_j]=1
                    ((_ndead++))
                    score_gain=$(( score_gain + _escore[_j] ))
                    if [[ "${_ecls[_j]}" == "Boss" ]] ; then
                        BOSS_DEATH_POS=()
                        local _dr=0 _drest=${_eart[_j]}
                        while [[ -n "$_drest" ]] ; do
                            local _dl=${_drest%%$'\n'*}
                            if [[ "$_drest" == *$'\n'* ]] ; then _drest=${_drest#*$'\n'}
                            else _drest=''
                            fi
                            local _dc=0 _dlen=${#_dl}
                            while (( _dc < _dlen )) ; do
                                local _dch=${_dl:_dc:1}
                                [[ "$_dch" != " " ]] && BOSS_DEATH_POS+=($((_ey[_j] + _dr)) $((_ex[_j] + _dc)))
                                ((_dc++))
                            done
                            ((_dr++))
                        done
                        BOSS_DEATH_TICK=30
                        local _bdt=(2 3 4 5 H b m L S)
                        local _bdc="${_bdt[RANDOM % 9]}"
                        xo_obj_born Drop "$_bdc"
                        local -n _bd=$REPLY
                        _bd["{x}$X"]=$(( _ex[_j] + _ew[_j] / 2 ))
                        _bd["{y}$X"]=$(( _ey[_j] + _eh[_j] - 1 ))
                        unset -n _bd
                        DROPS+=("$REPLY")
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
    local _sx1=$(( px - 4 )) _sx2=$(( px + 4 ))
    local _sy1=$(( py - 1 )) _sy2=$(( py + 1 ))

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
           py >= _ey[_j] && py < _ey[_j] + _eh[_j] )) && \
            player_dmg=$(( player_dmg + 3 ))
    done

    if (( player_dmg > 0 && G_INV == 0 )) ; then
        p["{hp}$X"]=$(( ${p["{hp}$X"]} - player_dmg ))
        G_INV=30
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
    # 拾取用整架飞机的 ASCII art 包围盒：
    #   普通形态：x-1 .. x+1，y .. y+1（o|o / -'-）
    #   护盾形态：x-4 .. x+4，y-1 .. y+1（.-----. / /  o|o  \ / _._）
    # 注意：敌机/敌弹碰撞仍只用 px/py 这个竖线位置，本改动不影响它们。
    local _pal=${p["{al}$X"]:-1}
    local _px1=$(( px - _pal )) _px2=$(( px + _pal ))
    local _py1=$(( py - _sh )) _py2=$(( py + 1 ))

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
                    (( ${p["{hp}$X"]} > 20 )) && p["{hp}$X"]=20
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

    # ---- 11. 死亡判定 ----
    local -i _hp_final=${p["{hp}$X"]}
    unset -n p
    (( _hp_final <= 0 )) && { G_GAME_OVER=1 ; return 0 ; }

    # ---- 12. 刷怪 ----
    (( G_ENEMY_TICK++ % 50 == 0 )) && (( ${#ENEMIES[@]} < ENEMY_LIMIT )) && {
        local alive_B=0 alive_Boss=0
        for e in "${ENEMIES[@]}" ; do
            [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
            local -n _e=$e
            local _c=${_e["{CLS}$X"]}
            [[ "$_c" == "EnemyB" ]] && ((alive_B++))
            [[ "$_c" == "Boss"   ]] && ((alive_Boss++))
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
                spawn_cls=Boss ; G_BOSS_DRY=0
            elif (( G_B_DRY >= 30 && alive_B == 0 )) ; then
                spawn_cls=EnemyB ; G_B_DRY=0
            # 0/1 Boss 时的小怪配比：V40% / Q25% / M15% / B18% / Boss2%
            elif (( _r < 400 )) ; then spawn_cls=EnemyV
            elif (( _r < 650 )) ; then spawn_cls=EnemyQ
            elif (( _r < 800 )) ; then spawn_cls=EnemyM
            elif (( _r < 980 )) ; then spawn_cls=EnemyB
            else                       spawn_cls=Boss
            fi
        fi

        if [[ "$spawn_cls" == "Boss" ]] ; then G_BOSS_DRY=0
        else ((G_BOSS_DRY++)) ; fi
        if [[ "$spawn_cls" == "EnemyB" ]] ; then G_B_DRY=0
        elif [[ "$spawn_cls" != "Boss" ]] ; then ((G_B_DRY++)) ; fi

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
        local -i paused_changed=0
        while IFS= read -rsn1 -t 0.01 key ; do
            case "$key" in
                p|P) paused=$((1-paused)) ; paused_drawn=0 ; paused_changed=1 ;;
                q|Q) running=0 ; break ;;
                s|S)
                    if (( paused )) ; then
                        save_game
                        msg="SAVED" ; msg_tick=50
                    else
                        G_DY=1
                    fi
                    ;;
                l|L)
                    if (( paused )) ; then
                        if load_game ; then
                            screen_clear
                            FRAME_BUF=""
                            draw_frame
                            draw_hud_line2
                            printf '%s' "$FRAME_BUF"
                            FRAME_BUF=""
                            msg="LOADED"
                            need_render=1
                            # 读档后屏幕已清空，强制下一帧重画 bonus 行，
                            # 否则 last_bonus_str 可能和读档前的值相同而跳过绘制。
                            last_bonus_str='__load__'
                        else
                            msg="LOAD FAILED"
                        fi
                        msg_tick=50
                    else
                        G_DX=1
                    fi
                    ;;
                a|A|h|H) (( paused )) || G_DX=-1 ;;
                d|D)     (( paused )) || G_DX=1  ;;
                w|W|k|K) (( paused )) || G_DY=-1 ;;
                j|J)     (( paused )) || G_DY=1  ;;
                ' ')
                    if (( !paused )) ; then
                        local -n _bp_tmp=$PLAYER
                        (( ${_bp_tmp["{bombs}$X"]:-0} > 0 )) && G_WANT_BOMB=1
                        unset -n _bp_tmp
                    fi
                    ;;
            esac
        done
        ((running)) || return 1

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
            for e in "${ENEMIES[@]}" ; do
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local new_hp=$(( ${_e["{hp}$X"]} - 10 ))
                _e["{hp}$X"]=$new_hp
                local escore=${_e["{score}$X"]}
                unset -n _e
                if (( new_hp <= 0 )) ; then
                    bomb_score=$(( bomb_score + escore ))
                    xo_obj_kill "$e"
                else
                    bomb_alive+=("$e")
                fi
            done
            ENEMIES=("${bomb_alive[@]}")
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

                render
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

            if [[ -n "$FRAME_BUF" ]] ; then
                printf '%s' "$FRAME_BUF"
                FRAME_BUF=""
            fi
        fi

        (( G_GAME_OVER )) && return 0
    done
}
