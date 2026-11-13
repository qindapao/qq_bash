# game/play_game.sh — 单局主循环（游戏核心逻辑）
#
# 依赖：所有类定义、所有 render、save、config
# 这是最重的模块，所有下游模块都在这里被调用
[[ -n "${_STRAFE_PLAY_GAME_SH:-}" ]] && return 0
_STRAFE_PLAY_GAME_SH=1

. "$STRAFE_LIB_HOME/xo.sh"

# config 层
_DIR_PG="$(dirname "${BASH_SOURCE[0]}")"
. "$_DIR_PG/../config/const.sh"
. "$_DIR_PG/../config/color.sh"
. "$_DIR_PG/../config/art.sh"
. "$_DIR_PG/../config/words.sh"
. "$_DIR_PG/../config/globals.sh"

# classes 层
. "$_DIR_PG/../classes/base_types.sh"
. "$_DIR_PG/../classes/projectiles/bullet.sh"
. "$_DIR_PG/../classes/projectiles/missile.sh"
. "$_DIR_PG/../classes/projectiles/enemy_bullet.sh"
. "$_DIR_PG/../classes/enemies/enemy_base.sh"
. "$_DIR_PG/../classes/enemies/enemy_v.sh"
. "$_DIR_PG/../classes/enemies/enemy_q.sh"
. "$_DIR_PG/../classes/enemies/enemy_m.sh"
. "$_DIR_PG/../classes/enemies/enemy_b.sh"
. "$_DIR_PG/../classes/enemies/boss.sh"
. "$_DIR_PG/../classes/pickups/drop.sh"
. "$_DIR_PG/../classes/pickups/word.sh"
. "$_DIR_PG/../classes/plane/plane_helpers.sh"
. "$_DIR_PG/../classes/plane/plane.sh"

# render 层
. "$_DIR_PG/../render/ansi.sh"
. "$_DIR_PG/../render/frame.sh"
. "$_DIR_PG/../render/hud.sh"
. "$_DIR_PG/../render/scene.sh"
. "$_DIR_PG/../render/fx.sh"

# save 层
. "$_DIR_PG/../save/save.sh"

