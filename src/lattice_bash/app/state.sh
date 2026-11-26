# lattice/app/state.sh — application state and small helpers
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[state]++ )) && return 0

LATTICE_NAME='lattice'
LATTICE_VERSION='1.0.0.0'

LATTICE_HOME=${LATTICE_HOME:-$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)}

# Machine identity is derived from the operating system on every run. It must
# NOT be cached in LATTICE_STATE_DIR: that directory may live on a USB stick
# shared by several machines, and a cached id would then be reused everywhere.
lattice_machine_id ()
{
    local id=${LATTICE_MACHINE_ID:-}

    if [[ -z "$id" && -r /etc/machine-id ]] ; then
        IFS= read -r id < /etc/machine-id || id=''
    fi
    if [[ -z "$id" ]] && command -v powershell.exe >/dev/null 2>&1 ; then
        id=$(powershell.exe -NoProfile -Command \
            '(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography").MachineGuid' \
            2>/dev/null | tr -d '\r')
    fi
    [[ -n "$id" ]] || id=${HOSTNAME:-unknown}
    id=${id//[^A-Za-z0-9_.-]/_}
    printf '%s' "$id"
}

# Explicit environment wins over both config layers. Snapshot values before
# assigning any defaults or env-file paths.
declare -gA LATTICE_EXPLICIT_ENV=()
_lattice_env_names=(
    LATTICE_MACHINE_ID LATTICE_ROOT LATTICE_CONFIG LATTICE_STATE_DIR
    LATTICE_ENV_CONF LATTICE_ENV_DIR LATTICE_HISTORY_FILE LATTICE_ORDER_FILE
    LATTICE_EXECUTOR_RC LATTICE_OPEN_CMD LATTICE_EDITOR
    LATTICE_TMUX_BIN LATTICE_TMUX_SESSION LATTICE_RECENT_LIMIT
    LATTICE_HISTORY_LIMIT
)
for _lattice_env_name in "${_lattice_env_names[@]}" ; do
    [[ -n "${!_lattice_env_name+x}" ]] && \
        LATTICE_EXPLICIT_ENV[$_lattice_env_name]=${!_lattice_env_name}
done
unset _lattice_env_name _lattice_env_names

LATTICE_MACHINE_ID=${LATTICE_MACHINE_ID:-$(lattice_machine_id)}
LATTICE_MACHINE_ID=${LATTICE_MACHINE_ID//[^A-Za-z0-9_.-]/_}
LATTICE_STATE_DIR=${LATTICE_STATE_DIR:-"${HOME}/.lattice"}
LATTICE_ENV_CONF=${LATTICE_ENV_CONF:-"$LATTICE_STATE_DIR/env.conf"}
LATTICE_ENV_DIR=${LATTICE_ENV_DIR:-"$LATTICE_STATE_DIR/env.d"}

lattice_env_source ()
{
    local file=$1
    [[ -f "$file" ]] || return 0
    # shellcheck source=/dev/null
    . "$file" || printf 'lattice: failed to load %s\n' "$file" >&2
}

# Common user defaults, then machine-specific overrides.
lattice_env_source "$LATTICE_ENV_CONF"
lattice_env_source "$LATTICE_ENV_DIR/$LATTICE_MACHINE_ID.conf"

# Restore explicitly exported values over both files.
for _lattice_env_name in "${!LATTICE_EXPLICIT_ENV[@]}" ; do
    printf -v "$_lattice_env_name" '%s' "${LATTICE_EXPLICIT_ENV[$_lattice_env_name]}"
done
unset _lattice_env_name

LATTICE_ROOT=${LATTICE_ROOT:-$(pwd)}
LATTICE_CONFIG=${LATTICE_CONFIG:-"$LATTICE_HOME/config/commands.conf"}
LATTICE_HISTORY_FILE=${LATTICE_HISTORY_FILE:-"$LATTICE_STATE_DIR/history.tsv"}
LATTICE_ORDER_FILE=${LATTICE_ORDER_FILE:-"$LATTICE_STATE_DIR/command-order.tsv"}
LATTICE_USER_COMMANDS_FILE=${LATTICE_USER_COMMANDS_FILE:-"$LATTICE_STATE_DIR/commands.user.conf"}
LATTICE_DISABLED_FILE=${LATTICE_DISABLED_FILE:-"$LATTICE_STATE_DIR/commands.disabled"}
LATTICE_EXECUTOR_RC=${LATTICE_EXECUTOR_RC:-"$LATTICE_HOME/executor/rc.sh"}
LATTICE_EDITOR=${LATTICE_EDITOR:-gvim}
LATTICE_OPEN_CMD=${LATTICE_OPEN_CMD:-"$LATTICE_EDITOR --remote-silent"}
LATTICE_CONTEXT_FILE=${LATTICE_CONTEXT_FILE:-"${TMPDIR:-/tmp}/lattice-context-${LATTICE_TMUX_SESSION:-lattice}"}

LATTICE_DIR=$LATTICE_ROOT
LATTICE_SELECTED=0
LATTICE_MODE='tree'
LATTICE_STATUS=''
LATTICE_STATUS_KIND='info'
LATTICE_RECENT_FOCUS=0
LATTICE_OWN_SESSION=${LATTICE_OWN_SESSION:-0}
LATTICE_QUIT=0
LATTICE_RESIZING=0
LATTICE_TREE_OFFSET=0
LATTICE_TREE_BODY=1
LATTICE_MOUSE_LAST_TS=0
LATTICE_MOUSE_LAST_ROW=-1
LATTICE_MOUSE_LAST_MODE=''
LATTICE_SNAPSHOT_TEXT=''
LATTICE_SNAPSHOT_NAME=''
LATTICE_SNAPSHOT_OPEN=0
LATTICE_SNAPSHOT_SCROLL=0
LATTICE_SNAPSHOT_WRAP=()
LATTICE_SNAPSHOT_INNER=0
LATTICE_SNAPSHOT_CAP=1
LATTICE_SNAPSHOT_TOTAL=0
LATTICE_SEARCH_STATUS_ACTIVE=0
LATTICE_SEARCH_STATUS_RIGHT=''
LATTICE_SEARCH_STATUS_RIGHT_LENGTH=''

LATTICE_FORM_OPEN=0
LATTICE_FORM_KIND=''
LATTICE_FORM_TITLE=''
LATTICE_FORM_LABELS=()
LATTICE_FORM_VALUES=()
LATTICE_FORM_DEFAULTS=()
LATTICE_FORM_CURSORS=()
LATTICE_FORM_INDEX=0
LATTICE_FORM_CMD_INDEX=-1
LATTICE_FORM_DELETE_NAME=''

declare -gA LATTICE_CMD_ROW_CACHE=()

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
    local size actual_cols old_cols=$LATTICE_COLS
    actual_cols=$LATTICE_COLS
    if size=$(stty size 2>/dev/null) && [[ -n "$size" ]] ; then
        LATTICE_ROWS=${size%% *}
        actual_cols=${size##* }
        LATTICE_COLS=$actual_cols
    fi
    (( LATTICE_COLS < 24 )) && LATTICE_COLS=24
    (( LATTICE_ROWS < 10 )) && LATTICE_ROWS=10
    if (( LATTICE_COLS != old_cols )) ; then
        LATTICE_CMD_ROW_CACHE=()
    fi

    # Keep a mouse-dragged border from squeezing the TUI into an unusable
    # width. The pane can reach 1 column before WINCH arrives; ask tmux to put
    # it back to the minimum, guarded against recursive WINCH handling.
    if (( actual_cols < 24 )) && [[ -n "${TMUX_PANE:-}" && -z "${LATTICE_RESIZING:-}" ]] &&
       declare -F lattice_tmux_quick >/dev/null 2>&1 ; then
        LATTICE_RESIZING=1
        lattice_tmux_quick resize-pane -t "$TMUX_PANE" -x 24 2>/dev/null || true
        LATTICE_RESIZING=0
    fi
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
