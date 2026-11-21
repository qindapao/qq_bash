# game/cli.sh — 命令行参数解析（-h/--help、-t/--theme）
#
# 必须在 source main.sh 之前执行：--theme 写进 STRAFE_THEME 后，
# config/color.sh 才能在加载时读到它（它在 source 时就把调色板定下来了）。
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[cli]++ )) && return 0

# 帮助内容 = 开始页的全部信息（操作/掉落/武器/作者）+ 参数说明。
cli_help () {
    # cli.sh 先于 main.sh 加载，此时 const.sh 还没跑：单独取版本号文件
    . "$STRAFE_PROJ_DIR/config/version.sh"
    printf 'STRAFE_BASH %s — a pure Bash terminal bullet-hell\n' "$STRAFE_VERSION"
    cat <<'EOF'

Usage:
  strafe_bash.sh                  play
  strafe_bash.sh -t light         play with the light-background palette
  strafe_bash.sh --theme dark     play with the neon palette
  strafe_bash.sh -d               validate class/Mixin registration at startup
  strafe_bash.sh -h | --help      show this help

Options:
  -t, --theme light|dark|auto     terminal theme (default: auto)
  -d, --debug                     run xo class/Mixin registration validation
  -h, --help                      show this help

  light   darker colours for light-background terminals
  dark    neon colours for dark-background terminals
  auto    follow COLORFGBG when the terminal exports it, otherwise dark

Environment:
  STRAFE_THEME=light|dark|auto    same as -t/--theme
  STRAFE_DEBUG=1|0                same as -d/--debug
  STRAFE_INPUT_POLL=1|0           force the probe-based input loop on/off
                                  default: on under MSYS/CYGWIN, off elsewhere
                                  (Windows read -t has a 15.9 ms granularity,
                                   polling is what keeps 30 fps there)
  STRAFE_ERRLOG=<path>            where runtime errors are written
                                  default: /tmp/strafe_bash.err

Controls:
  1-4                    choose a plane on the title screen
  W A S D  /  H J K L    move
  Y U      /  B N        move diagonally (up-left, up-right, down-left, down-right)
  SPACE / right click    use a bomb
  P                      pause / resume
  Q                      quit
  S                      save while paused (hidden .strafe_save)
  L                      load while paused, or from the title screen
  mouse                  move the plane; firing stays automatic

Drops:
  H +3 HP    b bomb    m homing missile    L lane    S shield    W net
  W scans upward: clears enemy bullets/missiles on its row, damages enemies
  touching a falling word collects it for score

Weapons:
  2 |    3 #    4 @    5 $

Author:
  qindapao  ·  northisland2017@gmail.com
  https://github.com/qindapao/qq_bash
  https://github.com/qindapao  ·  qindapao.com
EOF
}

# 只接受 light/dark/auto：写错主题名时宁可报错，也不要静默落回 dark 调色板。
_cli_set_theme () {
    case "$1" in
        light|dark|auto) export STRAFE_THEME=$1 ; return 0 ;;
    esac
    printf 'invalid theme: %s (expected light, dark or auto)\n' "$1" >&2
    return 2
}

# 解析失败返回 2，由入口决定怎么退出；-h 直接打印后退出 0。
cli_parse () {
    while (( $# )) ; do
        case "$1" in
            -h|--help)
                cli_help
                exit 0
                ;;
            -t|--theme)
                (( $# >= 2 )) || { printf 'missing value for %s (try -h)\n' "$1" >&2 ; return 2 ; }
                _cli_set_theme "$2" || return 2
                shift
                ;;
            -d|--debug)
                export STRAFE_DEBUG=1
                ;;
            --theme=*)
                _cli_set_theme "${1#*=}" || return 2
                ;;
            *)
                printf 'unknown option: %s (try -h)\n' "$1" >&2
                return 2
                ;;
        esac
        shift
    done
    return 0
}
