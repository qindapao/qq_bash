#!/usr/bin/env bash

. ../libs/test_utils.sh

if [[ "${BASH_GRAMMAR[current_shell_process_replace]}" == 1 ]] ; then
test_case1 ()
{
    test_case1_innser ()
    {
        return 5
    }
    local ret
    ret=${|test_case1_innser;}
    local ret_code=$?
    if ((ret_code==5)) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    return 0
}
fi

test_case2 () { : ; }

eval -- "$(AS_RUN_TEST_CASES)"


