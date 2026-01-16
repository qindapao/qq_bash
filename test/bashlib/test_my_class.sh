#!/usr/bin/env bash

. ../../src/bashlib/my_class.sh
. ../../src/bashlib/meta.sh
. ../libs/test_utils.sh

test_case1 ()
{
    declare -gA "root_obj=(${|trie_init "$TR_TYPE_OBJ";})"
    new_my_class "root_obj" 1 '' 'value1' 'value2' '0' 

    ${root_obj[{print_self}$X]}

    ${root_obj[{haha}$X]}
    ${root_obj[{cut_plus}$X]}
    ${root_obj[{print_self}$X]}
    
    # Add a new element
    local -a "new_element_info=(${|trie_push_leaf root_obj "{ELEMENTS}$X" "$TR_VALUE_NULL_OBJ";})"
    new_my_class "root_obj" "${new_element_info[@]}" 'new1_value1' 'new1_value2' '3'

    local -a "new_element_info=(${|trie_push_leaf root_obj "{ELEMENTS}$X" "$TR_VALUE_NULL_OBJ";})"
    new_my_class "root_obj" "${new_element_info[@]}" 'new2_value1' 'new2_value2' '3'

    local -a "new_element_info=(${|trie_push_leaf root_obj "{ELEMENTS}$X" "$TR_VALUE_NULL_OBJ";})"
    new_my_class "root_obj" "${new_element_info[@]}" 'new3_value1' 'new3_value2' '3'

    # Delete the last element
    ${root_obj[{delete_last_element}$X]}
    ${root_obj[{print_self}$X]}
}

eval -- "${|AS_RUN_TEST_CASES;}"

