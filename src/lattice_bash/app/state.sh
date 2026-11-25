# lattice/app/state.sh — application state and small helpers
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[state]++ )) && return 0

LATTICE_NAME='lattice'
LATTICE_VERSION='0.1.0'

LATTICE_HOME=${LATTICE_HOME:-$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)}
LATTICE_LIB_HOME=${LATTICE_LIB_HOME:-$(cd -- "$LATTICE_HOME/../bashlib" && pwd)}
LATTICE_ROOT=${LATTICE_ROOT:-$(pwd)}
LATTICE_CONFIG=${LATTICE_CONFIG:-"$LATTICE_HOME/config/commands.conf"}
LATTICE_STATE_DIR=${LATTICE_STATE_DIR:-"${HOME}/.lattice"}
LATTICE_HISTORY_FILE=${LATTICE_HISTORY_FILE:-"$LATTICE_STATE_DIR/history.tsv"}
LATTICE_ORDER_FILE=${LATTICE_ORDER_FILE:-"$LATTICE_STATE_DIR/command-order.tsv"}
LATTICE_EXECUTOR_RC=${LATTICE_EXECUTOR_RC:-"$LATTICE_HOME/executor/rc.sh"}
LATTICE_OPEN_CMD=${LATTICE_OPEN_CMD:-'/d/programes/vim/vim91/gvim.exe --remote-silent'}
LATTICE_CONTEXT_FILE=${LATTICE_CONTEXT_FILE:-"${TMPDIR:-/tmp}/lattice-context-${LATTICE_TMUX_SESSION:-lattice}"}

LATTICE_DIR=$LATTICE_ROOT
LATTICE_SELECTED=0
LATTICE_MODE='tree'
LATTICE_STATUS=''
LATTICE_STATUS_KIND='info'
LATTICE_RECENT_FOCUS=0
LATTICE_OWN_SESSION=${LATTICE_OWN_SESSION:-0}
LATTICE_QUIT=0

LATTICE_COLS=${COLUMNS:-80}
LATTICE_ROWS=${LINES:-24}

# ANSI sequences
LATTICE_ESC=$'\033'
LATTICE_C_RESET="${LATTICE_ESC}[0m"
LATTICE_C_DIM="${LATTICE_ESC}[2m"
LATTICE_C_REV="${LATTICE_ESC}[7m"
LATTICE_C_BOLD="${LATTICE_ESC}[1m"
LATTICE_C_CYAN="${LATTICE_ESC}[36m"
LATTICE_C_YELLOW="${LATTICE_ESC}[33m"
LATTICE_C_GREEN="${LATTICE_ESC}[32m"
LATTICE_C_RED="${LATTICE_ESC}[31m"

lattice_status ()
{
    LATTICE_STATUS=$1
    LATTICE_STATUS_KIND=${2:-info}
}

lattice_term_size ()
{
    local size
    if size=$(stty size 2>/dev/null) && [[ -n "$size" ]] ; then
        LATTICE_ROWS=${size%% *}
        LATTICE_COLS=${size##* }
    fi
    (( LATTICE_COLS < 40 )) && LATTICE_COLS=40
    (( LATTICE_ROWS < 10 )) && LATTICE_ROWS=10
}

lattice_join_path ()
{
    local base=$1 name=$2
    if [[ "$name" == '..' ]] ; then
        if [[ "$base" == '/' ]] ; then
            REPLY='/'
        else
            REPLY=${base%/*}
            [[ -z "$REPLY" ]] && REPLY='/'
        fi
        return 0
    fi
    if [[ "$base" == '/' ]] ; then
        REPLY="/$name"
    else
        REPLY="$base/$name"
    fi
}

lattice_selected_path ()
{
    local name=${LATTICE_ENTRIES[LATTICE_SELECTED]:-}
    if [[ -z "$name" ]] ; then
        REPLY=$LATTICE_DIR
        return 0
    fi
    lattice_join_path "$LATTICE_DIR" "$name"
}

lattice_clip ()
{
    local s=$1 max=$2
    if (( ${#s} > max )) ; then
        REPLY=${s:0:max}
    else
        REPLY=$s
    fi
}

lattice_reload_all ()
{
    lattice_tree_load || return $?
    return 0
}
