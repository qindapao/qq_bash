# lattice/fs/tree.sh — directory listing and navigation
declare -gA _LATTICE_LOADED
(( _LATTICE_LOADED[fs_tree]++ )) && return 0

declare -ga LATTICE_ENTRIES=()
declare -ga LATTICE_ENTRY_IS_DIR=()
declare -ga LATTICE_ALL_ENTRIES=()
declare -ga LATTICE_ALL_ENTRY_IS_DIR=()
LATTICE_SHOW_HIDDEN=${LATTICE_SHOW_HIDDEN:-0}
LATTICE_TREE_FILTER=''
LATTICE_TREE_SEARCH=0

lattice_tree_apply_filter ()
{
    LATTICE_ENTRIES=()
    LATTICE_ENTRY_IS_DIR=()
    local i name q=${LATTICE_TREE_FILTER,,}
    for ((i=0;i<${#LATTICE_ALL_ENTRIES[@]};i++)); do
        name=${LATTICE_ALL_ENTRIES[i]}
        if [[ "$name" == '..' ]] ||
           [[ -z "$q" || "${name,,}" == *"$q"* ]] ; then
            LATTICE_ENTRIES+=("$name")
            LATTICE_ENTRY_IS_DIR+=("${LATTICE_ALL_ENTRY_IS_DIR[i]}")
        fi
    done
    (( LATTICE_SELECTED >= ${#LATTICE_ENTRIES[@]} )) && \
        LATTICE_SELECTED=$(( ${#LATTICE_ENTRIES[@]} - 1 ))
    (( LATTICE_SELECTED < 0 )) && LATTICE_SELECTED=0
}

lattice_tree_set_filter ()
{
    LATTICE_TREE_FILTER=$1
    LATTICE_SELECTED=0
    lattice_tree_apply_filter
}

lattice_tree_search_open ()
{
    LATTICE_TREE_SEARCH=1
    LATTICE_TREE_FILTER=''
    LATTICE_SELECTED=0
    lattice_tree_apply_filter
}

lattice_tree_search_close ()
{
    LATTICE_TREE_SEARCH=0
    LATTICE_TREE_FILTER=''
    LATTICE_SELECTED=0
    lattice_tree_apply_filter
}

lattice_tree_load ()
{
    local dir=${1:-$LATTICE_DIR}
    local -a names=() dirs=()
    local p n

    [[ -d "$dir" ]] || {
        lattice_status "not a directory: $dir" error
        return 1
    }
    dir=$(cd -- "$dir" 2>/dev/null && pwd) || return 1
    LATTICE_DIR=$dir

    if (( LATTICE_SHOW_HIDDEN )) ; then
        shopt -s nullglob dotglob
        for p in "$dir"/* ; do
            n=${p##*/}
            [[ "$n" == '.' || "$n" == '..' ]] && continue
            names+=("$n")
        done
        shopt -u dotglob
        shopt -u nullglob
    else
        shopt -s nullglob
        for p in "$dir"/* ; do
            n=${p##*/}
            names+=("$n")
        done
        shopt -u nullglob
    fi

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
        if [[ -d "$dir/$n" ]] ; then
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
    LATTICE_SELECTED=$(( LATTICE_SELECTED + delta ))
    (( LATTICE_SELECTED < 0 )) && LATTICE_SELECTED=0
    (( LATTICE_SELECTED > max )) && LATTICE_SELECTED=$max
    lattice_selected_path
    lattice_status "$REPLY"
}

lattice_tree_enter ()
{
    local path
    lattice_selected_path
    path=$REPLY
    if [[ -d "$path" ]] ; then
        LATTICE_SELECTED=0
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
    LATTICE_SELECTED=0
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

lattice_tree_refresh ()
{
    local path=$LATTICE_DIR
    lattice_tree_load "$path"
}
