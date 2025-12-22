((_TRIE_IMPORTED++)) && return 0

. array.sh

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

_split_tokens ()
{
    local tokens_str=$1
    local -a tokens=()
    while [[ -n "$tokens_str" ]] ; do
        tokens+=("${tokens_str%%"$S"*}")
        tokens_str="${tokens_str#*"$S"}"
    done
    REPLY="${tokens[*]@Q}"
}

trie_init ()
{
    local -A t=()
    local j_type=$1
    t[$TR_ROOT_ID]=1
    t[$TR_ROOT_ID.children]=''
    t[$TR_ROOT_ID.key]=''

    # Next available node ID
    t[max_index]=2
    REPLY=${t[*]@K}
}

# Subtree mount
trie_graft ()
{
    :
}

trie_key_is_invalid ()
{
    if [[ "$1" == "$S"* ]] ||
        [[ "$1" == *"$S$S"* ]] ||
        [[ "$1" == "$S" ]] ||
        [[ "$1" != *"$S" ]] ; then
        return $TR_RET_ENUM_KEY_IS_NULL
    else
        return $TR_RET_ENUM_OK
    fi
}

trie_insert ()
{
    local -n tr=$1
    local tr_full_key=$2

    trie_key_is_invalid "$tr_full_key" || return $?

    local tr_value=$3

    # If it is a leaf node, update the value directly
    if [[ -v 'tr["$tr_full_key"]' ]] ; then
        tr["$tr_full_key"]=$tr_value
        return ${TR_RET_ENUM_OK}
    fi

    local tr_token tr_child_key tr_child_id
    eval -- local -a tr_tokens=(${|_split_tokens "$tr_full_key";})
    local tr_node=${TR_ROOT_ID}

    for tr_token in "${tr_tokens[@]}" ; do
        # The upper layer cannot be leaves
        [[ -n "${tr[$tr_node.key]}" ]] && {
            return ${TR_RET_ENUM_KEY_UP_LEV_HAVE_LEAF}
        }

        tr_child_key="$tr_node.child.$tr_token"
        tr_child_id="${tr[$tr_child_key]}"

        # Child node does not exist -> create
        if [[ -z "$tr_child_id" ]] ; then
            tr_child_id="${tr[max_index]}"
            ((tr[max_index]++))
            tr[$tr_child_id]=1
            tr[$tr_child_id.children]=''
            tr[$tr_child_id.key]=''

            eval -- local -a tr_children=(${|_split_tokens "${tr[$tr_node.children]}";})
            if [[ "${tr[$tr_node.children]//"$S"/}${tr_token}" == *[^0-9]* ]] ; then
                array_sorted_insert tr_children "$tr_token" '>'
            else
                array_sorted_insert tr_children "$tr_token" '-gt'
            fi
            
            printf -v tr[$tr_node.children] "%s$S" "${tr_children[@]}"
            tr["$tr_child_key"]=$tr_child_id
        fi

        tr_node=$tr_child_id
    done

    # Write leaf key
    tr[$tr_node.key]=$tr_full_key
    tr["$tr_full_key"]=$tr_value

    return 0
}

trie_dump()
{
    local -n tr=$1
    local tr_node=${2:-$TR_ROOT_ID}
    local tr_indent=${3:-""}

    # Traverse children
    eval -- local -a tr_children=(${|_split_tokens "${tr[$tr_node.children]}";})

    local tr_token
    for tr_token in "${tr_children[@]}"; do
        local tr_child_id="${tr[$tr_node.child.$tr_token]}"

        if [[ -n "${tr[$tr_child_id.key]}" ]]; then
            local tr_key=${tr[$tr_child_id.key]}
            local tr_value=${tr["$tr_key"]}
            printf "%s%s(%s) => %s\n" \
                "$tr_indent" "$tr_token" "$tr_child_id" "$tr_value"
        else
            printf "%s%s(%s)\n" "$tr_indent" "$tr_token" "$tr_child_id"
        fi

        trie_dump "$1" "$tr_child_id" "    $tr_indent"
    done
}

