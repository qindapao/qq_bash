#!/usr/bin/env bash

. ../../src/bashlib/my_class.sh
. ../../src/bashlib/meta.sh
. ../libs/test_utils.sh

# test fn_map_inplace
test_case1 ()
{
    local -A "demo_tree=(${|new_my_class "demo_tree" "yy" '5' 10;})"

    ${demo_tree[{print_self}$S]}
    ${demo_tree[{haha}$S]}
    ${demo_tree[{cut_plus}$S]}
    ${demo_tree[{print_self}$S]}

    local -A "demo_tree_new=(${demo_tree[@]@K})"
    rebind_self demo_tree_new

    ${demo_tree_new[{print_self}$S]}
    ${demo_tree_new[{haha}$S]}
}

eval -- "${|AS_RUN_TEST_CASES;}"

