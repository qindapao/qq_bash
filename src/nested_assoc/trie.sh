#!/usr/bin/env bash

((_TRIE_IMPORTED++)) && return 0

TRIE_RET_ENUM_OK=0
TRIE_RET_ENUM_KEY_IS_TREE=1
TRIE_RET_ENUM_KEY_IS_LEAF=2
TRIE_RET_ENUM_KEY_IS_NOTFOUND=3
TRIE_RET_ENUM_KEY_IS_NULL=8
TRIE_RET_ENUM_KEY_UP_LEV_HAVE_LEAF=9

# (root)
#  ├── a
#  │    ├── b   (leaf)
#  │    └── c   (leaf)
#  └── x
#       └── y
#            └── z   (leaf)
# ----------------------------------------
# - 根节点（ID=1）
# T[max_index]=10
# T[1] = 1
# T[1.children] = "a x"
# T[1.child.a] = 2
# T[1.child.x] = 10
# ----------------------------------------
# - 分支 1：a
# 节点 a（ID=2）
# T[2] = 1
# T[2.children] = "b c"
# T[2.child.b] = 3
# T[2.child.c] = 5
# 
# a → b（ID=3）
# 
# T[3] = 1
# T[3.children] = ""
# T[3.key] = "a${SEP}b${SEP}"
# 这是一个叶子节点。
# 
# a → c（ID=5）
# T[5] = 1
# T[5.children] = ""
# T[5.key] = "a${SEP}c${SEP}"
# 也是一个叶子节点。
# ----------------------------------------
# - 分支 2：x
# 节点 x（ID=10
# T[10] = 1
# T[10.children] = "y"
# T[10.child.y] = 11
# 
# 
# x → y（ID=11）
# T[11] = 1
# T[11.children] = "z"
# T[11.child.z] = 12
# 
# 
# x → y → z（ID=12）
# T[12] = 1
# T[12.children] = ""
# T[12.key] = "x${SEP}y${SEP}z${SEP}"
# 
# 1. 分叉就是 children 里有多个 token
# 
# 例如：
# T[2.children] = "b c"
# 
# 2. 叶子节点的 children=""，但 key 非空
# 例如：
# T[3.children] = ""
# T[3.key] = "a${SEP}b${SEP}"     
# 
# 
# 3. 中间节点没有 key，但有 children
# 例如：
# 
# T[10.children] = "y"
# T[10.key] = ""   # 不是叶子
# 
# children 非空 → 中间节点
# children 空 + key 非空 → 叶子
# children 空 + key 空 → 空节点（可删除）
#
# children 甚至可以排序，这样可以模拟数组和字典的嵌套

SEP=$'\034'
TRIE_ROOT_ID=1

# T[node.type] = "arr" | "obj" | "str" | "number" | "null" | "true" | "false"

# 叶子节点
# T[node.children] = ""
# T[node.key] = "fullkey"
#
# 非叶子节点
# T[node.children] = "a b c"
# T[node.key] = ""   # 非叶子不能有 key
# 
# 每个节点包含的内容
# T[node] = 1
# T[node.children] = "token1 token2 ..."
# T[node.child.token] = childID
# T[node.key] = "fullkey"   # 仅叶子有
# 

_split_tokens ()
{
    local tokens_str=$1
    local -a tokens=()
    while [[ -n "$tokens_str" ]] ; do
        tokens+=("${tokens_str%%"$SEP"*}")
        tokens_str="${tokens_str#*"$SEP"}"
    done
    REPLY="${tokens[*]@Q}"
}

trie_init ()
{
    local -A t=()
    local j_type=$1
    t[$TRIE_ROOT_ID]=1
    t[$TRIE_ROOT_ID.children]=''
    t[$TRIE_ROOT_ID.key]=''

    # 下一个可用节点 ID
    t[max_index]=2
    REPLY=${t[*]@K}
}

# 子树挂接
trie_graft ()
{
    :
}

# :TODO: 把添加的过程用asciio画出来
trie_insert ()
{
    eval -- local -A t=($1)
    local full_key=$2
    local value=$3

    local token child_key child_id
    local -a tokens
    eval -- tokens=(${|_split_tokens "$full_key";})
    local node=${TRIE_ROOT_ID}

    for token in "${tokens[@]}" ; do
        # 上层不能是叶子
        [[ -n "${t[$node.key]}" ]] && {
            REPLY=$1
            return ${TRIE_RET_ENUM_KEY_UP_LEV_HAVE_LEAF}
        }

        child_key="$node.child.$token"
        child_id="${t[$child_key]}"

        # 子节点不存在 -> 创建
        if [[ -z "$child_id" ]] ; then
            child_id="${t[max_index]}"
            ((t[max_index]++))
            t[$child_id]=1
            t[$child_id.children]=''
            t[$child_id.key]=''

            # 加入 children 列表
            t[$node.children]+="$token$SEP"

            # children 排序
            eval -- local -a children=(${|_split_tokens "${t[$node.children]}";})
            if [[ "${t[$node.children]//"$SEP"/}" == *[^0-9]* ]] ; then
                # 非数字使用 字典 序
                # :TODO: 以后可以使用 qsort 内置命令提高效率
                eval -- children=( ${ printf "%s\n" "${children[@]@Q}" | sort;} )
            else
                # 数字键使用 数字 序
                children=( ${ printf "%s\n" "${children[@]}" | sort -n;} )
            fi
            printf -v t[$node.children] "%s$SEP" "${children[@]}"
            t["$child_key"]=$child_id
        fi

        node=$child_id
    done

    # 写入叶子 key
    t[$node.key]=$full_key
    t["V$SEP$full_key"]=$value

    REPLY="${t[*]@K}"
    return 0
}