play_game () {
    local b e d eb m w key dx dy running=1
    local enemy_tick=0 drop_tick=0 word_tick=0 fire_cd=0 missile_cd=0 missile_side=0
    local b_dry=0 boss_dry=0
    local paused=0 paused_drawn=0
    local msg= msg_tick=0
    local inv=0
    local bomb_fx_tick=0
    local hud_tick=0
    local last_bonus_str='__init__'

    local LAST_US=${EPOCHREALTIME/./}
    local -i ACC_US=0

    screen_clear
    draw_frame

    while : ; do
        local NOW_US=${EPOCHREALTIME/./}
        local DELTA_US=$(( NOW_US - LAST_US ))
        LAST_US=$NOW_US
        ACC_US=$(( ACC_US + DELTA_US ))
        local -i DEC_TICKS=0
        while (( ACC_US >= TICK_US )) ; do
            ((DEC_TICKS++))
            ACC_US=$(( ACC_US - TICK_US ))
        done
        (( DEC_TICKS > 100 )) && DEC_TICKS=100

        ((fire_cd > 0)) && ((fire_cd--))
        ((missile_cd > 0)) && ((missile_cd--))
        (( inv > 0 )) && ((inv--))

        if (( hud_tick % 6 == 0 )) ; then
            draw_hud_line1
            draw_hud_line2
        fi
        ((hud_tick++))

        local -n _pbh=$PLAYER
        local _cbs="$(( ${_pbh["{t2}$X"]:-0} / FPS )) $(( ${_pbh["{t3}$X"]:-0} / FPS )) $(( ${_pbh["{t4}$X"]:-0} / FPS )) $(( ${_pbh["{t5}$X"]:-0} / FPS )) $(( ${_pbh["{mt}$X"]:-0} / FPS )) $(( ${_pbh["{lt}$X"]:-0} / FPS )) $(( ${_pbh["{st}$X"]:-0} / FPS )) ${_pbh["{lanes}$X"]:-0}"
        unset -n _pbh
        if [[ "$_cbs" != "$last_bonus_str" ]] ; then
            draw_bonus_hud
            last_bonus_str=$_cbs
        fi

        local -n _pb=$PLAYER
        if (( DEC_TICKS > 0 )) ; then
            local _tk _tv _new
            for _tk in "{t2}$X" "{t3}$X" "{t4}$X" "{t5}$X" "{mt}$X" "{lt}$X" "{st}$X" ; do
                _tv=${_pb[$_tk]:-0}
                if (( _tv > 0 )) ; then
                    _new=$(( _tv - DEC_TICKS ))
                    (( _new < 0 )) && _new=0
                    _pb["$_tk"]=$_new
                fi
            done
        fi

        if (( ${_pb["{lt}$X"]:-0} == 0 )) ; then
            _pb["{lanes}$X"]=0
        fi

        if (( ${_pb["{shield}$X"]:-0} && ${_pb["{st}$X"]:-0} == 0 )) ; then
            unset -n _pb
            _plane_set_shield "$PLAYER" 0
            local -n _pb=$PLAYER
        fi

        local _bt=${_pb["{bullet}$X"]}
        local _sym='.'
        if [[ -n "$_bt" && -n "${XO_OBJ_POOL[$_bt]+_}" ]] ; then
            local -n _bo=$_bt
            _sym=${_bo["{symbol}$X"]}
            unset -n _bo
        fi
        local _tk_cur=''
        case "$_sym" in
            '*') _tk_cur="{t2}$X" ;;
            '@') _tk_cur="{t3}$X" ;;
            '$') _tk_cur="{t4}$X" ;;
            '|') _tk_cur="{t5}$X" ;;
        esac
        if [[ -n "$_tk_cur" ]] ; then
            if (( ${_pb[$_tk_cur]:-0} == 0 )) ; then
                local _old=${_pb["{bullet}$X"]}
                [[ -n "$_old" && -n "${XO_OBJ_POOL[$_old]+_}" ]] && xo_obj_kill "$_old"
                xo_obj_born BulletType '.' 1
                _pb["{bullet}$X"]=$REPLY
            fi
        fi
        unset -n _pb

        dx=0 ; dy=0 ; local want_bomb=0
        while IFS= read -rsn1 -t 0.01 key ; do
            case "$key" in
                p|P) paused=$((1-paused)) ; paused_drawn=0 ;;
                q|Q) running=0 ; break ;;
                s|S)
                    if (( paused )) ; then
                        save_game
                        msg="SAVED" ; msg_tick=50
                    else
                        dy=1
                    fi
                    ;;
                l|L)
                    if (( paused )) ; then
                        if load_game ; then
                            screen_clear
                            draw_frame
                            msg="LOADED" ; msg_tick=50
                        else
                            msg="LOAD FAILED" ; msg_tick=50
                        fi
                    else
                        dx=1
                    fi
                    ;;
                a|A|h|H) (( paused )) || dx=-1 ;;
                d|D)     (( paused )) || dx=1  ;;
                w|W|k|K) (( paused )) || dy=-1 ;;
                j|J)     (( paused )) || dy=1  ;;
                ' ')
                    if (( !paused )) ; then
                        local -n _bp_tmp=$PLAYER
                        if (( ${_bp_tmp["{bombs}$X"]:-0} > 0 )) ; then
                            want_bomb=1
                        fi
                        unset -n _bp_tmp
                    fi
                    ;;
            esac
        done
        ((running)) || return 1

        if (( want_bomb )) ; then
            local -n _bp=$PLAYER
            _bp["{bombs}$X"]=$(( ${_bp["{bombs}$X"]:-0} - 1 ))
            unset -n _bp

            local _ceb
            for _ceb in "${ENEMY_BULLETS[@]}" ; do
                [[ -n "$_ceb" && -n "${XO_OBJ_POOL[$_ceb]+_}" ]] || continue
                local -n _ce=$_ceb
                printf '\033[%d;%dH ' "${_ce["{y}$X"]}" "${_ce["{x}$X"]}"
                unset -n _ce
                xo_obj_kill "$_ceb"
            done
            ENEMY_BULLETS=()

            local -a bomb_alive=()
            local bomb_score=0
            for e in "${ENEMIES[@]}" ; do
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local new_hp=$(( ${_e["{hp}$X"]} - 10 ))
                _e["{hp}$X"]=$new_hp
                local escore=${_e["{score}$X"]}
                local _ay=${_e["{y}$X"]} _ax=${_e["{x}$X"]}
                local _art=${_e["{art}$X"]} _h=${_e["{h}$X"]}
                local _ecls=${_e["{CLS}$X"]}
                local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}
                unset -n _e
                if (( new_hp <= 0 )) ; then
                    bomb_score=$(( bomb_score + escore ))
                    _art_clear_at "$_ay" "$_ax" "$_art"
                    (( _ay + _h < SCREEN_H )) && { printf '\033[%d;%dH\033[K\033[%d;%dH%s' $((_ay + _h)) "$_ax" $((_ay + _h)) "$SCREEN_W" "$FRAME_V" ; }
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

        if (( paused )) ; then
            if (( !paused_drawn )) ; then
                local _s='PAUSED  (p=resume  q=quit  s=save  l=load)'
                local _maxw=$(( SCREEN_W - 2 ))
                _s="${_s:0:_maxw}"
                printf '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
                paused_drawn=1
            fi
            if (( msg_tick > 0 )) ; then
                local _s="$msg"
                local _maxw=$(( SCREEN_W - 2 ))
                _s="${_s:0:_maxw}"
                printf '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
                ((msg_tick--))
                if (( msg_tick == 0 )) ; then paused_drawn=0 ; fi
            fi
            continue
        fi
        if (( paused_drawn )) ; then
            printf '\033[5;2H\033[K\033[5;%dH%s' "$SCREEN_W" "$FRAME_V"
            paused_drawn=0
        fi

        (( dx || dy )) && xo_call "$PLAYER" move "$dx" "$dy"

        if (( fire_cd == 0 )) ; then
            xo_call "$PLAYER" fire
            local -n _pp=$PLAYER
            local _fbt=${_pp["{bullet}$X"]}
            local _fsym='.'
            if [[ -n "$_fbt" && -n "${XO_OBJ_POOL[$_fbt]+_}" ]] ; then
                local -n _fbo=$_fbt
                _fsym=${_fbo["{symbol}$X"]}
                unset -n _fbo
            fi
            unset -n _pp
            if [[ "$_fsym" == "|" ]] ; then fire_cd=0 ; else fire_cd=6 ; fi
        fi

        local -n _pm=$PLAYER
        if (( ${_pm["{mt}$X"]:-0} > 0 && missile_cd == 0 )) ; then
            local _my=$(( ${_pm["{y}$X"]} - 1 ))
            local _mx
            if (( missile_side )) ; then
                _mx=$(( ${_pm["{x}$X"]} - 1 ))
                missile_side=0
            else
                _mx=$(( ${_pm["{x}$X"]} + 1 ))
                missile_side=1
            fi
            (( _mx < 2 )) && _mx=2
            (( _mx > SCREEN_W - 2 )) && _mx=$(( SCREEN_W - 2 ))
            xo_obj_born Missile "$_mx" "$_my" 2
            MISSILES+=("$REPLY")
            missile_cd=10
        fi
        unset -n _pm

        CLEAR_BATCH=()
        local -a alive_b=()
        for b in "${BULLETS[@]}" ; do
            [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
            xo_call "$b" move
            local -n _b=$b
            if (( ${_b["{y}$X"]} < GAME_TOP || ${_b["{x}$X"]} < 2 || ${_b["{x}$X"]} > SCREEN_W - 2 )) ; then
                unset -n _b
                xo_obj_kill "$b"
            else
                unset -n _b
                alive_b+=("$b")
            fi
        done
        BULLETS=("${alive_b[@]}")
        if (( ${#CLEAR_BATCH[@]} )) ; then
            local _cbuf='' _ciy _cix _ct
            for (( _ci=0 ; _ci<${#CLEAR_BATCH[@]} ; _ci+=2 )) ; do
                _ciy=${CLEAR_BATCH[_ci]}
                _cix=${CLEAR_BATCH[_ci+1]}
                printf -v _ct '\033[%d;%dH ' "$_ciy" "$_cix"
                _cbuf+=$_ct
            done
            printf '%s' "$_cbuf"
        fi

        local -a alive_m=()
        for m in "${MISSILES[@]}" ; do
            [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
            xo_call "$m" move
            if (( $? == 0 )) ; then
                alive_m+=("$m")
            else
                xo_obj_kill "$m"
            fi
        done
        MISSILES=("${alive_m[@]}")

        local -a alive_eb=()
        for eb in "${ENEMY_BULLETS[@]}" ; do
            [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
            local ey ex
            local -n _eb=$eb
            ey=${_eb["{y}$X"]} ; ex=${_eb["{x}$X"]}
            unset -n _eb
            xo_call "$eb" move
            if (( $? == 0 )) ; then
                alive_eb+=("$eb")
            else
                printf '\033[%d;%dH ' "$ey" "$ex"
                xo_obj_kill "$eb"
            fi
        done
        ENEMY_BULLETS=("${alive_eb[@]}")

        local -a alive_e=()
        for e in "${ENEMIES[@]}" ; do
            [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
            xo_call "$e" move
            if (( $? == 0 )) ; then
                alive_e+=("$e")
            else
                xo_obj_kill "$e"
            fi
        done
        ENEMIES=("${alive_e[@]}")

        local -a alive_d=()
        for d in "${DROPS[@]}" ; do
            [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
            local dy_pos dx_pos
            local -n _d=$d
            dy_pos=${_d["{y}$X"]} ; dx_pos=${_d["{x}$X"]}
            unset -n _d
            xo_call "$d" move
            if (( $? == 0 )) ; then
                alive_d+=("$d")
            else
                printf '\033[%d;%dH ' "$dy_pos" "$dx_pos"
                xo_obj_kill "$d"
            fi
        done
        DROPS=("${alive_d[@]}")

        local -a alive_w=()
        for w in "${WORDS[@]}" ; do
            [[ -n "$w" && -n "${XO_OBJ_POOL[$w]+_}" ]] || continue
            xo_call "$w" move
            if (( $? == 0 )) ; then
                alive_w+=("$w")
            else
                xo_obj_kill "$w"
            fi
        done
        WORDS=("${alive_w[@]}")

        local -A killed_b=() killed_m=() killed_e=()
        local score_gain=0

        for b in "${BULLETS[@]}" ; do
            [[ -n "${killed_b[$b]+_}" ]] && continue
            [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
            local -n _b=$b
            local bx=${_b["{x}$X"]} by=${_b["{y}$X"]}
            local bdmg=${_b["{damage}$X"]}
            unset -n _b

            for e in "${ENEMIES[@]}" ; do
                [[ -n "${killed_e[$e]+_}" ]] && continue
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local _ex=${_e["{x}$X"]} _ey=${_e["{y}$X"]}
                local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}

                if (( bx >= _ex && bx < _ex + _ew && by >= _ey && by < _ey + _eh )) ; then
                    local new_hp=$(( ${_e["{hp}$X"]} - bdmg ))
                    _e["{hp}$X"]=$new_hp
                    local escore=${_e["{score}$X"]}
                    local _art=${_e["{art}$X"]} _h=${_e["{h}$X"]}
                    local _ecls=${_e["{CLS}$X"]} _ew2=${_e["{w}$X"]} _eh2=${_e["{h}$X"]}
                    unset -n _e
                    killed_b[$b]=1
                    if (( new_hp <= 0 )) ; then
                        killed_e[$e]=1
                        score_gain=$(( score_gain + escore ))
                        if [[ "$_ecls" == "Boss" ]] ; then
                            BOSS_DEATH_POS=()
                            local _dr=0 _drest=$_art
                            while [[ -n "$_drest" ]] ; do
                                local _dl=${_drest%%$'\n'*}
                                if [[ "$_drest" == *$'\n'* ]] ; then
                                    _drest=${_drest#*$'\n'}
                                else
                                    _drest=''
                                fi
                                local _dc=0 _dlen=${#_dl}
                                while (( _dc < _dlen )) ; do
                                    local _dch=${_dl:_dc:1}
                                    if [[ "$_dch" != " " ]] ; then
                                        BOSS_DEATH_POS+=($((_ey + _dr)) $((_ex + _dc)))
                                    fi
                                    ((_dc++))
                                done
                                ((_dr++))
                            done
                            BOSS_DEATH_TICK=30
                            (( _ey + _h < SCREEN_H )) && { printf '\033[%d;%dH\033[K\033[%d;%dH%s' $((_ey + _h)) "$_ex" $((_ey + _h)) "$SCREEN_W" "$FRAME_V" ; }
                            local _bdt=(1 3 4 5 H b m L S)
                            local _bdc="${_bdt[RANDOM % 9]}"
                            xo_obj_born Drop "$_bdc"
                            local -n _bd=$REPLY
                            _bd["{x}$X"]=$(( _ex + _ew2 / 2 ))
                            _bd["{y}$X"]=$(( _ey + _eh2 - 1 ))
                            unset -n _bd
                            DROPS+=("$REPLY")
                        else
                            _art_clear_at "$_ey" "$_ex" "$_art"
                            (( _ey + _h < SCREEN_H )) && { printf '\033[%d;%dH\033[K\033[%d;%dH%s' $((_ey + _h)) "$_ex" $((_ey + _h)) "$SCREEN_W" "$FRAME_V" ; }
                        fi
                        xo_obj_kill "$e"
                    fi
                    break
                fi
                unset -n _e
            done
        done

        for m in "${MISSILES[@]}" ; do
            [[ -n "${killed_m[$m]+_}" ]] && continue
            [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
            local -n _m=$m
            local mx=${_m["{x}$X"]} my=${_m["{y}$X"]}
            local mdmg=${_m["{damage}$X"]}
            unset -n _m

            for e in "${ENEMIES[@]}" ; do
                [[ -n "${killed_e[$e]+_}" ]] && continue
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local _ex=${_e["{x}$X"]} _ey=${_e["{y}$X"]}
                local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}

                if (( mx >= _ex && mx < _ex + _ew && my >= _ey && my < _ey + _eh )) ; then
                    local new_hp=$(( ${_e["{hp}$X"]} - mdmg ))
                    _e["{hp}$X"]=$new_hp
                    local escore=${_e["{score}$X"]}
                    local _art=${_e["{art}$X"]} _h=${_e["{h}$X"]}
                    local _ecls=${_e["{CLS}$X"]} _ew2=${_e["{w}$X"]} _eh2=${_e["{h}$X"]}
                    unset -n _e
                    killed_m[$m]=1
                    if (( new_hp <= 0 )) ; then
                        killed_e[$e]=1
                        score_gain=$(( score_gain + escore ))
                        if [[ "$_ecls" == "Boss" ]] ; then
                            BOSS_DEATH_POS=()
                            local _dr=0 _drest=$_art
                            while [[ -n "$_drest" ]] ; do
                                local _dl=${_drest%%$'\n'*}
                                if [[ "$_drest" == *$'\n'* ]] ; then
                                    _drest=${_drest#*$'\n'}
                                else
                                    _drest=''
                                fi
                                local _dc=0 _dlen=${#_dl}
                                while (( _dc < _dlen )) ; do
                                    local _dch=${_dl:_dc:1}
                                    if [[ "$_dch" != " " ]] ; then
                                        BOSS_DEATH_POS+=($((_ey + _dr)) $((_ex + _dc)))
                                    fi
                                    ((_dc++))
                                done
                                ((_dr++))
                            done
                            BOSS_DEATH_TICK=30
                            (( _ey + _h < SCREEN_H )) && { printf '\033[%d;%dH\033[K\033[%d;%dH%s' $((_ey + _h)) "$_ex" $((_ey + _h)) "$SCREEN_W" "$FRAME_V" ; }
                            local _bdt=(1 3 4 5 H b m L S)
                            local _bdc="${_bdt[RANDOM % 9]}"
                            xo_obj_born Drop "$_bdc"
                            local -n _bd=$REPLY
                            _bd["{x}$X"]=$(( _ex + _ew2 / 2 ))
                            _bd["{y}$X"]=$(( _ey + _eh2 - 1 ))
                            unset -n _bd
                            DROPS+=("$REPLY")
                        else
                            _art_clear_at "$_ey" "$_ex" "$_art"
                            (( _ey + _h < SCREEN_H )) && { printf '\033[%d;%dH\033[K\033[%d;%dH%s' $((_ey + _h)) "$_ex" $((_ey + _h)) "$SCREEN_W" "$FRAME_V" ; }
                        fi
                        xo_obj_kill "$e"
                    fi
                    break
                fi
                unset -n _e
            done
        done

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
                    local -n _m=$m
                    printf '\033[%d;%dH ' "${_m["{y}$X"]}" "${_m["{x}$X"]}"
                    unset -n _m
                    xo_obj_kill "$m"
                else
                    nm+=("$m")
                fi
            done
            MISSILES=("${nm[@]}")
        fi

        if ((${#killed_e[@]})) ; then
            local -a ne=()
            for e in "${ENEMIES[@]}" ; do
                [[ -n "${killed_e[$e]+_}" ]] || ne+=("$e")
            done
            ENEMIES=("${ne[@]}")
        fi

        local -n p=$PLAYER
        local px=${p["{x}$X"]} py=${p["{y}$X"]}
        local player_dmg=0

        local _sh=$(( ${p["{shield}$X"]:-0} ))
        local _sx1=$(( px - 4 )) _sx2=$(( px + 4 ))
        local _sy1=$(( py - 1 )) _sy2=$(( py + 1 ))

        local -a survive_eb=()
        for eb in "${ENEMY_BULLETS[@]}" ; do
            [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
            local -n _eb=$eb
            local _ebx=${_eb["{x}$X"]} _eby=${_eb["{y}$X"]}
            local _hit=0
            if (( _sh )) ; then
                if (( _ebx >= _sx1 && _ebx <= _sx2 && _eby >= _sy1 && _eby <= _sy2 )) ; then
                    _hit=1
                fi
            else
                if (( _ebx == px && _eby == py )) ; then
                    _hit=1
                fi
            fi
            if (( _hit )) ; then
                (( ! _sh )) && player_dmg=$(( player_dmg + ${_eb["{damage}$X"]} ))
                printf '\033[%d;%dH ' "$_eby" "$_ebx"
                unset -n _eb
                xo_obj_kill "$eb"
            else
                unset -n _eb
                survive_eb+=("$eb")
            fi
        done
        ENEMY_BULLETS=("${survive_eb[@]}")

        for e in "${ENEMIES[@]}" ; do
            [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
            local -n _e=$e
            local _ex=${_e["{x}$X"]} _ey=${_e["{y}$X"]}
            local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}
            if (( px >= _ex && px < _ex + _ew && py >= _ey && py < _ey + _eh )) ; then
                player_dmg=$(( player_dmg + 3 ))
            fi
            unset -n _e
        done

        if (( player_dmg > 0 && inv == 0 )) ; then
            p["{hp}$X"]=$(( ${p["{hp}$X"]} - player_dmg ))
            inv=30
            if (( ${p["{lt}$X"]:-0} > 0 && ${p["{lanes}$X"]:-0} > 0 )) ; then
                local _nl=$(( ${p["{lanes}$X"]} - 1 ))
                p["{lanes}$X"]=$_nl
                if (( _nl == 0 )) ; then
                    p["{lt}$X"]=0
                fi
            fi
        fi

        if (( score_gain > 0 )) ; then
            p["{score}$X"]=$(( ${p["{score}$X"]} + score_gain ))
        fi
        local hp=${p["{hp}$X"]}

        local -a survive_d2=()
        for d in "${DROPS[@]}" ; do
            [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
            local -n _d=$d
            if (( ${_d["{x}$X"]} == px && ${_d["{y}$X"]} == py )) ; then
                local dtype=${_d["{dtype}$X"]}
                printf '\033[%d;%dH ' "${_d["{y}$X"]}" "${_d["{x}$X"]}"
                unset -n _d
                xo_obj_kill "$d"

                case "$dtype" in
                    1|3|4|5)
                        p["{t2}$X"]=0 ; p["{t3}$X"]=0 ; p["{t4}$X"]=0 ; p["{t5}$X"]=0
                        local bsym bdmg tfield
                        case "$dtype" in
                            1) bsym='*' ; bdmg=2 ; tfield=t2 ;;
                            3) bsym='@' ; bdmg=3 ; tfield=t3 ;;
                            4) bsym='$' ; bdmg=4 ; tfield=t4 ;;
                            5) bsym='|' ; bdmg=3 ; tfield=t5 ;;
                        esac
                        local old_bt=${p["{bullet}$X"]}
                        [[ -n "$old_bt" && -n "${XO_OBJ_POOL[$old_bt]+_}" ]] && xo_obj_kill "$old_bt"
                        xo_obj_born BulletType "$bsym" "$bdmg"
                        p["{bullet}$X"]=$REPLY
                        case "$tfield" in
                            t2) p["{t2}$X"]=$BONUS_T2 ;;
                            t3) p["{t3}$X"]=$BONUS_T3 ;;
                            t4) p["{t4}$X"]=$BONUS_T4 ;;
                            t5) p["{t5}$X"]=$BONUS_T5 ;;
                        esac
                        ;;
                    H)
                        p["{hp}$X"]=$(( ${p["{hp}$X"]} + 3 ))
                        (( ${p["{hp}$X"]} > 20 )) && p["{hp}$X"]=20
                        ;;
                    b)
                        if (( ${p["{bombs}$X"]:-0} < 5 )) ; then
                            p["{bombs}$X"]=$(( ${p["{bombs}$X"]:-0} + 1 ))
                        fi
                        ;;
                    m)
                        p["{mt}$X"]=$BONUS_MT
                        ;;
                    L)
                        local _cur_lanes=${p["{lanes}$X"]:-0}
                        case "$_cur_lanes" in
                            0) p["{lanes}$X"]=1
                               p["{lanes_side}$X"]=$(( RANDOM % 2 ))
                               p["{lt}$X"]=$BONUS_LT ;;
                            1) p["{lanes}$X"]=2
                               p["{lt}$X"]=$BONUS_LT ;;
                            2) p["{lanes}$X"]=3
                               p["{lanes_side}$X"]=$(( RANDOM % 2 ))
                               p["{lt}$X"]=$BONUS_LT ;;
                            3) p["{lanes}$X"]=4
                               p["{lt}$X"]=$BONUS_LT ;;
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
        unset -n p

        (( hp <= 0 )) && return 0

        (( enemy_tick++ % 50 == 0 )) && (( ${#ENEMIES[@]} < ENEMY_LIMIT )) && {
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
            if (( alive_Boss >= 1 )) ; then
                if (( _r < 600 )) ; then spawn_cls=EnemyV
                elif (( _r < 850 )) ; then spawn_cls=EnemyQ
                elif (( _r < 950 )) ; then spawn_cls=EnemyM
                else                       spawn_cls=EnemyB
                fi
            else
                if (( boss_dry >= 300 )) ; then
                    spawn_cls=Boss ; boss_dry=0
                elif (( b_dry >= 30 && alive_B == 0 )) ; then
                    spawn_cls=EnemyB ; b_dry=0
                elif (( _r < 450 )) ; then spawn_cls=EnemyV
                elif (( _r < 700 )) ; then spawn_cls=EnemyQ
                elif (( _r < 800 )) ; then spawn_cls=EnemyM
                elif (( _r < 980 )) ; then spawn_cls=EnemyB
                else                       spawn_cls=Boss
                fi
            fi

            if [[ "$spawn_cls" == "Boss" ]] ; then
                boss_dry=0
            else
                ((boss_dry++))
            fi
            if [[ "$spawn_cls" == "EnemyB" ]] ; then b_dry=0
            elif [[ "$spawn_cls" != "Boss" ]] ; then ((b_dry++))
            fi
            xo_obj_born "$spawn_cls"
            ENEMIES+=("$REPLY")
        }

        (( drop_tick++ % 100 == 0 )) && (( RANDOM % 100 < 60 )) && (( ${#DROPS[@]} < DROP_LIMIT )) && {
            local -n _pdl=$PLAYER
            local _lanes_now=${_pdl["{lanes}$X"]:-0}
            unset -n _pdl
            local _drop_type=''
            local _r=$(( RANDOM % 100 ))
            if (( _lanes_now >= 1 && _lanes_now <= 3 )) ; then
                if (( _r < 25 )) ; then _drop_type='L'
                elif (( _r < 40 )) ; then _drop_type='S'
                else
                    local _others=(1 3 4 5 H b m)
                    _drop_type="${_others[RANDOM % 7]}"
                fi
            elif (( _lanes_now == 0 )) ; then
                if (( _r < 15 )) ; then _drop_type='L'
                elif (( _r < 30 )) ; then _drop_type='S'
                else
                    local _others=(1 3 4 5 H b m)
                    _drop_type="${_others[RANDOM % 7]}"
                fi
            else
                local _all=(1 3 4 5 H b m L S)
                _drop_type="${_all[RANDOM % 9]}"
            fi
            xo_obj_born Drop "$_drop_type"
            DROPS+=("$REPLY")
        }

        (( word_tick++ % 250 == 0 )) && (( ${#WORDS[@]} < WORD_LIMIT )) && {
            local _wtext="${WORD_LIST[RANDOM % ${#WORD_LIST[@]}]}"
            local _ww
            str_display_width "$_wtext" _ww
            if (( _ww <= SCREEN_W - 4 )) ; then
                xo_obj_born Word "$_wtext"
                WORDS+=("$REPLY")
            fi
        }

        if (( msg_tick > 0 )) ; then
            local _s="$msg"
            local _maxw=$(( SCREEN_W - 2 ))
            _s="${_s:0:_maxw}"
            printf '\033[5;2H\033[K%s\033[5;%dH%s' "$_s" "$SCREEN_W" "$FRAME_V"
            ((msg_tick--))
            if (( msg_tick == 0 )) ; then
                printf '\033[5;2H\033[K\033[5;%dH%s' "$SCREEN_W" "$FRAME_V"
            fi
        fi

        render

        if (( bomb_fx_tick > 0 )) ; then
            render_bomb_fx
            ((bomb_fx_tick--))
        elif (( ${#BOMB_FX_POS[@]} > 0 )) ; then
            local _bi
            for (( _bi=0; _bi<${#BOMB_FX_POS[@]}; _bi+=2 )) ; do
                printf '\033[%d;%dH ' "${BOMB_FX_POS[_bi]}" "${BOMB_FX_POS[_bi+1]}"
            done
            BOMB_FX_POS=()
        fi

        if (( BOSS_DEATH_TICK > 0 )) ; then
            render_boss_death
            ((BOSS_DEATH_TICK--))
        elif (( ${#BOSS_DEATH_POS[@]} > 0 )) ; then
            local _bi
            for (( _bi=0; _bi<${#BOSS_DEATH_POS[@]}; _bi+=2 )) ; do
                printf '\033[%d;%dH ' "${BOSS_DEATH_POS[_bi]}" "${BOSS_DEATH_POS[_bi+1]}"
            done
            BOSS_DEATH_POS=()
        fi
    done
}
