#!/usr/bin/env bash

. ../../src/bashlib/my_class.sh
. ../../src/bashlib/meta.sh
. ../libs/test_utils.sh

test_case1 ()
{
    declare -gA "root_obj=(${|trie_init "$TR_TYPE_OBJ";})"
    new_my_class "root_obj" 1 '' 'value1' 'value2' '0' 

    # ${root_obj[{print_self}$X]}

    ${root_obj[{haha}$X]}
    ${root_obj[{cut_plus}$X]}
    # ${root_obj[{print_self}$X]}
    
    local i
    time {
        for i in {0..2} ; do
            # Add a new element
            local -a "new_element_info=(${|trie_push_leaf root_obj "{ELEMENTS}$X" "$TR_VALUE_NULL_OBJ";})"
            new_my_class "root_obj" "${new_element_info[@]}" 'new1_value1' 'new1_value2' '3'

            # ${root_obj[${new_element_info[1]}{print_self}$X]}
        done
    }

    # Delete the last element
    # ${root_obj[{delete_last_element}$X]}
    ${root_obj[{print_self}$X]}

    # declare -p root_obj >root_qq.txt
}

eval -- "${|AS_RUN_TEST_CASES;}"

