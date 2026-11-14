# classes/enemies/skull_king.sh — SkullKing（骷髅王）
# 500 HP；三颗跟踪骷髅头；O/X 高频弹幕；四阶段 + 无头状态。
[[ -n "${_STRAFE_SKULL_KING_SH:-}" ]] && return 0
_STRAFE_SKULL_KING_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_base.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/boss_bullet.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/skull_bullet.sh"

IFS= read -r -d '' SKULL_ART_0 <<'EOF' || true
             .-.            
            (o.o)           
             |=|            
            __|__           
   .-.    //.=|=.\\    .-.  
  (o.o)__// .=|=. \\__(o.o) 
   |=|___/  .=|=.  \___|=|  
            (_=_)           
           (:| |:           
            || ||           
            () ()           
            || ||           
            || ||           
           ==' '==          
EOF

IFS= read -r -d '' SKULL_ART_1 <<'EOF' || true
             .-.            
            (o.o)           
             |=|            
            __|__           
   .-.    //.=|=.\\    .-.  
  (o.o)__// .=|=. \\__(o.o) 
   |=|___/  .=|=.  \___|=|  
            (_=_)           
               |:           
               ||           
               ()           
               ||           
               ||           
               '==          
EOF

IFS= read -r -d '' SKULL_ART_2 <<'EOF' || true
             .-.            
            (o.o)           
             |=|            
            __|__           
   .-.    //.=|=.\\    .-.  
  (o.o)__// .=|=. \\__(o.o) 
   |=|___/  .=|=.  \___|=|  
            (_=_)           
                            
                            
                            
                            
                            
                            
EOF

IFS= read -r -d '' SKULL_ART_3 <<'EOF' || true
             .-.            
            (o.o)           
             |=|            
            __|__           
   .-.    //  |  \\    .-.  
  (o.o)__//   |   \\__(o.o) 
   |=|___/    |    \___|=|  
                            
                            
                            
                            
                            
                            
                            
EOF

IFS= read -r -d '' SKULL_ART_HEADLESS <<'EOF' || true



           __|__   
         //.=|=.\\ 
        // .=|=. \\
        /  .=|=.  \
           (_=_)   
          (:| |:   
           || ||   
           () ()   
           || ||   
           || ||   
          ==' '==  
EOF

readonly SkullKingStaticTemplate='
    SkullKingObj ->
        {CLS} => SkullKing
        {SUP} => BossBase
        {MIX} => 
        {name} => THE SKULL KING
        {w} => 29
        {h} => 14
        {hp} => 500
        {maxhp} => 500
        {score} => 20000
        {symbol} => K
        {pcut1} => 75
        {pcut2} => 50
        {pcut3} => 25
        {death_style} => 0
        {headless_art} => 
        {headless} => 0
        {skull_cd} => 0
        {head_cd} => 0
        {shot_cd} => 0
    '

SkullKing_born () {
    _boss_set_arts "$1" "$SKULL_ART_0" "$SKULL_ART_1" "$SKULL_ART_2" "$SKULL_ART_3"
    BossBase_born "$1"
    local -n _self=$1
    _self["{headless_art}$X"]=$SKULL_ART_HEADLESS
    _self["{headless}$X"]=0
    _self["{skull_cd}$X"]=70
    _self["{head_cd}$X"]=0
    _self["{shot_cd}$X"]=8
    unset -n _self
}

_skull_king_fire_heads () {
    local -n _bs=$1
    if (( ${#SKULLS[@]} + 3 > SKULL_LIMIT )) ; then
        unset -n _bs
        return 1
    fi
    local -i x=${_bs["{x}$X"]} y=${_bs["{y}$X"]} w=${_bs["{w}$X"]}
    local -i sy=$(( y + 4 ))
    local -i sx1=$(( x + 2 ))
    local -i sx2=$(( x + w / 2 - 2 ))
    local -i sx3=$(( x + w - 7 ))
    unset -n _bs
    local _sx
    for _sx in "$sx1" "$sx2" "$sx3" ; do
        xo_obj_born SkullBullet "$_sx" "$sy" 240 5 3 "$C_RED"
        SKULLS+=("$REPLY")
    done
    return 0
}

SkullKing_move () {
    _boss_update_phase "$1"
    local -n self=$1
    local -i phase=${self["{phase}$X"]}
    local -i x=${self["{x}$X"]} y=${self["{y}$X"]} w=${self["{w}$X"]} h=${self["{h}$X"]}

    # 巨型 Boss 只在顶部小范围移动，把下半屏留给玩家。
    _boss_move_target "$1" 12 "$(( SCREEN_H - 4 - h ))" 4 30 18 4 0

    if (( ${#ENEMY_BULLETS[@]} + 2 <= BOSS_BULLET_LIMIT )) ; then
        local -i sc=$(( ${self["{shot_cd}$X"]:-0} - 1 ))
        if (( sc <= 0 )) ; then
            self["{shot_cd}$X"]=6
            x=$((${self["{x}$X"]}))
            y=$((${self["{y}$X"]}))
            local _by=$(( y + h ))
            local _cx=$(( x + w / 2 ))
            xo_obj_born BossBullet "$((_cx - 3))" "$_by" 0 1 'O' 1 2 "$C_YELLOW"
            ENEMY_BULLETS+=("$REPLY")
            xo_obj_born BossBullet "$((_cx + 3))" "$_by" 0 1 'X' 1 2 "$C_ORANGE"
            ENEMY_BULLETS+=("$REPLY")
        else
            self["{shot_cd}$X"]=$sc
        fi
    fi

    if (( ${self["{headless}$X"]:-0} )) ; then
        local -i hc=$(( ${self["{head_cd}$X"]:-0} - 1 ))
        if (( hc <= 0 )) ; then
            self["{headless}$X"]=0
            self["{head_cd}$X"]=0
            self["{skull_cd}$X"]=70
        else
            self["{head_cd}$X"]=$hc
        fi
    else
        local -i kc=$(( ${self["{skull_cd}$X"]:-0} - 1 ))
        if (( kc <= 0 )) ; then
            if _skull_king_fire_heads "$1" ; then
                self["{headless}$X"]=1
                self["{head_cd}$X"]=40
                self["{skull_cd}$X"]=70
            else
                # 达到骷髅头上限时保留头部，稍后再尝试
                self["{skull_cd}$X"]=12
            fi
        else
            self["{skull_cd}$X"]=$kc
        fi
    fi

    if (( ${self["{headless}$X"]:-0} )) ; then
        self["{art}$X"]=${self["{headless_art}$X"]}
    else
        self["{art}$X"]=${self["{art$phase}$X"]}
    fi
    unset -n self
    return 0
}
