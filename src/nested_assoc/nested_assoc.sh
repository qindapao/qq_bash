#!/usr/bin/env bash

((_NESTED_ASSOC_IMPORTED++)) && return 0

# nested assoc sub sep
# SEP needs to wrap the tail of the key to eliminate ambiguity
SEP=$'\034'
NA_RET_ENUM_OK=0
NA_RET_ENUM_KEY_IS_TREE=1
NA_RET_ENUM_KEY_IS_LEAF=2
NA_RET_ENUM_KEY_IS_NOTFOUND=3
NA_RET_ENUM_KEY_IS_NULL=8
NA_RET_ENUM_KEY_UP_LEV_HAVE_LEAF=9

# declare -A nested_assoc_tmp=()
# - add leaf key(Check for empty keys. Empty keys are not allowed to be inserted.)
# nested_assoc_tmp["key1${SEP}key2${SEP}key3${SEP}"]="something"
# - delete leaf key
# unset -v nested_assoc_tmp["key1${SEP}key2${SEP}key3${SEP}"]
# 直接操作叶子键前最好先检查下要添加的叶子键如果是子树是不能直接添加的

# $1: 需要获取键Q字符串列表的树变量名
na_gk ()
{
    eval -- 'printf "%q " "${!'$1'[@]}"'
}

na_tree_node_type ()
{
    local base_key=$2 key
    [[ -z "$base_key" ]] && {
        return ${NA_RET_ENUM_KEY_IS_NULL}
    }

    eval -- local -A base_tree=($1)

    [[ -v base_tree["$base_key"] ]] && return ${NA_RET_ENUM_KEY_IS_LEAF}

    for key in "${!base_tree[@]}" ; do
        [[ "$key" == "$base_key"* ]] && return ${NA_RET_ENUM_KEY_IS_TREE}
    done

    return ${NA_RET_ENUM_KEY_IS_NOTFOUND}
}

na_tree_delete ()
{
    local base_key=$2 key
    [[ -z "$base_key" ]] && {
        REPLY=$1
        return ${NA_RET_ENUM_KEY_IS_NULL}
    }
    
    eval -- local -A base_tree=($1)
    
    for key in "${!base_tree[@]}" ; do
        [[ "$key" != "${base_key}"* ]] && {
            REPLY+=" ${key@Q}"
            REPLY+=" ${base_tree[$key]@Q}"
        }
    done
    return ${NA_RET_ENUM_OK}
}

