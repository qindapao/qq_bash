#!/usr/bin/env bash
# lattice.sh — entry point for the Lattice TUI workbench.
# Runs a two-pane tmux session: TUI on the left, executor shell on the right.

LATTICE_SELF=${BASH_SOURCE[0]}
if [[ "$LATTICE_SELF" != /* ]] ; then
    LATTICE_SELF=$(cd -- "$(dirname -- "$LATTICE_SELF")" && pwd)/${LATTICE_SELF##*/}
fi
LATTICE_HOME=${LATTICE_HOME:-$(cd -- "${LATTICE_SELF%/*}" && pwd)}
LATTICE_LIB_HOME=${LATTICE_LIB_HOME:-$(cd -- "$LATTICE_HOME/../bashlib" && pwd)}

# Reuse str_display_width for CJK alignment. str.sh prints its grammar probe;
# suppress that chatter in the TUI launcher.
# shellcheck source=/dev/null
. "$LATTICE_LIB_HOME/str.sh" >/dev/null || {
    printf 'lattice: failed to load str.sh\n' >&2
    exit 1
}

# shellcheck source=/dev/null
. "$LATTICE_HOME/app/state.sh"
# shellcheck source=/dev/null
. "$LATTICE_HOME/fs/tree.sh"
# shellcheck source=/dev/null
. "$LATTICE_HOME/cmd/registry.sh"
# shellcheck source=/dev/null
. "$LATTICE_HOME/cmd/history.sh"
# shellcheck source=/dev/null
. "$LATTICE_HOME/cmd/tmux.sh"
# shellcheck source=/dev/null
. "$LATTICE_HOME/cmd/executor.sh"
# shellcheck source=/dev/null
. "$LATTICE_HOME/ui/render.sh"
# shellcheck source=/dev/null
. "$LATTICE_HOME/ui/event.sh"

lattice_usage ()
{
    cat <<'EOF'
Usage: lattice.sh [options]

  --root DIR          start file browser at DIR
  --session NAME      tmux session name (default: lattice)
  --tui               run the TUI in the current pane
  --owned             internal: close tmux session on quit
  --no-tmux           run TUI without looking for a tmux executor
  --list-commands     print configured commands
  --print-command NAME print the expanded command for NAME
  --machine-id       print machine id and env config paths
  --version, -v      print version
  --help              this help
EOF
}

lattice_cleanup ()
{
    lattice_status_left_end 2>/dev/null || true
    lattice_search_status_end 2>/dev/null || true
    if (( ${LATTICE_SCREEN_ACTIVE:-0} )) ; then
        LATTICE_SCREEN_ACTIVE=0
        lattice_screen_done
    fi
}

lattice_signal_exit ()
{
    LATTICE_QUIT=1
    lattice_cleanup
    exit 0
}

lattice_app_main ()
{
    LATTICE_SCREEN_ACTIVE=0
    LATTICE_NEED_RENDER=0
    [[ -n "${TMUX:-}" ]] && lattice_tmux_apply_tui_width
    [[ -n "${TMUX:-}" ]] && lattice_tmux_mouse_on
    [[ -n "${TMUX:-}" ]] && lattice_status_left_start
    trap lattice_cleanup EXIT
    trap lattice_signal_exit INT TERM HUP
    trap 'LATTICE_NEED_RENDER=1; lattice_term_size' WINCH

    lattice_registry_load || exit 1
    lattice_history_init || exit 1
    lattice_tree_load "$LATTICE_ROOT" || exit 1

    lattice_screen_init
    LATTICE_SCREEN_ACTIVE=1
    lattice_event_loop
    lattice_cleanup
    trap - EXIT INT TERM HUP

    # Clean exit only for sessions created by the launcher. A manually started
    # --tui inside an existing tmux session must not kill the user's session.
    if (( LATTICE_OWN_SESSION )) ; then
        lattice_tmux_quick kill-session -t "$LATTICE_TMUX_SESSION" 2>/dev/null || true
    fi
    return 0
}

lattice_list_commands ()
{
    local i
    lattice_registry_load || return 1
    for ((i=0;i<${#LATTICE_CMD_IDS[@]};i++)); do
        printf '%-30s %-8s %-8s %s\n' \
            "${LATTICE_CMD_NAMES[i]}" \
            "${LATTICE_CMD_SCOPES[i]}" "${LATTICE_CMD_TARGETS[i]}" \
            "${LATTICE_CMD_COMMANDS[i]}"
    done
}

lattice_print_command ()
{
    local name=$1 idx
    lattice_registry_load || return 1
    lattice_registry_index_for_name "$name" || {
        lattice_status "no command named '$name'" error
        return 1
    }
    idx=$REPLY
    printf '%s\n' "${LATTICE_CMD_COMMANDS[idx]}"
}

lattice_create_session ()
{
    local self=$1 root=$2 config=$3 session=$4
    local tui_cmd pane
    local -a panes=()

    lattice_tmux_available || {
        printf 'lattice: tmux not found; install tmux or run --tui in an existing pane\n' >&2
        return 1
    }
    LATTICE_TMUX_SESSION=$session

    if lattice_tmux_session_exists ; then
        if lattice_tmux_has_role tui && lattice_tmux_has_role executor ; then
            lattice_tmux_mouse_on
            lattice_tmux_select_role tui
            lattice_tmux attach -t "$session"
            return $?
        fi
        # A half-created session (TUI only or executor only) is the state that
        # used to leave a blocked split-window client behind.
        lattice_tmux_quick kill-session -t "$session" 2>/dev/null || true
    fi

    printf -v tui_cmd 'exec %q --tui --owned --root %q --config %q --session %q' \
        "$self" "$root" "$config" "$session"
    # Start with a plain shell, split first, then respawn the TUI. Starting the
    # TUI before the split makes it cache the full-window width and renders
    # misaligned inside the smaller pane.
    # The first tmux server start can be much slower than a normal control
    # command on MSYS2; give only this one a longer cold-start window.
    LATTICE_TMUX_TIMEOUT=10 lattice_tmux_quick new-session -d -s "$session" -n work -c "$root" \
        'exec bash --noprofile --norc' || {
        printf 'lattice: tmux new-session failed for session %s\n' "$session" >&2
        return 1
    }
    lattice_tmux_mouse_on
    if ! lattice_tmux_quick split-window -h -p 70 -t "$session:work" -c "$root" \
            "$(lattice_tmux_executor_command)" ; then
        printf 'lattice: tmux split-window failed (executor pane)\n' >&2
        lattice_tmux_quick kill-session -t "$session" 2>/dev/null || true
        return 1
    fi

    mapfile -t panes < <(lattice_tmux_quick list-panes -t "$session:work" -F '#{pane_id}')
    if (( ${#panes[@]} < 2 )) ; then
        printf 'lattice: tmux session has fewer than two panes\n' >&2
        lattice_tmux_quick kill-session -t "$session" 2>/dev/null || true
        return 1
    fi
    lattice_tmux_mark_role "${panes[0]}" tui
    lattice_tmux_mark_role "${panes[1]}" executor
    if ! lattice_tmux_quick respawn-pane -k -t "${panes[0]}" "$tui_cmd" ; then
        printf 'lattice: tmux respawn-pane failed (TUI)\n' >&2
        lattice_tmux_quick kill-session -t "$session" 2>/dev/null || true
        return 1
    fi
    lattice_tmux_quick select-pane -t "${panes[0]}"
    lattice_tmux attach -t "$session"
}

main ()
{
    local root=$LATTICE_ROOT config=$LATTICE_CONFIG session=$LATTICE_TMUX_SESSION
    local mode='launch'

    while (($#)) ; do
        case "$1" in
        --root) root=$2 ; shift 2 ;;
        --config) config=$2 ; shift 2 ;;
        --session) session=$2 ; shift 2 ;;
        --tui) mode='tui' ; shift ;;
        --owned) LATTICE_OWN_SESSION=1 ; shift ;;
        --no-tmux) LATTICE_NO_TMUX=1 ; shift ;;
        --list-commands) mode='list' ; shift ;;
        --print-command) mode='print' ; PRINT_KEY=$2 ; shift 2 ;;
        --machine-id) mode='machine' ; shift ;;
        --version|-v) mode='version' ; shift ;;
        --help|-h) lattice_usage ; return 0 ;;
        *) printf 'lattice: unknown option %s\n' "$1" >&2 ; lattice_usage >&2 ; return 1 ;;
        esac
    done

    [[ "$mode" == 'version' ]] && {
        printf 'lattice v%s\n' "$LATTICE_VERSION"
        return 0
    }

    [[ -d "$root" ]] || { printf 'lattice: not a directory: %s\n' "$root" >&2 ; return 1 ; }
    root=$(cd -- "$root" && pwd)
    LATTICE_ROOT=$root
    LATTICE_CONFIG=$config
    LATTICE_TMUX_SESSION=$session

    case "$mode" in
    version) printf 'lattice v%s\n' "$LATTICE_VERSION" ;;
    list) lattice_list_commands ;;    print) lattice_print_command "$PRINT_KEY" ;;
    machine)
        printf 'machine: %s\n' "$LATTICE_MACHINE_ID"
        printf 'common:  %s\n' "$LATTICE_ENV_CONF"
        printf 'machine: %s/%s.conf\n' "$LATTICE_ENV_DIR" "$LATTICE_MACHINE_ID"
        ;;
    tui) lattice_app_main ;;
    launch)
        if [[ -n "${TMUX:-}" ]] ; then
            lattice_app_main
        else
            lattice_create_session "$LATTICE_SELF" "$root" "$config" "$session"
        fi
        ;;
    esac
}

main "$@"
