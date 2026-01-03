#!/usr/bin/env bash

. ../../src/bashlib/my_class.sh
. ../../src/bashlib/meta.sh
. ../libs/test_utils.sh

# test fn_map_inplace
test_case1 ()
{
    local -A "demo_tree=(${|new_my_class "demo_tree" "yy" '5' 10;})"

    ${demo_tree[{FN}$S{print_self}$S]}
    ${demo_tree[{FN}$S{haha}$S]}
    ${demo_tree[{FN}$S{cut_plus}$S]}
    ${demo_tree[{FN}$S{print_self}$S]}

    local -A "demo_tree_new=(${demo_tree[@]@K})"
    rebind_self demo_tree_new

    ${demo_tree_new[{FN}$S{print_self}$S]}
    ${demo_tree_new[{FN}$S{haha}$S]}
}

eval -- "${|AS_RUN_TEST_CASES;}"

