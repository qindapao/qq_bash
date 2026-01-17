#!/usr/bin/env bash

. ../../src/bashlib/my_class.sh
. ../../src/bashlib/meta.sh
. ../libs/test_utils.sh

test_case1 ()
{
    bless_my_class 'my_class'
    bless_mid_class 'mid_class'
    bless_base_class 'base_class'

    declare -gA "root_obj=(${|trie_init "$TR_TYPE_OBJ";})"
    new_my_class "root_obj" 1 '' 'value1' 'value2' '0' 

    local i
    time {
        for i in {0..5} ; do
            # Add a new element
            local -a "new_element_info=(${|trie_push_leaf root_obj "{ELEMENTS}$X" "$TR_VALUE_NULL_OBJ";})"
            new_my_class "root_obj" "${new_element_info[@]}" 'new1_value1' 'new1_value2' '2'

            # local class=${root_obj[${new_element_info[1]}{CLASS}$X]}
            # local self=${root_obj[${new_element_info[1]}{SELF}$X]}
            # ${FN[$class.print_self]} $self
        done
    }

    # # Delete the last element
    local class=${root_obj[{CLASS}$X]}
    local self=${root_obj[{SELF}$X]}

    ${FN[$class.delete_last_element]} $self
    ${FN[$class.print_self]} $self

    # ${FN[$class.haha]} $self

    # ${FN[$class.cut_plus]} $self

    # ${FN[$class.print_self]} $self
}

eval -- "${|AS_RUN_TEST_CASES;}"

