# render/hud.sh — HUD 状态栏（拼接 FRAME_BUF）
[[ -n "${_STRAFE_HUD_SH:-}" ]] && return 0
_STRAFE_HUD_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"

draw_hud_line1 () {
    local bt=${OBJ_player["{bullet}$X"]}
    local weapon='.'
    if [[ -n "$bt" && -n "${XO_OBJ_POOL[$bt]+_}" ]] ; then
        local -n _bt=$bt
        weapon=${_bt["{u}$X"]}
    fi
    local _s
    # 被 Boss 减速时在主状态行上直接标出来（玩家最常看的一行），比藏在 BONUS 行尾显眼
    local _slow=$(( ${OBJ_player["{slow}$X"]:-0} / FPS ))
    local _slowseg=''
    (( _slow > 0 )) && printf -v _slowseg '  SLOW:%d' "$_slow"
    # 临时桩：人才市场存量（MKT）。RES_MARKET 的键数就是全市场对象总数。
    # 发布前连同格式串里的 MKT 段和这一整段一起删掉（TODO.txt 有记录）。
    local _mkt=${#RES_MARKET[@]} _mktseg='' _c _ab _n
    for _c in "${!RES_COUNT[@]}" ; do
        _n=${RES_COUNT[$_c]}
        (( _n > 0 )) || continue
        case "$_c" in
            Bullet)       _ab=B  ;;
            EnemyBullet)  _ab=EB ;;
            BossBullet)   _ab=BB ;;
            Missile)      _ab=M  ;;
            EnemyMissile) _ab=EM ;;
            *)            _ab=${_c:0:2} ;;
        esac
        _mktseg+="$_ab$_n/"
    done
    _mktseg=${_mktseg%/}
    local _mktf="  MKT:${_mkt}"
    [[ -n "$_mktseg" ]] && _mktf="  MKT:${_mkt}(${_mktseg})"
    printf -v _s 'HP:%d/%d%s  SCORE:%d  STAGE:%d  W:%s  BOMB:%d/5  E:%d/%d  OBJ:%d%s' \
        "${OBJ_player["{hp}$X"]:-0}" "${OBJ_player["{maxhp}$X"]:-20}" "$_slowseg" \
        "${OBJ_player["{score}$X"]:-0}" "$(( G_BOSS_KILLS + 1 ))" "$weapon" "${OBJ_player["{bombs}$X"]:-0}" \
        "${#ENEMIES[@]}" "$ENEMY_LIMIT" "${#XO_OBJ_POOL[@]}" "$_mktf"
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    local _t
    printf -v _t '\033[2;2H%*s\033[2;2H%s\033[2;%dH%s' "$_maxw" '' "$_s" "$SCREEN_W" "$FRAME_V"
    FRAME_BUF+="$_t"
}

draw_hud_line2 () {
    # 只显示本局实际抽到的 4 种掉落武器（tier 2..5），默认子弹不占位。
    local _s='BULLET'
    local _i _w
    if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        for _i in 2 3 4 5 ; do
            _w=${OBJ_player["{w$_i}$X"]}
            [[ -n "$_w" && -n "${XO_OBJ_POOL[$_w]+_}" ]] || continue
            local -n _wobj=$_w
            local _wu=${_wobj["{u}$X"]} _wd=${_wobj["{damage}$X"]}
            _s+=" ${_wu}:${_wd}"
        done
    fi
    _s+='  DROP H:+3 b:BOMB m:MISSILE L:LANE S:SHIELD W:NET'
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    local _t
    printf -v _t '\033[3;2H%*s\033[3;2H%s\033[3;%dH%s' "$_maxw" '' "$_s" "$SCREEN_W" "$FRAME_V"
    FRAME_BUF+="$_t"
}

draw_bonus_hud () {
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] || return 0
    local _s='BONUS'
    local _i _w _wu _tv _part
    # 4 种武器按 tier 2..5 动态取实际字符和倒计时，
    # 不能像旧版那样写死 * @ $ |，否则武器和数字会错位。
    for _i in 2 3 4 5 ; do
        _w=${OBJ_player["{w$_i}$X"]}
        _wu='?'
        if [[ -n "$_w" && -n "${XO_OBJ_POOL[$_w]+_}" ]] ; then
            local -n _wobj=$_w
            _wu=${_wobj["{u}$X"]}
        fi
        _tv=$(( ${OBJ_player["{t$_i}$X"]:-0} / FPS ))
        printf -v _part '  %s:%3d' "$_wu" "$_tv"
        _s+=$_part
    done
    local mt=$(( ${OBJ_player["{mt}$X"]:-0} / FPS ))
    local lt=$(( ${OBJ_player["{lt}$X"]:-0} / FPS ))
    local st=$(( ${OBJ_player["{st}$X"]:-0} / FPS ))
    local lcount=$(( ${OBJ_player["{lanes}$X"]:-0} + 1 ))
    printf -v _part '  m:%3d  L:%3d(%d)  S:%3d' "$mt" "$lt" "$lcount" "$st"
    _s+=$_part
    # 被 Boss 减速时给个倒计时提示（简单动画：数字每秒跳动）
    local slow=$(( ${OBJ_player["{slow}$X"]:-0} / FPS ))
    if (( slow > 0 )) ; then
        printf -v _part '  SLOW:%3d' "$slow"
        _s+=$_part
    fi
    local _maxw=$(( SCREEN_W - 2 ))
    _s="${_s:0:_maxw}"
    local _t
    printf -v _t '\033[4;2H%*s\033[4;2H%s\033[4;%dH%s' "$_maxw" '' "$_s" "$SCREEN_W" "$FRAME_V"
    FRAME_BUF+="$_t"
}
