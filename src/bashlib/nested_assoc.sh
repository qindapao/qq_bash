((_NESTED_ASSOC_IMPORTED++)) && return 0

# 变量前缀 na_ 外部用户变量不能以此命名


# 当有递归情况发生时:
# 安全的情况是，引用的始终是用户传进来的变量名。而不能是递归函数自己的变量名
# 如果是递归函数自己的变量名，那么传递到下层去的时候一定会冲突的。

# :TODO: The efficiency of key polling may not be high. You can consider using
#   a dictionary tree to optimize it.
# trie[lev1${SEP}]=(lev2-1${SEP} lev2-2${SEP})
# trie[lev1${SEP}lev1-1${SEP}]=(lev3${SEP})
#
# In fact, I feel that it is not necessary anymore, just use JSON directly.
#
# nested assoc sub sep
# SEP needs to wrap the tail of the key to eliminate ambiguity
SEP=$'\034'
# 如果想要绝对安全可以定义下面的分隔符,防止极端碰撞
# SEP=$'\034'$'\035'$'\036'$'\037'
NA_RET_ENUM_OK=0
NA_RET_ENUM_KEY_IS_TREE=1
NA_RET_ENUM_KEY_IS_LEAF=2
NA_RET_ENUM_KEY_IS_NOTFOUND=3
NA_RET_ENUM_KEY_IS_NULL=8
NA_RET_ENUM_KEY_UP_LEV_HAVE_LEAF=9

na_gk ()
{
    eval -- 'printf "%q " "${!'$1'[@]}"'
}

na_tree_node_type ()
{
    local na_base_key=$2 na_key
    [[ -z "$na_base_key" ]] && {
        return ${NA_RET_ENUM_KEY_IS_NULL}
    }

    local -n na_base_tree=$1

    [[ -v na_base_tree["$na_base_key"] ]] && return ${NA_RET_ENUM_KEY_IS_LEAF}

    for na_key in "${!na_base_tree[@]}" ; do
        [[ "$na_key" == "$na_base_key"* ]] && return ${NA_RET_ENUM_KEY_IS_TREE}
    done

    return ${NA_RET_ENUM_KEY_IS_NOTFOUND}
}

na_tree_delete ()
{
    local na_base_key=$2 na_key
    [[ -z "$na_base_key" ]] && {
        return ${NA_RET_ENUM_KEY_IS_NULL}
    }
    local -n na_base_tree=$1
    
    for na_key in "${!na_base_tree[@]}" ; do
        [[ "$na_key" == "${na_base_key}"* ]] && {
            unset -v 'na_base_tree["$na_key"]'
        }
    done
    return ${NA_RET_ENUM_OK}
}

