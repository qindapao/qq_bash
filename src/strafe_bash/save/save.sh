# save/save.sh — 最小存档/读档（只保存玩家进度）
[[ -n "${_STRAFE_SAVE_SH:-}" ]] && return 0
_STRAFE_SAVE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/game/init_game.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_helpers.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_types.sh"

# 只接受非负整数
_save_is_uint () {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

# 存档只包含：
#   score / hp / bombs / 道具计时器 / 当前武器槽 / 五把武器的 class 名
# 不保存敌人、子弹、掉落物、坐标、对象句柄，也不使用 x_tree。
save_game () {
    [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] || return 1
    local -n p=$PLAYER

    local -a _wcls=()
    local -i i _slot=1
    local _h
    for i in 1 2 3 4 5 ; do
        _h=${p["{w$i}$X"]}
        if [[ -n "$_h" && -n "${XO_OBJ_POOL[$_h]+_}" ]] ; then
            _wcls[$i]=${XO_OBJ_POOL[$_h]}
        elif (( i == 1 )) ; then
            _wcls[$i]=BulletTypeDefault
        else
            unset -n p
            return 1
        fi
    done
    for i in 1 2 3 4 5 ; do
        [[ "${p["{bullet}$X"]}" == "${p["{w$i}$X"]}" ]] && _slot=$i
    done

    local _pcls=${XO_OBJ_POOL[$PLAYER]}
    [[ "$_pcls" == "Plane" ]] && _pcls=PlaneBee
    local -A SAVE=(
        [version]=6
        [plane_cls]=$_pcls
        [score]=${p["{score}$X"]:-0}
        [hp]=${p["{hp}$X"]:-0}
        [bombs]=${p["{bombs}$X"]:-0}
        [t2]=${p["{t2}$X"]:-0}
        [t3]=${p["{t3}$X"]:-0}
        [t4]=${p["{t4}$X"]:-0}
        [t5]=${p["{t5}$X"]:-0}
        [mt]=${p["{mt}$X"]:-0}
        [lanes]=${p["{lanes}$X"]:-0}
        [lanes_side]=${p["{lanes_side}$X"]:-0}
        [lt]=${p["{lt}$X"]:-0}
        [shield]=${p["{shield}$X"]:-0}
        [st]=${p["{st}$X"]:-0}
        [bullet_slot]=$_slot
    )
    for i in 1 2 3 4 5 ; do
        SAVE["w${i}_cls"]=${_wcls[$i]}
    done
    unset -n p

    local _tmp="${STRAFE_SAVE_FILE}.tmp.$$"
    local -a _keys=(version plane_cls score hp bombs t2 t3 t4 t5 mt lanes lanes_side lt shield st bullet_slot w1_cls w2_cls w3_cls w4_cls w5_cls)
    local _k
    {
        printf '# strafe save v6\n'
        for _k in "${_keys[@]}" ; do
            printf '%s=%s\n' "$_k" "${SAVE[$_k]}"
        done
    } > "$_tmp" || { rm -f "$_tmp" ; return 1 ; }
    mv -f "$_tmp" "$STRAFE_SAVE_FILE" || { rm -f "$_tmp" ; return 1 ; }
    return 0
}

load_game () {
    [[ -f "$STRAFE_SAVE_FILE" ]] || return 1

    local -A SAVE=()
    local _line _k _v
    while IFS= read -r _line || [[ -n "$_line" ]] ; do
        _line=${_line%$'\r'}
        [[ -z "$_line" ]] && continue
        [[ "$_line" == \#* ]] && continue
        [[ "$_line" == *=* ]] || return 1
        _k=${_line%%=*}
        _v=${_line#*=}
        [[ "$_k" =~ ^[a-z0-9_]+$ ]] || return 1
        SAVE[$_k]=$_v
    done < "$STRAFE_SAVE_FILE"

    local _ver=${SAVE[version]:-}
    [[ "$_ver" == "5" || "$_ver" == "6" ]] || return 1

    local _plane_cls
    if [[ "$_ver" == "5" ]] ; then
        # v5 存档没有机型字段，按默认 Bee 读
        _plane_cls=PlaneBee
    else
        _plane_cls=${SAVE[plane_cls]:-}
        [[ "$_plane_cls" == "Plane" ]] && _plane_cls=PlaneBee
        [[ "$_plane_cls" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
        declare -p "${_plane_cls}Obj" >/dev/null 2>&1 || return 1
        local _valid=0 _c
        for _c in "${PLANE_CLASSES[@]}" ; do
            [[ "$_plane_cls" == "$_c" ]] && _valid=1
        done
        (( _valid )) || return 1
    fi

    local -n _pc=${_plane_cls}Obj
    local -i _pmax=${_pc["{maxhp}$X"]:-20}
    unset -n _pc

    local -a _nums=(score hp bombs t2 t3 t4 t5 mt lanes lanes_side lt shield st bullet_slot)
    for _k in "${_nums[@]}" ; do
        _save_is_uint "${SAVE[$_k]:-}" || return 1
    done
    local -i _hp=${SAVE[hp]} _lanes=${SAVE[lanes]} _side=${SAVE[lanes_side]}
    local -i _shield=${SAVE[shield]} _slot=${SAVE[bullet_slot]}
    (( _hp >= 1 && _hp <= _pmax )) || return 1
    (( _lanes >= 0 && _lanes <= 4 )) || return 1
    (( _side == 0 || _side == 1 )) || return 1
    (( _shield == 0 || _shield == 1 )) || return 1
    (( _slot >= 1 && _slot <= 5 )) || return 1

    local -i i
    local _cls
    for i in 1 2 3 4 5 ; do
        _cls=${SAVE[w${i}_cls]:-}
        [[ "$_cls" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
        declare -p "${_cls}Obj" >/dev/null 2>&1 || return 1
    done

    # 读档从新一波开始；机型不同就替换玩家对象。
    if [[ -z "$PLAYER" || -z "${XO_OBJ_POOL[$PLAYER]+_}" || "${XO_OBJ_POOL[$PLAYER]}" != "$_plane_cls" ]] ; then
        [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] && xo_obj_kill "$PLAYER"
        xo_obj_born "$_plane_cls" || return 1
        PLAYER=$REPLY
    fi
    init_game || return 1

    local -n p=$PLAYER
    for i in 1 2 3 4 5 ; do
        _cls=${SAVE[w${i}_cls]}
        [[ -n "${XO_OBJ_POOL[OBJ_wpn$i]+_}" ]] && xo_obj_kill "OBJ_wpn$i"
        xo_obj_born_named "OBJ_wpn$i" "$_cls" || { unset -n p ; return 1 ; }
        p["{w$i}$X"]=$REPLY
    done

    p["{score}$X"]=${SAVE[score]}
    p["{hp}$X"]=${SAVE[hp]}
    p["{bombs}$X"]=${SAVE[bombs]}
    p["{t2}$X"]=${SAVE[t2]}
    p["{t3}$X"]=${SAVE[t3]}
    p["{t4}$X"]=${SAVE[t4]}
    p["{t5}$X"]=${SAVE[t5]}
    p["{mt}$X"]=${SAVE[mt]}
    p["{lanes}$X"]=${SAVE[lanes]}
    p["{lanes_side}$X"]=${SAVE[lanes_side]}
    p["{lt}$X"]=${SAVE[lt]}
    p["{shield}$X"]=${SAVE[shield]}
    p["{st}$X"]=${SAVE[st]}
    local _wk="{w${_slot}}$X"
    local _bh=${p[$_wk]}
    p["{bullet}$X"]=$_bh
    # 护盾不是只靠 {shield}/{st}：还要恢复护盾 art、4 格宽度和 prev_shield。
    if (( ${SAVE[shield]} )) ; then
        _plane_set_shield "$PLAYER" 1
        p["{st}$X"]=${SAVE[st]}
    else
        _plane_set_shield "$PLAYER" 0
        p["{st}$X"]=${SAVE[st]}
    fi
    p["{shield}$X"]=${SAVE[shield]}
    p["{prev_shield}$X"]=${SAVE[shield]}
    unset -n p
    return 0
}
