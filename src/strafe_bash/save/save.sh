# save/save.sh — 存档 / 读档
[[ -n "${_STRAFE_SAVE_SH:-}" ]] && return 0
_STRAFE_SAVE_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

save_game () {
    local -A SAVE=()
    x_init "$X_TYPE_OBJ" ; SAVE=($REPLY)
    x_insert SAVE "{meta}$X{version}$X" 1
    x_insert SAVE "{meta}$X{player}$X" "$PLAYER"
    x_insert SAVE "{meta}$X{obj_seq}$X" "$XO_OBJ_SEQ"

    local obj k
    for obj in "${!XO_OBJ_POOL[@]}" ; do
        local -n _o=$obj
        for k in "${!_o[@]}" ; do
            [[ "$k" == '{'*"$X" ]] || continue
            x_insert SAVE "{objs}$X{$obj}$X$k" "${_o[$k]}" || continue
        done
        unset -n _o
    done

    local i
    for i in "${!BULLETS[@]}" ; do
        x_insert SAVE "{lists}$X{bullets}$X[$i]$X" "${BULLETS[$i]}"
    done
    for i in "${!ENEMIES[@]}" ; do
        x_insert SAVE "{lists}$X{enemies}$X[$i]$X" "${ENEMIES[$i]}"
    done
    for i in "${!DROPS[@]}" ; do
        x_insert SAVE "{lists}$X{drops}$X[$i]$X" "${DROPS[$i]}"
    done
    for i in "${!ENEMY_BULLETS[@]}" ; do
        x_insert SAVE "{lists}$X{ebullets}$X[$i]$X" "${ENEMY_BULLETS[$i]}"
    done
    for i in "${!MISSILES[@]}" ; do
        x_insert SAVE "{lists}$X{missiles}$X[$i]$X" "${MISSILES[$i]}"
    done

    x_dump SAVE '' 4 6 > "$STRAFE_SAVE_FILE"
    return 0
}

load_game () {
    [[ -f "$STRAFE_SAVE_FILE" ]] || return 1
    local dump
    dump=$(<"$STRAFE_SAVE_FILE")
    [[ -n "$dump" ]] || return 1

    x_rebuild_from_dump "$dump" || return 1
    local -A SAVE=($REPLY)

    [[ "${SAVE[{meta}$X{version}$X]:-}" == "1" ]] || return 1

    local obj
    for obj in "${!XO_OBJ_POOL[@]}" ; do
        unset -v "$obj"
    done
    XO_OBJ_POOL=()
    BULLETS=() ; ENEMIES=() ; DROPS=() ; ENEMY_BULLETS=() ; MISSILES=()

    local k rest obj_tok o after field_tok v
    local -A declared=()
    for k in "${!SAVE[@]}" ; do
        [[ "$k" == "{objs}$X"* ]] || continue
        rest=${k#"{objs}$X"}
        obj_tok=${rest%%"$X"*}
        o=${obj_tok:1:-1}
        after=${rest#*"$X"}
        [[ -z "$after" ]] && continue
        field_tok=${after%%"$X"*}
        [[ "$after" != "${field_tok}$X" ]] && continue
        v=${SAVE[$k]}
        [[ "$v" == "$X_VALUE_NULL" ]] && continue

        if [[ -z "${declared[$o]+_}" ]] ; then
            declare -gA "$o=()"
            declared[$o]=1
        fi
        local -n _t=$o
        _t["${field_tok}$X"]=$v
        unset -n _t
    done

    for o in "${!declared[@]}" ; do
        local -n _t=$o
        XO_OBJ_POOL[$o]=${_t["{CLS}$X"]}
        unset -n _t
    done

    PLAYER=${SAVE[{meta}$X{player}$X]}
    XO_OBJ_SEQ=${SAVE[{meta}$X{obj_seq}$X]}

    local list_tok list idx_tok idx
    for k in "${!SAVE[@]}" ; do
        [[ "$k" == "{lists}$X"* ]] || continue
        rest=${k#"{lists}$X"}
        list_tok=${rest%%"$X"*}
        list=${list_tok:1:-1}
        after=${rest#*"$X"}
        [[ -z "$after" ]] && continue
        idx_tok=${after%%"$X"*}
        [[ "$after" != "${idx_tok}$X" ]] && continue
        idx=${idx_tok:1:-1}
        v=${SAVE[$k]}
        case "$list" in
            bullets)   BULLETS[$idx]=$v ;;
            enemies)   ENEMIES[$idx]=$v ;;
            drops)     DROPS[$idx]=$v ;;
            ebullets)  ENEMY_BULLETS[$idx]=$v ;;
            missiles)  MISSILES[$idx]=$v ;;
        esac
    done

    return 0
}
