((_TRIE_IMPORTED++)) && return 0

# :TODO: 当前 trie_insert 和 trie_graft 的语义不一样
#   trie_insert 不允许破坏原有的树，只能插入合法的叶子，上层路径有叶子不允许
#   trie_graft 允许破坏，强制插入树，

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
# 0 全数字
# 1 包含非数字
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

# 校验 subtree 是否是一个最基本的 trie
_trie_tree_is_valid ()
{
    local -n tr_tree=$1

    [[ "${tr_tree@a}" != *A* ]] && {
        echo "invalid tree: $1 is not an associative array!" >&2
        return ${TR_RET_ENUM_TREE_IS_INVALID}
    }

    # 不能是空的
    ((${#tr_tree[@]})) || {
        echo "invalid tree: $1 is empty!" >&2
        return ${TR_RET_ENUM_TREE_IS_EMPTY}
    }

    # 必须至少包含 root 节点
    [[ -v tr_tree[$TR_ROOT_ID] ]] || {
        echo "invalid tree: $1 not have root node!" >&2
        return ${TR_RET_ENUM_TREE_NOT_HAVE_ROOT}
    }

    return ${TR_RET_ENUM_OK}
}

# Subtree mount
# 不管是叶子还是子树都强制覆盖
# 复用 trie_insert , 所以说不是最高效的实现版本
# 是最简单实现
trie_graft ()
{
    local tr_target_name=$1
    local -n tr_target=$1
    local -n tr_sub=$2
    local tr_prefix=$3

    # 1. 删除 prefix 下的旧子树(包括叶子)
    trie_delete "$1" "$tr_prefix"

    # 2. 简单检查下子树的合法性
    _trie_tree_is_valid "$2" || return $?

    # 3. DFS 遍历 subtree, 把所有叶子插入 tr_target
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
    local tr_t_name=$1
    shift
    while (($#)) ; do
        trie_insert "$tr_t_name" "$1" "$2"
        shift 2
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
                # 非数字(字典序插入排序)
                tr_sort_sub=array_sorted_insert
                tr_sort_rule='>'
            else
                # 数字
                if _str_is_decimal_positive_int "$tr_token" ; then
                    # 数字(数字序插入排序)
                    tr_sort_sub=array_sorted_insert
                    tr_sort_rule='-gt'
                else
                    # 非数字(插入后做字典序快速排序)
                    tr_sort_sub=array_qsort
                    tr_sort_rule='>'
                fi
            fi

            if [[ "$tr_sort_sub" == "array_sorted_insert" ]] ; then
                array_sorted_insert tr_children "$tr_token" "$tr_sort_rule"
            else
                # 插入后做快速排序
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

    # 空 key 是合法的 只保留 ROOT 节点
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
            # 不存在的键直接返回
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
            tr_t[$tr_parent.children]=''
        else
            # 判断是否需要重新排序
            # 1. 删除前全是数字 -> 不用重排
            # 2. 删除前有非数字
            #       1. 删除后还是有非数字 -> 不用重排
            #       2. 删除后变成了全数字 -> 数字序快排
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

    # 1. 如果 tr_full_key 为空，直接返回整棵树
    [[ -z "$tr_full_key" ]] && {
        REPLY="${tr_t[*]@K}"
        return ${TR_RET_ENUM_OK}
    }

    # 2. 判断 tr_full_key 是否合法
    trie_key_is_invalid "$tr_full_key" || return $?

    # 3. 判断是否是叶子节点，如果是叶子节点，返回错误
    [[ -v 'tr_t["$tr_full_key"]' ]] && {
        echo "key is leaf!" >&2
        return ${TR_RET_ENUM_KEY_IS_LEAF}
    }

    # 4. 找到 tr_full_key 对应的节点 ID 
    local tr_node
    tr_node=${|_trie_token_to_node_id "$tr_t_name" "$tr_full_key";} || return $?

    # 5. 获取该节点的 children (子树的一级节点)
    local -a "tr_root_children=(${|_split_tokens "${tr_t[$tr_node.children]}";})"

    # 6. 创建一颗新树
    local -A "tr_new=(${|trie_init;})"

    # 7. 新树的 children 重置为当前的 tr_root_children
    printf -v tr_new[$TR_ROOT_ID.children] "%s$S" "${tr_root_children[@]}"

    # 8. 挂接所有的 root children
    local tr_tk tr_cid
    local -a tr_stack=()
    for tr_tk in "${tr_root_children[@]}" ; do
        tr_cid=${tr_t[$tr_node.child.$tr_tk]}
        tr_new["$TR_ROOT_ID.child.$tr_tk"]="$tr_cid"
        tr_stack+=("$tr_cid")
    done

    # 9. DFS 复制子节点
    local tr_max_id=1
    while ((${#tr_stack[@]})) ; do
        local tr_cur=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'
        ((tr_max_id=(tr_cur>tr_max_id)?tr_cur:tr_max_id))

        tr_new[$tr_cur]=1
        if [[ -n "${tr_t[$tr_cur.children]}" ]] ; then
            tr_new[$tr_cur.children]=${tr_t[$tr_cur.children]}
        fi

        # 这里的 key 不能直接复制老树的，需要剪掉前缀
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

    # 设置最大的 max_index
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

    # 1. tr_prefix 必须合法或者是 空key(遍历树根)
    [[ -n "$tr_prefix" ]] && {
        trie_key_is_invalid "$tr_prefix" || return $?
    }

    # 2. 找到 tr_prefix 对应的节点 ID
    local tr_node_id
    tr_node_id=${|_trie_token_to_node_id "$1" "$tr_prefix";} || return $?

    # 3. 读取 tr_children
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

# 这只是一个范例, 用于演示 trie_walk 的回调函数，处理整棵树
# callback <type> <token> <full_key> <node_id>
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

    # 栈：保存 (prefix node_id)
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

            # 判断 leaf / tree
            if [[ -n "${tr_t[$tr_child_id.key]}" ]]; then
                tr_type="leaf"
                tr_full_key="${tr_t["$tr_child_id.key"]}"
                tr_value="${tr_t["$tr_full_key"]}"
            else
                tr_type="tree"
                tr_value=''
                tr_full_key="${tr_prefix}${tr_tk}$S"
            fi
            
            # 调用回调
            "$tr_callback" "$tr_type" "$tr_tk" "$tr_full_key" "$tr_child_id" "$tr_node_id" "$tr_value"

            # 如果是 tree，压栈继续 DFS
            if [[ $tr_type == tree ]]; then
                tr_stack+=("$tr_full_key" "$tr_child_id")
            fi
        done
    done
}

# 这个函数意义不大，强迫症可以使用，作用是把树内部的ID从1开始重新编号
# 用于树操作久了后ID很多空洞的情况
# 但是其实意义不大
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

    # 单独保存根节点的映射
    tr_id_map[$TR_ROOT_ID]=1

    # 创建一颗新树
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

    # 更新最大索引
    tr_new[max_index]=$tr_new_id
    
    # 返回新树
    REPLY=${tr_new[*]@K}
    return ${TR_RET_ENUM_OK}
}

trie_equals ()
{
    local -n tr_1=$1 tr_2=$2
    local tr_ok=1

    # 遍历 tr_1，检查 tr_2
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

    # 遍历 tr_2，检查 tr_1
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

