#!/usr/bin/env bash

. ../../src/bashlib/my_class.sh
. ../../src/bashlib/meta.sh
. ../libs/test_utils.sh

# test fn_map_inplace
test_case1 ()
{
    local -A "demo_tree=(${|new_my_class "demo_tree" "yy" '5' 10;})"

    ${demo_tree[{print_self}$X]}
    ${demo_tree[{haha}$X]}
    ${demo_tree[{cut_plus}$X]}
    ${demo_tree[{print_self}$X]}

    local -A "demo_tree_new=(${demo_tree[@]@K})"
    rebind_self demo_tree_new

    ${demo_tree_new[{print_self}$X]}
    ${demo_tree_new[{haha}$X]}
}

eval -- "${|AS_RUN_TEST_CASES;}"

