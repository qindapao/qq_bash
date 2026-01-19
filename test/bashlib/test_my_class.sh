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

    local i element_num=10

    time {
        local -a params=()
        local -a new_element_infos=()
        for((i=0;i<element_num;i++)) ; do
            params+=("$TR_VALUE_NULL_OBJ")
        done

        local -a "new_element_infos=(${|trie_push_leaf_fast root_obj '' "{ELEMENTS}$X" "${params[@]}";})"
    }

    local i
    time {
        for ((i=0;i<element_num*2;i+=2)) ; do
            local index=${new_element_infos[i]}
            local phy_token=${new_element_infos[i+1]}

            # Add a new element
            new_my_class "root_obj" "$index" "$phy_token" 'new1_value1' 'new1_value2' '2'

            local class=${root_obj[$phy_token{CLASS}$X]}
            local self=${root_obj[$phy_token{SELF}$X]}
            ${FN[$class.print_self]} $self
        done
    }

    # # Delete the last element
    local class=${root_obj[{CLASS}$X]}
    local self=${root_obj[{SELF}$X]}

    ${FN[$class.delete_last_element]} $self
    ${FN[$class.print_self]} $self

    ${FN[$class.haha]} $self

    ${FN[$class.cut_plus]} $self

    ${FN[$class.print_self]} $self
}

# step_test 1

eval -- "${|AS_RUN_TEST_CASES;}"