na_tree_get ()
{
    local na_base_key=$2
    [[ -z "$na_base_key" ]] && return ${NA_RET_ENUM_KEY_IS_NULL}
    local na_key na_sub_key
    local -n na_base_tree=$1
    
    for na_key in "${!na_base_tree[@]}" ; do
        [[ "$na_key" == "${na_base_key}"* ]] && {
            na_sub_key=${na_key#"$na_base_key"}
            [[ -n "$na_sub_key" ]] && {
                REPLY+=" ${na_sub_key@Q}"
                REPLY+=" ${na_base_tree[$na_key]@Q}"
            }
        }
    done
    return ${NA_RET_ENUM_OK}
}

na_tree_get_len ()
{
    :
}

na_tree_walk ()
{
    local na_base_tree_var=$1
    local -n na_base_tree=$1
    local na_base_key="$2"

    local IFS=$'\n'
    local na_type_key_tuple key_q na_key na_key_type

    for na_type_key_tuple in ${|na_tree_iter "$na_base_tree_var" "$na_base_key" ;} ; do
        eval -- set -- $na_type_key_tuple ; na_key_type=$1 na_key=$2
        # IFS=$'\n'
        
        if [[ "$na_key_type" == leaf ]] ; then
            printf "%b => %s\n" "${na_base_key}${na_key}${SEP}" "${na_base_tree["${na_base_key}${na_key}${SEP}"]}" 
        else
            na_tree_walk "$na_base_tree_var" "${na_base_key}${na_key}${SEP}"
        fi
    done
}

# Key iterator, returns a list of
# (key[Qstring] type[Normal_string])
# The reason why Q string protection is used is to prevent newline characters
# from appearing in the key.
# The caller needs to first set IFS=$'\n' Then do Q string eval reduction when using it
na_tree_iter ()
{
    local -n na_base_tree=$1
    local na_base_key=$2
    local na_key na_sub_key
    local -A na_seen=()
    local na_node_type=''

    for na_key in "${!na_base_tree[@]}"; do
        if [[ -z "$na_base_key" ]]; then
            na_sub_key=${na_key%%"$SEP"*}
        else
            [[ "$na_key" != "$na_base_key"* ]] && continue
            na_sub_key=${na_key#"$na_base_key"}
            # Just take down one level
            na_sub_key=${na_sub_key%%"$SEP"*}
        fi

        [[ -n "$na_sub_key" ]] && [[ ! -v na_seen["$na_sub_key"] ]] && {
            [[ -v na_base_tree["${na_base_key}${na_sub_key}${SEP}"] ]] && na_node_type='leaf' || na_node_type='tree'
            REPLY+="${REPLY:+$'\n'}${na_node_type} ${na_sub_key@Q}"
            na_seen[$na_sub_key]=1
        }
    done
}

na_tree_dump ()
{
    local print_name="$1"
    local -A "print_tree=($2)"
    local prefix="$3" indent_cnt="${4:-4}" key
    local -A strip_tree=()

    printf "%s\n" "${print_name} =>"
    local -a sorted_keys=("${!print_tree[@]}")
    eval -- sorted_keys=($(printf "%s\n" "${sorted_keys[@]@Q}" | sort))

    local new_indent ; printf -v new_indent "%*s" "$indent_cnt" ""

    _na_tree_dump "$2" "${sorted_keys[*]@Q}" "$prefix" "$new_indent" "$indent_cnt"
}

na_tree_add_leaf ()
{
    local na_base_key=$2

    [[ -z "$na_base_key" ]] && {
        return ${NA_RET_ENUM_KEY_IS_NULL}
    }

    local -n na_base_tree=$1
    local na_leaf=$3

    # Check if there are leaves in the superior level
    local na_prefix=${na_base_key%"$SEP"}
    while [[ "$na_prefix" == *"$SEP"* ]] ; do
        local na_parent="${na_prefix%$SEP*}$SEP"
        [[ -v na_base_tree["$na_parent"] ]] && {
            return ${NA_RET_ENUM_KEY_UP_LEV_HAVE_LEAF}
        }
        na_prefix=${na_prefix%"$SEP"*}
    done 

    na_tree_delete "${1}" "$na_base_key"
    na_base_tree[$na_base_key]=$na_leaf

    return ${NA_RET_ENUM_OK}
}

na_tree_add_sub ()
{
    local na_base_key=$2

    [[ -z "$na_base_key" ]] && {
        return ${NA_RET_ENUM_KEY_IS_NULL}
    }

    local -n na_base_tree=$1
    local -n na_sub_tree=$3

    # Check if there are leaves in the superior level
    local na_prefix=${na_base_key%"$SEP"}
    while [[ "$na_prefix" == *"$SEP"* ]] ; do
        local na_parent="${na_prefix%$SEP*}$SEP"
        [[ -v na_base_tree["$na_parent"] ]] && {
            return ${NA_RET_ENUM_KEY_UP_LEV_HAVE_LEAF}
        }
        na_prefix=${na_prefix%"$SEP"*}
    done 

    na_tree_delete "$1" "$na_base_key"

    local na_sub_key ; for na_sub_key in "${!na_sub_tree[@]}" ; do
        na_base_tree["${na_base_key}${na_sub_key}"]=${na_sub_tree["$na_sub_key"]}
    done

    return ${NA_RET_ENUM_OK}
}

# :TODO: Double-width aligned display of Chinese has not been considered for
# the time being.

_na_tree_dump ()
{
    local -A "print_tree=($1)"
    local -a "sorted_keys=($2)"
    local prefix="$3" indent="$4"
    local indent_cnt="$5"
    local -A subkeys=()
    local -a subkeys_order=()
    local fullkey rest subkey
    local -A rest_tree=()
    local -a rest_sorted_keys=()

    # Collect the leaves and values of the current layer,
    # and the subkey set of the next layer
    local index
    for index in "${!sorted_keys[@]}"; do
        fullkey=${sorted_keys[$index]}
        if [[ -z "$prefix" || "$fullkey" == "$prefix"* ]]; then
            rest=${fullkey#"$prefix"}
            if [[ "${rest%$SEP}" == *"$SEP"* ]] ; then
                subkey="${rest%%"$SEP"*}"
                [[ -z "${subkeys[$subkey]}" ]] && {
                    subkeys["$subkey"]=1
                    subkeys_order+=("$subkey")
                }
                rest_tree["$fullkey"]=${print_tree[$fullkey]}
                rest_sorted_keys+=("$fullkey")
            else
                rest=${fullkey%"$SEP"}
                rest=${rest##*"$SEP"}
                local indent_leaf_value=${rest##*$'\n'}
                indent_leaf_value=${indent_leaf_value//?/ }
                indent_leaf_value+="${indent}    "
                printf "%s\n" "${indent}${rest//$'\n'/$'\n'"$indent"} => ${print_tree[$fullkey]//$'\n'/$'\n'"$indent_leaf_value"}"
            fi
        else
            rest_tree["$fullkey"]=${print_tree[$fullkey]}
            rest_sorted_keys+=("$fullkey")
        fi
    done

    local new_indent ; printf -v new_indent "%*s" "$indent_cnt" ""
    if ((${#subkeys_order[@]})); then
        for subkey in "${subkeys_order[@]}" ; do
            printf "%s\n" "${indent}${subkey//$'\n'/$'\n'"$indent"} =>"
            _na_tree_dump "${rest_tree[*]@K}" "${rest_sorted_keys[*]@Q}" "${prefix}${subkey}${SEP}" "${new_indent}${indent}" "$indent_cnt"
        done
    fi
}

return 0

