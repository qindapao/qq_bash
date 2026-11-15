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
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] || return 1
    local -a _wcls=()
    local -i i _slot=1
    local _h
    for i in 1 2 3 4 5 ; do
        _h=${OBJ_player["{w$i}$X"]}
        if [[ -n "$_h" && -n "${XO_OBJ_POOL[$_h]+_}" ]] ; then
            _wcls[$i]=${XO_OBJ_POOL[$_h]}
        elif (( i == 1 )) ; then
            _wcls[$i]=BulletTypeDefault
        else
            return 1
        fi
    done
    for i in 1 2 3 4 5 ; do
        [[ "${OBJ_player["{bullet}$X"]}" == "${OBJ_player["{w$i}$X"]}" ]] && _slot=$i
    done

    local _pcls=${XO_OBJ_POOL[OBJ_player]}
    [[ "$_pcls" == "Plane" ]] && _pcls=PlaneBee
    local -A SAVE=(
        [version]=6
        [plane_cls]=$_pcls
        [score]=${OBJ_player["{score}$X"]:-0}
        [hp]=${OBJ_player["{hp}$X"]:-0}
        [bombs]=${OBJ_player["{bombs}$X"]:-0}
        [t2]=${OBJ_player["{t2}$X"]:-0}
        [t3]=${OBJ_player["{t3}$X"]:-0}
        [t4]=${OBJ_player["{t4}$X"]:-0}
        [t5]=${OBJ_player["{t5}$X"]:-0}
        [mt]=${OBJ_player["{mt}$X"]:-0}
        [lanes]=${OBJ_player["{lanes}$X"]:-0}
        [lanes_side]=${OBJ_player["{lanes_side}$X"]:-0}
        [lt]=${OBJ_player["{lt}$X"]:-0}
        [shield]=${OBJ_player["{shield}$X"]:-0}
        [st]=${OBJ_player["{st}$X"]:-0}
        [bullet_slot]=$_slot
    )
    for i in 1 2 3 4 5 ; do
        SAVE["w${i}_cls"]=${_wcls[$i]}
    done
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
    if [[ -z "${XO_OBJ_POOL[OBJ_player]+_}" || "${XO_OBJ_POOL[OBJ_player]}" != "$_plane_cls" ]] ; then
        [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && xo_obj_kill OBJ_player
        xo_obj_born_named OBJ_player "$_plane_cls" || return 1
    fi
    init_game || return 1
    for i in 1 2 3 4 5 ; do
        _cls=${SAVE[w${i}_cls]}
        [[ -n "${XO_OBJ_POOL[OBJ_wpn$i]+_}" ]] && xo_obj_kill "OBJ_wpn$i"
        xo_obj_born_named "OBJ_wpn$i" "$_cls" || return 1
        OBJ_player["{w$i}$X"]=$REPLY
    done

    OBJ_player["{score}$X"]=${SAVE[score]}
    OBJ_player["{hp}$X"]=${SAVE[hp]}
    OBJ_player["{bombs}$X"]=${SAVE[bombs]}
    OBJ_player["{t2}$X"]=${SAVE[t2]}
    OBJ_player["{t3}$X"]=${SAVE[t3]}
    OBJ_player["{t4}$X"]=${SAVE[t4]}
    OBJ_player["{t5}$X"]=${SAVE[t5]}
    OBJ_player["{mt}$X"]=${SAVE[mt]}
    OBJ_player["{lanes}$X"]=${SAVE[lanes]}
    OBJ_player["{lanes_side}$X"]=${SAVE[lanes_side]}
    OBJ_player["{lt}$X"]=${SAVE[lt]}
    OBJ_player["{shield}$X"]=${SAVE[shield]}
    OBJ_player["{st}$X"]=${SAVE[st]}
    local _wk="{w${_slot}}$X"
    local _bh=${OBJ_player[$_wk]}
    OBJ_player["{bullet}$X"]=$_bh
    # 护盾不是只靠 {shield}/{st}：还要恢复护盾 art、4 格宽度和 prev_shield。
    if (( ${SAVE[shield]} )) ; then
        _plane_set_shield "OBJ_player" 1
        OBJ_player["{st}$X"]=${SAVE[st]}
    else
        _plane_set_shield "OBJ_player" 0
        OBJ_player["{st}$X"]=${SAVE[st]}
    fi
    OBJ_player["{shield}$X"]=${SAVE[shield]}
    OBJ_player["{prev_shield}$X"]=${SAVE[shield]}
    return 0
}