trie_dump()
{
    eval -- local -A t=($1)
    local node=${2:-$TRIE_ROOT_ID}
    local indent=${3:-""}

    # 遍历 children
    eval -- local -a children=(${|_split_tokens "${t[$node.children]}";})

    for token in "${children[@]}"; do
        local child_id="${t[$node.child.$token]}"

        if [[ -n "${t[$child_id.key]}" ]]; then
            local key=${t[$child_id.key]}
            local value=${t["V$SEP$key"]}
            printf "%s%s(%s) => %s\n" \
                "$indent" "$token" "$child_id" "$value"
        else
            printf "%s%s(%s)\n" "$indent" "$token" "$child_id"
        fi

        trie_dump "${t[*]@K}" "$child_id" "    $indent"
    done
}

# :TODO: 把删除的过程用asciio画出来
trie_delete()
{
    eval -- local -A t=($1)
    local full_key=$2

    # 1. 拆分 token
    eval -- local -a tokens=(${|_split_tokens "$full_key";})

    # 2. 路径查找
    local node=$TRIE_ROOT_ID
    local -a path_nodes=($node)
    # 与 path_nodes 对齐
    local -a path_tokens=("")

    local token
    for token in "${tokens[@]}" ; do
        [[ -z "$token" ]] && continue
        local child_id="${t[$node.child.$token]}"
        [[ -z "$child_id" ]] && {
            REPLY=$1
            return ${TRIE_RET_ENUM_KEY_IS_NOTFOUND}
        }
        path_nodes+=("$child_id")
        path_tokens+=("$token")
        node=$child_id
    done

    # ----------------------------------------------------
    # 3. 判断是叶子删除还是“中间节点（子树）删除”
    # ----------------------------------------------------

    local has_children=""
    [[ -n "${t[$node.children]}" ]] && has_children=1

    # 3.1 先删当前节点自身挂的 value（无论是叶子还是中间节点，都可能有值）
    unset t["V$SEP$full_key"]
    unset t[$node.key]

    # 3.2 如果是中间节点：删除整个子树（包括所有 value）
    if [[ -n "$has_children" ]]; then
        # 用一个栈做 DFS
        local -a stack=("$node")

        while ((${#stack[@]} > 0)); do
            local cur=${stack[-1]}
            unset 'stack[-1]'

            # 取 children token
            eval -- local -a children=(${|_split_tokens "${t[$cur.children]}";})

            local tk cid
            for tk in "${children[@]}"; do
                [[ -z "$tk" ]] && continue
                cid="${t[$cur.child.$tk]}"

                # 入栈继续删
                [[ -n "$cid" ]] && stack+=("$cid")

                # 清理 child 映射
                unset t[$cur.child.$tk]
            done

            # 如果当前节点本身是叶子，也可能挂 value
            if [[ -n "${t[$cur.key]}" ]]; then
                unset t["V$SEP${t[$cur.key]}"]
                unset t[$cur.key]
            fi

            # 清理 children 字段和节点标记
            unset t[$cur.children]
            unset t[$cur]
        done
    fi

    # ----------------------------------------------------
    # 4. 自底向上剪枝（从 full_key 对应节点的父开始）
    # ----------------------------------------------------

    local i last child parent
    last=$((${#path_nodes[@]} - 1))

    for ((i=last; i>0; i--)); do
        child=${path_nodes[$i]}
        parent=${path_nodes[$((i-1))]}
        token=${path_tokens[$i]}

        # 中间节点删除时，child 可能已经在上面的 DFS 里被删掉了
        # 如果这个 child 已经没有任何结构信息了，就视为“可剪”
        if [[ -z "${t[$child.key]}" && -z "${t[$child.children]}" && -z "${t[$child]}" ]]; then
            :
        else
            # 如果 child 还有 children 或 key，则不能再继续剪
            if [[ -n "${t[$child.key]}" || -n "${t[$child.children]}" ]]; then
                break
            fi
        fi

        # 删除 child 节点（如果还在的话）
        unset t[$child]
        unset t[$child.key]
        unset t[$child.children]

        # 从 parent.children 中移除 token
        eval -- local -a children=(${|_split_tokens "${t[$parent.children]}";})

        local new=()
        local x
        for x in "${children[@]}"; do
            [[ "$x" != "$token" ]] && new+=("$x")
        done

        if [[ ${#new[@]} -eq 0 ]]; then
            t[$parent.children]=''
        else
            printf -v t[$parent.children] "%s$SEP" "${new[@]}"
        fi

        # 删除 child 映射
        unset t[$parent.child.$token]
    done

    REPLY="${t[*]@K}"
    return 0
}



eval -- declare -A t=(${|trie_init;})

eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}b${SEP}c${SEP}" "value1";})

eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}x${SEP}" "value2";})

eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}m${SEP}" "value3";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}b${SEP}d${SEP}" "value4";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}b${SEP}e${SEP}" "value5";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}b${SEP}e x k${SEP}" "value6";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}0${SEP}" "ka0";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}1${SEP}" "ka1";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}2${SEP}" "ka2";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}3${SEP}" "ka3";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}8${SEP}" "ka8";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}9${SEP}" "ka9";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}10${SEP}" "ka10";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}6${SEP}" "ka6";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}11${SEP}" "ka11";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}4${SEP}" "ka4";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}5${SEP}" "ka5";})
eval -- t=(${|trie_insert "${t[*]@K}" "a${SEP}a${SEP}7${SEP}" "ka7";})

declare -p t
trie_dump "${t[*]@K}"