# $?
# 0 成功获取
# 1 键为空
na_tree_get ()
{
    local base_key=$2
    [[ -z "$base_key" ]] && return ${NA_RET_ENUM_KEY_IS_NULL}
    local key sub_key
    eval -- local -A base_tree=($1)
    
    for key in "${!base_tree[@]}" ; do
        [[ "$key" == "${base_key}"* ]] && {
            sub_key=${key#"$base_key"}
            [[ -n "$sub_key" ]] && {
                REPLY+=" ${sub_key@Q}"
                REPLY+=" ${base_tree[$key]@Q}"
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
    local tree_q="$1"
    eval -- local -A tree=($tree_q)
    local base_key="$2"

    local IFS=$'\n'
    local type_key_tuple key_q key key_type

    for type_key_tuple in ${|na_tree_iter "$tree_q" "$base_key" ;} ; do
        IFS=' ' ; eval -- set -- $type_key_tuple
        key_type=$1 key=$2
        # IFS=$'\n'
        
        if [[ "$key_type" == leaf ]] ; then
            printf "%b => %s\n" "${base_key}${key}${SEP}" "${tree["${base_key}${key}${SEP}"]}" 
        else
            na_tree_walk "$tree_q" "${base_key}${key}${SEP}"
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
    eval -- local -A base_tree=($1)
    local base_key=$2
    local key sub_key
    local -A seen=()
    local node_type=''

    REPLY=""
    for key in "${!base_tree[@]}"; do
        if [[ -z "$base_key" ]]; then
            sub_key=${key%%"$SEP"*}
        else
            [[ "$key" != "$base_key"* ]] && continue
            sub_key=${key#"$base_key"}
            # Just take down one level
            sub_key=${sub_key%%"$SEP"*}
        fi

        [[ -n "$sub_key" ]] && [[ ! -v seen["$sub_key"] ]] && {
            [[ -v base_tree["${base_key}${sub_key}${SEP}"] ]] && node_type='leaf' || node_type='tree'
            REPLY+="${REPLY:+$'\n'}${node_type} ${sub_key@Q}"
            seen[$sub_key]=1
        }
    done
}

na_tree_print ()
{
    local print_name="$1"
    eval -- local -A print_tree=($2)
    local prefix="$3" indent_cnt="${4:-4}" key
    local -A strip_tree=()

    echo "${print_name} =>"
    local -a sorted_keys=("${!print_tree[@]}")
    eval -- sorted_keys=($(printf "%s\n" "${sorted_keys[@]@Q}" | sort))

    local new_indent ; printf -v new_indent "%*s" "$indent_cnt" ""

    _na_tree_print "$2" "${sorted_keys[*]@Q}" "$prefix" "$new_indent" "$indent_cnt"
}

na_tree_add_leaf ()
{
    local base_key=$2

    [[ -z "$base_key" ]] && {
        REPLY=$1
        return ${NA_RET_ENUM_KEY_IS_NULL}
    }

    eval -- local -A base_tree=($1)
    local leaf=$3

    # Check if there are leaves in the superior level
    local prefix=${base_key%"$SEP"}
    while [[ "$prefix" == *"$SEP"* ]] ; do
        local parent="${prefix%$SEP*}$SEP"
        [[ -v base_tree["$parent"] ]] && {
            REPLY=$1
            return ${NA_RET_ENUM_KEY_UP_LEV_HAVE_LEAF}
        }
        prefix=${prefix%"$SEP"*}
    done 

    REPLY=${|na_tree_delete "${base_tree[*]@K}" "$base_key" ;}
    REPLY+=" ${base_key@Q} ${leaf@Q}"

    return ${NA_RET_ENUM_OK}
}

na_tree_add_sub ()
{
    local base_key=$2

    [[ -z "$base_key" ]] && {
        REPLY=$1
        return ${NA_RET_ENUM_KEY_IS_NULL}
    }

    eval -- local -A base_tree=($1)
    eval -- local -A sub_tree=($3)

    # Check if there are leaves in the superior level
    local prefix=${base_key%"$SEP"}
    while [[ "$prefix" == *"$SEP"* ]] ; do
        local parent="${prefix%$SEP*}$SEP"
        [[ -v base_tree["$parent"] ]] && {
            REPLY=$1
            return ${NA_RET_ENUM_KEY_UP_LEV_HAVE_LEAF}
        }
        prefix=${prefix%"$SEP"*}
    done 

    REPLY=${|na_tree_delete "${base_tree[*]@K}" "$base_key" ;}

    local sub_key ; for sub_key in "${!sub_tree[@]}" ; do
        : "${base_key}${sub_key}" ; REPLY+=" ${_@Q}"
        REPLY+=" ${sub_tree[$sub_key]@Q}"
    done

    return ${NA_RET_ENUM_OK}
}

# :TODO: 暂时没有考虑中文的双宽对齐显示
_na_tree_print ()
{
    eval -- local -A print_tree=($1)
    eval -- local -a sorted_keys=($2)
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
                local indent_leaf_value
                indent_leaf_value=${rest%%$'\n'*}
                indent_leaf_value=${indent_leaf_value//?/ }
                indent_leaf_value+="${indent}    "
                echo "${indent}${rest//$'\n'/$'\n'"$indent"} => ${print_tree[$fullkey]//$'\n'/$'\n'"$indent_leaf_value"}"
            fi
        else
            rest_tree["$fullkey"]=${print_tree[$fullkey]}
            rest_sorted_keys+=("$fullkey")
        fi
    done

    local new_indent ; printf -v new_indent "%*s" "$indent_cnt" ""
    if ((${#subkeys_order[@]})); then
        for subkey in "${subkeys_order[@]}" ; do
            echo "${indent}${subkey//$'\n'/$'\n'"$indent"} =>"
            _na_tree_print "${rest_tree[*]@K}" "${rest_sorted_keys[*]@Q}" "${prefix}${subkey}${SEP}" "${new_indent}${indent}" "$indent_cnt"
        done
    fi
}

