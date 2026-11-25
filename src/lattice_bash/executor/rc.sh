# lattice/executor/rc.sh — dedicated executor shell context hook
# The TUI writes WB_DIR/WB_FILE/WB_ROOT to LATTICE_CONTEXT_FILE before it
# pastes a command. DEBUG exports them before execution.

__lattice_context ()
{
    local dir file root
    [[ -n "${LATTICE_CONTEXT_FILE:-}" && -s "$LATTICE_CONTEXT_FILE" ]] || return 0
    {
        IFS= read -r dir
        IFS= read -r file
        IFS= read -r root
    } < "$LATTICE_CONTEXT_FILE" || true
    export WB_DIR=$dir WB_FILE=$file WB_ROOT=$root
}

trap '__lattice_context' DEBUG
PS1='lattice:\w\$ '