#--------------------------Trie tree-------------------------------------------
# eval -- declare -A t=(${|trie_init;})
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
trie_delete() 
{
    local -n tr=$1
    local tr_full_key=$2

    trie_key_is_invalid "$tr_full_key" || return $?
    
    eval -- local -a tr_tokens=(${|_split_tokens "$tr_full_key";})

    # 2. Path search: go all the way from root to the node to be deleted
    local tr_node=$TR_ROOT_ID
    local -a tr_path_nodes=("$tr_node")
    local -a tr_path_tokens=("")

    local tr_token tr_child_id
    for tr_token in "${tr_tokens[@]}"; do
        tr_child_id="${tr[$tr_node.child.$tr_token]}"
        [[ -z "$tr_child_id" ]] && return "$TR_RET_ENUM_KEY_IS_NOTFOUND"
        tr_path_nodes+=("$tr_child_id")
        tr_path_tokens+=("$tr_token")
        tr_node=$tr_child_id
    done

    # At this time, tr_node is the node corresponding to tr_full_key
    # (it can be a leaf or an intermediate node)

    # 3. First delete the value/key attached to the current node
    # (both leaves and intermediate nodes may have key/value)
    unset -v 'tr["$tr_full_key"]'   # delete value
    unset -v 'tr["$tr_node.key"]'   # delete key

    # 4. Kill all subtrees rooted at the current node
    #   (even if it is a single leaf)
    local -a tr_stack=("$tr_node")
    local tr_cur tr_tk tr_cid
    while ((${#tr_stack[@]})); do
        tr_cur=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'

        # Get the current node children tr_token list
        eval -- local -a tr_children=(${|_split_tokens "${tr[$tr_cur.children]}";})

        for tr_tk in "${tr_children[@]}"; do
            tr_cid="${tr[$tr_cur.child.$tr_tk]}"
            tr_stack+=("$tr_cid")
            unset -v "tr[$tr_cur.child.$tr_tk]"
        done

        # If this node has its own key/value, clear it as well.
        local tr_key=${tr["$tr_cur.key"]}
        [[ -n "$tr_key" ]] && unset -v 'tr[$tr_key]'
        unset -v 'tr["$tr_cur.key"]'
        unset -v 'tr["$tr_cur.children"]'

        # Do not delete the root node itself
        (( tr_cur == TR_ROOT_ID )) || unset -v "tr[$tr_cur]"
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
        eval -- local -a tr_children=(${|_split_tokens "${tr[$tr_parent.children]}";})

        local -a tr_new=()
        local tr_x
        for tr_x in "${tr_children[@]}"; do
            [[ "$tr_x" != "$tr_token" ]] && tr_new+=("$tr_x")
        done

        if ((${#tr_new[@]} == 0)); then
            tr[$tr_parent.children]=''
        else
            printf -v 'tr[$tr_parent.children]' "%s$S" "${tr_new[@]}"
        fi

        # 2) Delete tr_parent.child.$tr_token mapping
        unset -v 'tr["$tr_parent.child.$tr_token"]'

        # 3) If the parent also has children or a key, it cannot be cut upwards.
        #   In fact, intermediate nodes cannot have keys, only leaf nodes can
        #   have keys, but it can be left here.
        if [[ -n "${tr[$tr_parent.children]}" || -n "${tr[$tr_parent.key]}" ]] ; then
            break
        fi

        # 4) If parent has become an "empty node":
        # children empty + key empty → empty node, can be cut, but keep root
        (( tr_parent == TR_ROOT_ID )) && break

        unset -v 'tr["$tr_parent"]'
        unset -v 'tr["$tr_parent.children"]'
        unset -v 'tr["$tr_parent.key"]'
        # Continue to look up the next level tr_parent
    done

    return "$TR_RET_ENUM_OK"
}

