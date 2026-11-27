# lattice/fs/tree.sh — directory listing and navigation
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[fs_tree]++ )) && return 0

declare -ga LATTICE_ENTRIES=()
declare -ga LATTICE_ENTRY_IS_DIR=()
declare -ga LATTICE_ALL_ENTRIES=()
declare -ga LATTICE_ALL_ENTRY_IS_DIR=()
declare -gA LATTICE_TREE_ROW_CACHE=()
LATTICE_SHOW_HIDDEN=${LATTICE_SHOW_HIDDEN:-0}
LATTICE_TREE_FILTER=''
LATTICE_TREE_SEARCH=0

lattice_tree_apply_filter ()
{
    local i name q=${LATTICE_TREE_FILTER,,}
    if [[ -z "$q" ]] ; then
        LATTICE_ENTRIES=("${LATTICE_ALL_ENTRIES[@]}")
        LATTICE_ENTRY_IS_DIR=("${LATTICE_ALL_ENTRY_IS_DIR[@]}")
        (( LATTICE_TREE_SELECTED >= ${#LATTICE_ENTRIES[@]} )) && \
            LATTICE_TREE_SELECTED=$(( ${#LATTICE_ENTRIES[@]} - 1 ))
        (( LATTICE_TREE_SELECTED < 0 )) && LATTICE_TREE_SELECTED=0
        return 0
    fi
    LATTICE_ENTRIES=()
    LATTICE_ENTRY_IS_DIR=()
    for ((i=0;i<${#LATTICE_ALL_ENTRIES[@]};i++)); do
        name=${LATTICE_ALL_ENTRIES[i]}
        if [[ "$name" == '..' ]] ||
           [[ "${name,,}" == *"$q"* ]] ; then
            LATTICE_ENTRIES+=("$name")
            LATTICE_ENTRY_IS_DIR+=("${LATTICE_ALL_ENTRY_IS_DIR[i]}")
        fi
    done
    (( LATTICE_TREE_SELECTED >= ${#LATTICE_ENTRIES[@]} )) && \
        LATTICE_TREE_SELECTED=$(( ${#LATTICE_ENTRIES[@]} - 1 ))
    (( LATTICE_TREE_SELECTED < 0 )) && LATTICE_TREE_SELECTED=0
}

lattice_tree_set_filter ()
{
    LATTICE_TREE_FILTER=$1
    LATTICE_TREE_SELECTED=0
    lattice_tree_apply_filter
}

lattice_tree_search_open ()
{
    LATTICE_TREE_SEARCH=1
    LATTICE_TREE_FILTER=''
    LATTICE_TREE_SELECTED=0
    lattice_tree_apply_filter
}

lattice_tree_search_close ()
{
    LATTICE_TREE_SEARCH=0
    LATTICE_TREE_FILTER=''
    LATTICE_TREE_SELECTED=0
    lattice_tree_apply_filter
}

lattice_tree_load ()
{
    local dir=${1:-$LATTICE_DIR}
    local -a names=()
    local -A kind=()
    local p n rec type

    [[ -d "$dir" ]] || {
        lattice_status "not a directory: $dir" error
        return 1
    }
    dir=$(cd -- "$dir" 2>/dev/null && pwd) || return 1
    LATTICE_DIR=$dir

    # One find pass gets entry type and name without a Bash stat per entry.
    # -printf is GNU find (MSYS2); NUL separation keeps spaces/newlines safe.
    while IFS= read -r -d '' rec ; do
        type=${rec:0:1}
        n=${rec:2}
        [[ -n "$n" ]] || continue
        if (( ! LATTICE_SHOW_HIDDEN )) && [[ "$n" == .* ]] ; then
            continue
        fi
        if [[ "$type" == 'l' ]] && [[ -d "$dir/$n" ]] ; then
            type=d
        fi
        names+=("$n")
        kind[$n]=$type
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -printf '%y %f\0' 2>/dev/null)

    # sort once in C order; this is a navigation list, not a hot render path.
    if ((${#names[@]})) ; then
        mapfile -t names < <(printf '%s\n' "${names[@]}" | LC_ALL=C sort)
    fi

    LATTICE_ALL_ENTRIES=()
    LATTICE_ALL_ENTRY_IS_DIR=()
    if [[ "$dir" != '/' ]] ; then
        LATTICE_ALL_ENTRIES+=('..')
        LATTICE_ALL_ENTRY_IS_DIR+=(1)
    fi
    for n in "${names[@]}" ; do
        LATTICE_ALL_ENTRIES+=("$n")
        if [[ "${kind[$n]:-f}" == 'd' ]] ; then
            LATTICE_ALL_ENTRY_IS_DIR+=(1)
        else
            LATTICE_ALL_ENTRY_IS_DIR+=(0)
        fi
    done

    lattice_tree_apply_filter
    lattice_status "$dir"
    return 0
}

lattice_tree_move ()
{
    local delta=$1 max
    max=$(( ${#LATTICE_ENTRIES[@]} - 1 ))
    (( max < 0 )) && return 0
    LATTICE_TREE_SELECTED=$(( LATTICE_TREE_SELECTED + delta ))
    (( LATTICE_TREE_SELECTED < 0 )) && LATTICE_TREE_SELECTED=0
    (( LATTICE_TREE_SELECTED > max )) && LATTICE_TREE_SELECTED=$max
    lattice_selected_path
    lattice_status "$REPLY"
}

lattice_tree_enter ()
{
    local path
    lattice_selected_path
    path=$REPLY
    if [[ -d "$path" ]] ; then
        LATTICE_TREE_SELECTED=0
        LATTICE_TREE_SEARCH=0
        LATTICE_TREE_FILTER=''
        lattice_tree_load "$path" || return $?
    else
        lattice_executor_open_file "$path"
    fi
}

lattice_tree_parent ()
{
    local parent
    [[ "$LATTICE_DIR" == '/' ]] && return 0
    parent=${LATTICE_DIR%/*}
    [[ -z "$parent" ]] && parent='/'
    LATTICE_TREE_SELECTED=0
    LATTICE_TREE_SEARCH=0
    LATTICE_TREE_FILTER=''
    lattice_tree_load "$parent" || return $?
}

lattice_tree_toggle_hidden ()
{
    if (( LATTICE_SHOW_HIDDEN )) ; then
        LATTICE_SHOW_HIDDEN=0
    else
        LATTICE_SHOW_HIDDEN=1
    fi
    lattice_tree_load "$LATTICE_DIR"
}

lattice_tree_open_directory ()
{
    local path opener="$LATTICE_HOME/executor/open-directory.sh"
    lattice_selected_path
    path=$REPLY
    if [[ -f "$path" ]] ; then
        path=${path%/*}
        [[ -n "$path" ]] || path='/'
    fi
    if [[ ! -d "$path" ]] ; then
        lattice_status "not a directory: $path" error
        return 1
    fi
    [[ -x "$opener" ]] || {
        lattice_status "directory opener missing" error
        return 1
    }
    "$opener" "$path" >/dev/null 2>&1 &
    lattice_status "open directory: $path" ok
}

lattice_tree_yank_path ()
{
    local path copier="$LATTICE_HOME/executor/copy-selection.sh"
    lattice_selected_path
    path=$REPLY
    [[ -n "$path" ]] || return 1
    [[ -x "$copier" ]] || {
        lattice_status "clipboard helper missing" error
        return 1
    }
    printf '%s' "$path" | "$copier" >/dev/null 2>&1 || {
        lattice_status "copy path failed" error
        return 1
    }
    lattice_clipboard_cache_write "$path" 2>/dev/null || true
    lattice_status "copied path: $path" ok
}

lattice_tree_register ()
{
    local key=$1 path
    lattice_selected_path
    path=$REPLY
    lattice_register_write "$key" "$path" || {
        lattice_status "register write failed: WB_$key" error
        return 1
    }
    lattice_status "WB_$key <- $path" ok
}

lattice_tree_refresh ()
{
    local path=$LATTICE_DIR
    lattice_tree_load "$path"
}
