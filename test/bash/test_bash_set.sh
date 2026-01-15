#!/usr/bin/env bash

. ../libs/test_utils.sh

# 测试 set 是否受 IFS 分词影响
# 结论: set 不会受 IFS 分词的影响
test_case1 ()
{
    local IFS='.'
    set -- a.b.c d.e.f

    if [[ "$1" == 'a.b.c' && "$2" == 'd.e.f' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case2 ()
{
    test_case2_inner ()
    {
        local - IFS=' '
        set -x
        local set_info=${ set -o;}
        if [[ "$set_info" =~ xtrace[[:blank:]]*on ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
    
        return 0
    }
    
    test_case2_inner
    local set_info=${ set -o;}
    if  [[ "$IFS" == $' \t\n' ]] &&
        [[ "$set_info" =~ xtrace[[:blank:]]*off ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"


