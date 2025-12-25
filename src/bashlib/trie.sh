((_TRIE_IMPORTED++)) && return 0

# :TODO: Currently the semantics of trie_insert and trie_graft are different
#   trie_insert It is not allowed to destroy the original tree. Only legal
#       leaves can be inserted. Leaves in the upper path are not allowed.
#   trie_graft Allow destruction, force tree insertion

TR_LIBS_DIR=${BASH_SOURCE[0]%/*}
. "$TR_LIBS_DIR/array.sh"

# All variable names in the library start with tr_.
# Be careful to avoid external variables.
# tr_

S=$'\034'
TR_ROOT_ID=1
TR_RET_ENUM_OK=0
TR_RET_ENUM_KEY_IS_TREE=1
TR_RET_ENUM_KEY_IS_LEAF=2
TR_RET_ENUM_KEY_IS_NOTFOUND=3
TR_RET_ENUM_KEY_IS_NULL=8
TR_RET_ENUM_KEY_UP_LEV_HAVE_LEAF=9
TR_RET_ENUM_TREE_IS_INVALID=10
TR_RET_ENUM_TREE_IS_EMPTY=11
TR_RET_ENUM_TREE_NOT_HAVE_ROOT=12

TR_RET_ENUM_TREE_IS_NOT_SAME=1

_str_is_decimal_positive_int ()
{
    [[ -z "$1" ]] && return 1
    [[ "$1" == "0" || ( -z "${1//[0-9]/}" && "$1" != 0* ) ]]
}

_array_is_all_decimal_positive_int ()
{
    local item
    for item in "$@" ; do
        _str_is_decimal_positive_int "$item" || return 1
    done

    return 0
}

# $?
# 0 all digital
# 1 Contains non-digits
_split_tokens ()
{
    local tokens_str=$1
    local -i is_need_check=${2:-0}
    local -a tokens=()
    local -i all_numeric=0
    if ((is_need_check)) ; then
        local tk
        while [[ -n "$tokens_str" ]] ; do
            tk="${tokens_str%%"$S"*}"
            tokens+=("$tk")
            tokens_str="${tokens_str#*"$S"}"
            ((all_numeric)) || {
                _str_is_decimal_positive_int "$tk" || all_numeric=1
            }
        done
    else
        while [[ -n "$tokens_str" ]] ; do
            tokens+=("${tokens_str%%"$S"*}")
            tokens_str="${tokens_str#*"$S"}"
        done
    fi
    
    REPLY="${tokens[*]@Q}"
    return $all_numeric
}

trie_init ()
{
    local -A t=()
    local j_type=$1
    t[$TR_ROOT_ID]=1
    # t[$TR_ROOT_ID.children]=''
    # t[$TR_ROOT_ID.key]=''

    # Next available node ID
    t[max_index]=2
    REPLY=${t[*]@K}
}

# Verify whether the subtree is a basic trie
_trie_tree_is_valid ()
{
    local -n tr_tree=$1

    [[ "${tr_tree@a}" != *A* ]] && {
        echo "invalid tree: $1 is not an associative array!" >&2
        return ${TR_RET_ENUM_TREE_IS_INVALID}
    }

    ((${#tr_tree[@]})) || {
        echo "invalid tree: $1 is empty!" >&2
        return ${TR_RET_ENUM_TREE_IS_EMPTY}
    }

    [[ -v tr_tree[$TR_ROOT_ID] ]] || {
        echo "invalid tree: $1 not have root node!" >&2
        return ${TR_RET_ENUM_TREE_NOT_HAVE_ROOT}
    }

    return ${TR_RET_ENUM_OK}
}

# Subtree mount
# Reuse trie_insert, so it is not the most efficient implementation version
# is the simplest implementation
trie_graft ()
{
    local tr_target_name=$1
    local -n tr_target=$1
    local -n tr_sub=$2
    local tr_prefix=$3

    # 1. Delete the old subtree (including leaves) under prefix
    trie_delete "$1" "$tr_prefix"

    # 2. Simply check the legality of the subtree
    _trie_tree_is_valid "$2" || return $?

    # 3. DFS traverses the subtree and inserts all leaves into tr_target
    local -a "tr_sub_root_children=(${|_split_tokens "${tr_sub[$TR_ROOT_ID.children]}";})"

    local -a tr_stack_ids=()
    local tr_tk tr_cid

    for tr_tk in "${tr_sub_root_children[@]}" ; do
        tr_cid="${tr_sub["$TR_ROOT_ID.child.$tr_tk"]}"
        tr_stack_ids+=("$tr_cid")
    done

    while ((${#tr_stack_ids[@]})) ; do
        local tr_cur=${tr_stack_ids[-1]}
        unset -v 'tr_stack_ids[-1]'

        local tr_sub_leaf_full_key="${tr_sub["$tr_cur.key"]}"
        if [[ -n "$tr_sub_leaf_full_key" ]] ; then
            trie_insert tr_target "${tr_prefix}${tr_sub_leaf_full_key}" "${tr_sub["$tr_sub_leaf_full_key"]}" || return $?
        fi

        local -a "tr_children=(${|_split_tokens "${tr_sub[$tr_cur.children]}";})"
        for tr_tk in "${tr_children[@]}" ; do
            tr_cid="${tr_sub["$tr_cur.child.$tr_tk"]}"
            tr_stack_ids+=("$tr_cid")
        done
    done

    return ${TR_RET_ENUM_OK}
}

trie_key_is_invalid ()
{
    if [[ "$1" == "$S"* ]] ||
        [[ "$1" == *"$S$S"* ]] ||
        [[ "$1" == "$S" ]] ||
        [[ "$1" != *"$S" ]] ; then
        echo "key is null or invalid!" >&2
        return $TR_RET_ENUM_KEY_IS_NULL
    else
        return $TR_RET_ENUM_OK
    fi
}

trie_inserts ()
{
    set -- "${@:2}" "$1"
    while (($#>1)) ; do
        trie_insert "${!#}" "$1" "$2" ; shift 2
    done
}

trie_insert ()
{
    local -n tr_t=$1
    local tr_full_key=$2

    trie_key_is_invalid "$tr_full_key" || return $?

    local tr_value=$3

    # If it is a leaf node, update the value directly
    if [[ -v 'tr_t["$tr_full_key"]' ]] ; then
        tr_t["$tr_full_key"]=$tr_value
        return ${TR_RET_ENUM_OK}
    fi

    local tr_token tr_child_key tr_child_id
    local -a "tr_tokens=(${|_split_tokens "$tr_full_key";})"
    local tr_node=${TR_ROOT_ID}

    for tr_token in "${tr_tokens[@]}" ; do
        # The upper layer cannot be leaves
        [[ -n "${tr_t[$tr_node.key]}" ]] && {
            echo "parent have leaf key!" >&2
            return ${TR_RET_ENUM_KEY_UP_LEV_HAVE_LEAF}
        }

        tr_child_key="$tr_node.child.$tr_token"
        tr_child_id="${tr_t[$tr_child_key]}"

        # Child node does not exist -> create
        if [[ -z "$tr_child_id" ]] ; then
            tr_child_id="${tr_t[max_index]}"
            ((tr_t[max_index]++))
            tr_t[$tr_child_id]=1
            # tr_t[$tr_child_id.children]=''
            # tr_t[$tr_child_id.key]=''

            local tr_children_str tr_children_str_ret
            tr_children_str=${|_split_tokens "${tr_t[$tr_node.children]}" "1";}
            tr_children_str_ret=$?
            local -a "tr_children=($tr_children_str)"
            local tr_sort_sub tr_sort_rule
            
            if ((tr_children_str_ret)) ; then
                # Non-numeric (lexicographic insertion sort)
                tr_sort_sub=array_sorted_insert
                tr_sort_rule='>'
            else
                # number
                if _str_is_decimal_positive_int "$tr_token" ; then
                    # Numbers (numeric insertion sort)
                    tr_sort_sub=array_sorted_insert
                    tr_sort_rule='-gt'
                else
                    # Non-numeric (lexicographic quick sort after insertion)
                    tr_sort_sub=array_qsort
                    tr_sort_rule='>'
                fi
            fi

            if [[ "$tr_sort_sub" == "array_sorted_insert" ]] ; then
                array_sorted_insert tr_children "$tr_token" "$tr_sort_rule"
            else
                # Quick sort after insertion
                tr_children+=("$tr_token")
                array_qsort tr_children "$tr_sort_rule"
            fi

            printf -v tr_t[$tr_node.children] "%s$S" "${tr_children[@]}"
            tr_t["$tr_child_key"]=$tr_child_id
        fi

        tr_node=$tr_child_id
    done

    # Write leaf key
    tr_t[$tr_node.key]=$tr_full_key
    tr_t["$tr_full_key"]=$tr_value

    return ${TR_RET_ENUM_OK}
}

trie_dump ()
{
    local tr_t_name=$1
    local -n tr_t=$1
    local tr_full_key=$2
    local tr_node
    tr_node=${|_trie_token_to_node_id "$tr_t_name" "$tr_full_key";} || return $?

    local tr_indent_cnt=${3:-4}
    local tr_indent ; printf -v tr_indent "%*s" "$tr_indent_cnt" ""

    printf "%s\n" "$tr_t_name"
    _trie_dump "$tr_t_name" "$tr_node" "$tr_indent_cnt" "$tr_indent"
}

_trie_dump ()
{
    local -n tr_t=$1
    local tr_node=$2
    local tr_indent_cnt=$3
    local tr_indent=$4
    local tr_indent_new
    printf -v tr_indent_new "%*s" "$tr_indent_cnt" ""
    tr_indent_new+="$tr_indent"

    # Traverse children
    local -a "tr_children=(${|_split_tokens "${tr_t[$tr_node.children]}";})"

    local tr_token
    for tr_token in "${tr_children[@]}"; do
        local tr_child_id="${tr_t[$tr_node.child.$tr_token]}"

        if [[ -n "${tr_t[$tr_child_id.key]}" ]]; then
            local tr_key=${tr_t[$tr_child_id.key]}
            local tr_value=${tr_t["$tr_key"]}
            # :TODO: Double-width aligned display of Chinese has not been considered for
            # the time being.
            local tr_value_indent="${tr_token}(${tr_child_id})"
            tr_value_indent=${tr_value_indent##*$'\n'}
            tr_value_indent=${tr_value_indent//?/ }
            tr_value_indent+="${tr_indent}    "

            printf "%s%s(%s) => %s\n" \
                "$tr_indent" "${tr_token//$'\n'/$'\n'$tr_indent}" "$tr_child_id" "${tr_value//$'\n'/$'\n'$tr_value_indent}"
        else
            printf "%s%s(%s)\n" "${tr_indent}" "${tr_token//$'\n'/$'\n'$tr_indent}" "$tr_child_id"
        fi

        _trie_dump "$1" "$tr_child_id" "$tr_indent_cnt" "$tr_indent_new"
    done
}


trie_dump_flat ()
{
    local tr_t_name=$1
    local -n tr_t=$1
    local tr_indent_cnt=${2:-4}
    local tr_indent
    printf -v tr_indent "%*s" "$tr_indent_cnt" ""
    local tr_indent2="$tr_indent$tr_indent"

    printf "%s\n" "$tr_t_name"
    local -a tr_keys=("${!tr_t[@]}")
    array_qsort 'tr_keys' '>'

    local tr_key tr_key_p tr_value_p
    for tr_key in "${tr_keys[@]}" ; do
        tr_key_p=${tr_key%"$S"}
        tr_key_p=${tr_key_p//"$S"/'.'}
        tr_key_p=${tr_key_p//$'\n'/$'\n'"$tr_indent2"}

        tr_value_p=${tr_t["$tr_key"]%"$S"}
        tr_value_p=${tr_value_p//"$S"/'.'}
        tr_value_p=${tr_value_p//$'\n'/$'\n'"$tr_indent2"}

        printf "${tr_indent}%s => %s\n" "$tr_key_p" "$tr_value_p"
    done
}

_trie_token_to_node_id ()
{
    local -n tr_t=$1
    local tr_full_key=$2

    [[ -z "$tr_full_key" ]] && {
        # ROOT
        REPLY=$TR_ROOT_ID
        return ${TR_RET_ENUM_OK}
    }

    trie_key_is_invalid "$tr_full_key" || return $?

    local -a "tr_tokens=(${|_split_tokens "$tr_full_key";})"
    local tr_node=$TR_ROOT_ID tr_token tr_child_id
    for tr_token in "${tr_tokens[@]}" ; do
        tr_child_id="${tr_t[$tr_node.child.$tr_token]}"
        [[ -z "$tr_child_id" ]] && {
            echo "key is not found!" >&2
            return "$TR_RET_ENUM_KEY_IS_NOTFOUND"
        }
        tr_node=$tr_child_id
    done

    REPLY=$tr_node
    return ${TR_RET_ENUM_OK}
}

#--------------------------Trie tree-------------------------------------------
# declare -A "t=(${|trie_init;})"
# trie_insert "t" "lev1-1${S}lev2-1${S}lev3-1${S}" "value1"
# trie_insert "t" "lev1-1${S}lev2-2${S}11${S}" "value11"
# trie_insert "t" "lev1-1${S}lev2-2${S}0${S}" "value0"
# trie_insert "t" "lev1-1${S}lev2-3${S}lev3-1${S}lev4-1${S}" "value10"
# trie_insert "t" "lev1-1${S}lev2-3${S}lev3-1${S}lev4-2${S}" "value10"
#              T[1]=1                
#              T[1.children]="lev1-1"
#              T[1.child.lev1-1]=2   <----ROOT
#              T[1.key]=""           
# T[2]=1                              
# T[2.children]="lev2-1 lev2-2 lev2-3"
# T[2.child.lev2-1]=3                     .-----------------------------------.
# T[2.child.lev2-2]=5                 <---+-lev1-1(2)                         |
# T[2.child.lev2-3]=8                     |     lev2-1(3)                     |
# T[2.key]=""                             |         lev3-1(4) => value1       |
#                                         |     lev2-2(5)                     |    T[10]=1                                 
#                                         |         0(7) => value0     .---------->T[10.children]=""                       
#        T[8]=1                           |         11(6) => value11   |      |    T[10.key]="lev1-1 lev2-3 lev3-1 lev4-1" 
#        T[8.children]="lev3-1"  <--------+-----lev2-3(8)              |      |    T[lev1-1 lev2-3 lev3-1 lev4-1]="value10"
#        T[8.child.lev3-1]=9            .-+---------lev3-1(9)          |      |
#        T[8.key]=""                    | |             lev4-1(10) => value10 |
#                                       | |             lev4-2(11) => value10 |
#                                       | |                            |      |
#                                       | |                            |      |
#        T[9]=1                         | '----------------------------+------'
#        T[9.children]="lev4-1 lev4-2"  |                              |
#        T[9.child.lev4-1]=10         <-'                              |
#        T[9.child.lev4-2]=11                                          |
#        T[9.key]=""                                                   v
#                                                      T[11]=1                                 
#                                                      T[11.children]=""                       
#                                                      T[11.key]="lev1-1 lev2-3 lev3-1 lev4-2" 
#                                                      T[lev1-1 lev2-3 lev3-1 lev4-2]="value10"
#------------------------------------------------------------------------------
trie_delete () 
{
    local -n tr_t=$1
    local tr_full_key=$2

    # Empty key is legal. Only ROOT nodes are reserved.
    [[ -z "$tr_full_key" ]] && {
        eval -- tr_t=(${|trie_init;})
        return ${TR_RET_ENUM_OK}
    }

    trie_key_is_invalid "$tr_full_key" || return $?
    
    local -a "tr_tokens=(${|_split_tokens "$tr_full_key";})"

    # 2. Path search: go all the way from root to the node to be deleted
    local tr_node=$TR_ROOT_ID
    local -a tr_path_nodes=("$tr_node")
    local -a tr_path_tokens=("")

    local tr_token tr_child_id
    for tr_token in "${tr_tokens[@]}"; do
        tr_child_id="${tr_t[$tr_node.child.$tr_token]}"
        [[ -z "$tr_child_id" ]] && {
            # echo "key is not found!" >&2
            # Keys that do not exist are returned directly.
            return "$TR_RET_ENUM_OK"
        }
        tr_path_nodes+=("$tr_child_id")
        tr_path_tokens+=("$tr_token")
        tr_node=$tr_child_id
    done

    # At this time, tr_node is the node corresponding to tr_full_key
    # (it can be a leaf or an intermediate node)

    # 3. First delete the value/key attached to the current node
    # (both leaves and intermediate nodes may have key/value)
    unset -v 'tr_t["$tr_full_key"]'   # delete value
    unset -v 'tr_t["$tr_node.key"]'   # delete key

    # 4. Kill all subtrees rooted at the current node
    #   (even if it is a single leaf)
    local -a tr_stack=("$tr_node")
    local tr_cur tr_tk tr_cid
    while ((${#tr_stack[@]})); do
        tr_cur=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'

        # Get the current node children tr_token list
        local -a "tr_children=(${|_split_tokens "${tr_t[$tr_cur.children]}";})"

        for tr_tk in "${tr_children[@]}"; do
            tr_cid="${tr_t[$tr_cur.child.$tr_tk]}"
            tr_stack+=("$tr_cid")
            unset -v 'tr_t["$tr_cur.child.$tr_tk"]'
        done

        # If this node has its own key/value, clear it as well.
        local tr_key=${tr_t["$tr_cur.key"]}
        [[ -n "$tr_key" ]] && unset -v 'tr_t[$tr_key]'
        unset -v 'tr_t["$tr_cur.key"]'
        unset -v 'tr_t["$tr_cur.children"]'

        # Do not delete the root node itself
        (( tr_cur == TR_ROOT_ID )) || unset -v "tr_t[$tr_cur]"
    done

    # 5. Bottom-up pruning: delete all the intermediate nodes that have no children or keys.
    local tr_i tr_last tr_parent
    tr_last=$((${#tr_path_nodes[@]} - 1))

    for ((tr_i=tr_last; tr_i>0; tr_i--)); do
        tr_parent=${tr_path_nodes[$((tr_i-1))]}
        tr_token=${tr_path_tokens[$tr_i]}

        # The child has been deleted in the above DFS.
        # Here we only need to remove it from the parent.
        # 1) from parent.children to remove tr_token
        local tr_children_is_num tr_children_str  tr_children_new_str
        tr_children_str=${|_split_tokens "${tr_t[$tr_parent.children]}" "1";}
        tr_children_is_num=$?
        local -a "tr_children=($tr_children_str)"

        local -a tr_new=()
        local tr_x
        for tr_x in "${tr_children[@]}"; do
            [[ "$tr_x" != "$tr_token" ]] && tr_new+=("$tr_x")
        done

        if ((${#tr_new[@]} == 0)); then
            unset -v 'tr_t[$tr_parent.children]'
        else
            # Determine whether reordering is needed
            # 1. All numbers before deletion -> No need to rearrange
            # 2. There are non-digits before deletion
            #       1. There are still non-digits after deletion -> No need to rearrange
            #       2. After deletion, it becomes all numbers -> Quick sort in numerical order
            ((tr_children_is_num)) &&
            _array_is_all_decimal_positive_int "${tr_new[@]}" && {
                array_qsort 'tr_new' '-gt'
            }

            printf -v 'tr_t[$tr_parent.children]' "%s$S" "${tr_new[@]}"
        fi

        # 2) Delete tr_parent.child.$tr_token mapping
        unset -v 'tr_t["$tr_parent.child.$tr_token"]'

        # 3) If the parent also has children or a key, it cannot be cut upwards.
        #   In fact, intermediate nodes cannot have keys, only leaf nodes can
        #   have keys, but it can be left here.
        if [[ -n "${tr_t[$tr_parent.children]}" || -n "${tr_t[$tr_parent.key]}" ]] ; then
            break
        fi

        # 4) If parent has become an "empty node":
        # children empty + key empty → empty node, can be cut, but keep root
        (( tr_parent == TR_ROOT_ID )) && break

        unset -v 'tr_t["$tr_parent"]'
        unset -v 'tr_t["$tr_parent.children"]'
        unset -v 'tr_t["$tr_parent.key"]'
        # Continue to look up the next level tr_parent
    done

    return "$TR_RET_ENUM_OK"
}

trie_get_subtree ()
{
    local tr_t_name=$1
    local -n tr_t=$1
    local tr_full_key=$2

    # 1. If tr_full_key is empty, return the entire tree directly
    [[ -z "$tr_full_key" ]] && {
        REPLY="${tr_t[*]@K}"
        return ${TR_RET_ENUM_OK}
    }

    # 2. Determine whether tr_full_key is legal
    trie_key_is_invalid "$tr_full_key" || return $?

    # 3. Determine whether it is a leaf node. If it is a leaf node, return an error.
    [[ -v 'tr_t["$tr_full_key"]' ]] && {
        echo "key is leaf!" >&2
        return ${TR_RET_ENUM_KEY_IS_LEAF}
    }

    # 4. Find the node ID corresponding to tr_full_key
    local tr_node
    tr_node=${|_trie_token_to_node_id "$tr_t_name" "$tr_full_key";} || return $?

    # 5. Get the children of the node (the first-level node of the subtree)
    local -a "tr_root_children=(${|_split_tokens "${tr_t[$tr_node.children]}";})"

    # 6. Create a new tree
    local -A "tr_new=(${|trie_init;})"

    # 7. The children of the new tree are reset to the current tr_root_children
    printf -v tr_new[$TR_ROOT_ID.children] "%s$S" "${tr_root_children[@]}"

    # 8. Mount all root children
    local tr_tk tr_cid
    local -a tr_stack=()
    for tr_tk in "${tr_root_children[@]}" ; do
        tr_cid=${tr_t[$tr_node.child.$tr_tk]}
        tr_new["$TR_ROOT_ID.child.$tr_tk"]="$tr_cid"
        tr_stack+=("$tr_cid")
    done

    # 9. DFS copy child node
    local tr_max_id=1
    while ((${#tr_stack[@]})) ; do
        local tr_cur=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'
        ((tr_max_id=(tr_cur>tr_max_id)?tr_cur:tr_max_id))

        tr_new[$tr_cur]=1
        if [[ -n "${tr_t[$tr_cur.children]}" ]] ; then
            tr_new[$tr_cur.children]=${tr_t[$tr_cur.children]}
        fi

        # The key here cannot be copied directly from the old tree, and 
        # the prefix needs to be cut off.
        local tr_key=${tr_t["$tr_cur.key"]}
        if [[ -n "$tr_key" ]] ; then
            tr_new[$tr_cur.key]=${tr_key#"$tr_full_key"}
            local tr_new_key=${tr_new["$tr_cur.key"]}
            tr_new["$tr_new_key"]=${tr_t["$tr_key"]}
        fi

        local -a "tr_children=(${|_split_tokens "${tr_t[$tr_cur.children]}";})"

        for tr_tk in "${tr_children[@]}" ; do
            tr_cid="${tr_t["$tr_cur.child.$tr_tk"]}"
            tr_new["$tr_cur.child.$tr_tk"]="$tr_cid"
            tr_stack+=("$tr_cid")
        done
    done

    tr_new[max_index]=$((tr_max_id+1))

    REPLY=${tr_new[*]@K}
    return ${TR_RET_ENUM_OK}
}

# Iterate children under prefix
# Output lines: "leaf token" or "tree token"
trie_iter ()
{
    local -n tr_t=$1
    local tr_prefix=$2

    [[ -n "$tr_prefix" ]] && {
        trie_key_is_invalid "$tr_prefix" || return $?
    }

    local tr_node_id
    tr_node_id=${|_trie_token_to_node_id "$1" "$tr_prefix";} || return $?

    local -a "tr_children=(${|_split_tokens "${tr_t[$tr_node_id.children]}";})"

    local tr_tk tr_child_id tr_type

    for tr_tk in "${tr_children[@]}"; do
        tr_child_id=${tr_t["$tr_node_id.child.$tr_tk"]}

        if [[ -n "${tr_t[$tr_child_id.key]}" ]]; then
            tr_type="leaf"
        else
            tr_type="tree"
        fi

        REPLY+="${REPLY:+$'\n'}${tr_type} ${tr_tk@Q}"
    done

    return ${TR_RET_ENUM_OK}
}

# This is just an example to demonstrate the callback function of trie_walk,
# processing the entire tree
# callback <type> <token> <full_key> <node_id> <parent_id> <value>
trie_callback_print ()
{
    local type=$1 token=$2 full_key=$3 node_id=$4 parent_id=$5 value=$6
    full_key="${full_key//"$S"/'.'}"
    full_key="${full_key%'.'}"
    printf "%s\n" "type:$type full_key:${full_key} node_id:$node_id parent:$parent_id value:${value}"
}

trie_walk ()
{
    local -n tr_t=$1
    local tr_prefix=$2
    local tr_callback=${3:-trie_callback_print}

    local tr_root_id
    tr_root_id=${|_trie_token_to_node_id "$1" "$tr_prefix";} || return $?

    # stack: save (prefix node_id)
    local -a tr_stack=()
    tr_stack+=("$tr_prefix" "$tr_root_id")

    while ((${#tr_stack[@]})); do
        local tr_node_id=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'
        local tr_prefix=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'

        local -a "tr_children=(${|_split_tokens "${tr_t[$tr_node_id.children]}";})"
        local tr_tk tr_child_id tr_type tr_full_key tr_value

        for tr_tk in "${tr_children[@]}"; do
            tr_child_id=${tr_t["$tr_node_id.child.$tr_tk"]}

            if [[ -n "${tr_t[$tr_child_id.key]}" ]]; then
                tr_type="leaf"
                tr_full_key="${tr_t["$tr_child_id.key"]}"
                tr_value="${tr_t["$tr_full_key"]}"
            else
                tr_type="tree"
                tr_value=''
                tr_full_key="${tr_prefix}${tr_tk}$S"
            fi
            
            "$tr_callback" "$tr_type" "$tr_tk" "$tr_full_key" "$tr_child_id" "$tr_node_id" "$tr_value"

            if [[ $tr_type == tree ]]; then
                tr_stack+=("$tr_full_key" "$tr_child_id")
            fi
        done
    done
}

trie_id_rebuild ()
{
    local -n tr_old=$1
    local -a tr_id_list=()

    trie_id_rebuild_collect_ids_callback ()
    {
        local type=$1 token=$2 full_key=$3 old_id=$4 parent_old_id=$5 value=$6
        tr_id_list+=("$old_id")
    }
    trie_walk tr_old '' trie_id_rebuild_collect_ids_callback
    unset -f trie_id_rebuild_collect_ids_callback

    array_qsort tr_id_list '-gt'
    local -A tr_id_map=()
    local tr_new_id=$((TR_ROOT_ID+1))
    local tr_old_id
    for tr_old_id in "${tr_id_list[@]}" ; do
        tr_id_map[$tr_old_id]=$tr_new_id
        ((tr_new_id++))
    done

    tr_id_map[$TR_ROOT_ID]=1

    local -A "tr_new=(${|trie_init;})"

    trie_id_rebuild_callback ()
    {
        local type=$1 token=$2 full_key=$3 old_id=$4 parent_old_id=$5 value=$6

        local new_id=${tr_id_map[$old_id]}
        local new_parent_id=${tr_id_map[$parent_old_id]}

        tr_new[$new_id]=1
        if [[ $type == leaf ]]; then
            tr_new[$new_id.key]="$full_key"
            tr_new["$full_key"]="$value"
        fi
        tr_new[$new_parent_id.child.$token]="$new_id"
        tr_new[$new_parent_id.children]+="$token$S"
    }
    trie_walk tr_old '' trie_id_rebuild_callback
    unset -f trie_id_rebuild_callback

    tr_new[max_index]=$tr_new_id
    
    REPLY=${tr_new[*]@K}
    return ${TR_RET_ENUM_OK}
}

trie_equals ()
{
    local -n tr_1=$1 tr_2=$2
    local tr_ok=1

    # Iterate over tr_1, check tr_2
    trie_equals_check_ab ()
    {
        local type=$1 full_key=$3 value=$6
        if [[ $type == leaf ]] ; then
            [[ -v 'tr_2["$full_key"]' && "${tr_2[$full_key]}" == "$value" ]] ||
            { tr_ok=0; return; }
        fi
    }
    trie_walk tr_1 '' trie_equals_check_ab

    ((tr_ok)) || {
        echo "$1 $2 not the same!" >&2
        return ${TR_RET_ENUM_TREE_IS_NOT_SAME}
    }

    # Traverse tr_2, check tr_1
    trie_equals_check_ba () {
        local type=$1 full_key=$3 value=$6
        if [[ $type == leaf ]]; then
            [[ -v 'tr_1["$full_key"]' && "${tr_1[$full_key]}" == "$value" ]] ||
            { tr_ok=0; return; }
        fi
    }
    trie_walk tr_2 '' trie_equals_check_ba

    ((tr_ok)) && return ${TR_RET_ENUM_OK} || {
        echo "$1 $2 not the same!" >&2
        return ${TR_RET_ENUM_TREE_IS_NOT_SAME}
    }
}

trie_search ()
{
    :
}

trie_array_push ()
{
    :
}

trie_array_pop ()
{
    :
}

trie_array_shift ()
{
    :
}

trie_array_unshift ()
{
    :
}

trie_array_get ()
{
    :
}

trie_array_set ()
{
    :
}

trie_array_len ()
{
    :
}

trie_array_iter ()
{
    :
}

return 0

