#!/usr/bin/env bash
#
# 复杂纯字典树：
#   - 分支 + 多级嵌套
#   - x_walk_dict_tree 与 x_walk 的输出逐行一致
#   - 节点不遗漏
#   - 父节点一定先于子节点（拓扑序）

. ../../src/bashlib/x.sh

x_init "$X_TYPE_OBJ"
eval "declare -A DW=($REPLY)"

leaves=(
    "{a}$X{b}$X{c}$X"
    "{a}$X{b}$X{d}$X"
    "{a}$X{e}$X{f}$X{g}$X"
    "{h}$X{i}$X"
    "{h}$X{j}$X{k}$X{l}$X{m}$X"
    "{n}$X{o}$X"
    "{n}$X{p}$X{q}$X"
)
for leaf in "${leaves[@]}" ; do
    x_insert_dict DW "$leaf" "$X_VALUE_NULL" || { echo "insert failed: $leaf" ; exit 1 ; }
done

probe () {
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}

x_walk DW '' probe > /tmp/qq_walk_generic_complex.txt
x_walk_dict_tree DW '' probe > /tmp/qq_walk_dict_complex.txt

if ! diff -u /tmp/qq_walk_generic_complex.txt /tmp/qq_walk_dict_complex.txt ; then
    echo 'FAIL: walk outputs differ'
    exit 1
fi

declare -A expected=() actual=() seen=()
for leaf in "${leaves[@]}" ; do
    cur=''
    rest=$leaf
    while [[ -n "$rest" ]] ; do
        token=${rest%%"$X"*}
        cur+="$token$X"
        expected[$cur]=1
        rest=${rest#*"$X"}
    done
done

while IFS='|' read -r kind idx idx_full value token full node parent ; do
    [[ -n "$full" ]] || continue
    actual[$full]=1
    trim=${full%"$X"}
    token=${trim##*"$X"}
    if [[ "$trim" == *"$X"* ]] ; then
        parent_path=${trim%"$X$token"}
        parent_path+="$X"
    else
        parent_path=''
    fi
    if [[ -n "$parent_path" && -z "${seen[$parent_path]+_}" ]] ; then
        echo "FAIL: parent before child violated: $parent_path -> $full"
        exit 1
    fi
    seen[$full]=1
done < /tmp/qq_walk_dict_complex.txt

if (( ${#actual[@]} != ${#expected[@]} )) ; then
    echo "FAIL: node count expected=${#expected[@]} actual=${#actual[@]}"
    exit 1
fi

for key in "${!expected[@]}" ; do
    if [[ -z "${actual[$key]+_}" ]] ; then
        echo "FAIL: missing node $key"
        exit 1
    fi
done

echo "PASS: complex dict tree, ${#actual[@]} nodes, topological order"

# 纯字典遍历器遇到数组必须显式失败，不能静默漏掉子节点。
x_insert_dict DW "{arr}$X" "$X_VALUE_NULL_ARR" >/dev/null 2>&1
x_insert DW "{arr}$X[0]$X" 'zero' >/dev/null 2>&1
out=$(x_walk_dict_tree DW '' probe 2>&1)
rc=$?
if (( rc == 0 )) ; then
    echo 'FAIL: x_walk_dict_tree accepted an array node'
    exit 1
fi
printf '%s\n' "$out" | grep -q 'array node is not supported' || {
    echo 'FAIL: missing array rejection message'
    exit 1
}
echo 'PASS: array node rejected explicitly'
