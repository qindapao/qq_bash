#!/usr/bin/env bash

. ../libs/test_utils.sh

# patsub_replacement 是 Bash 5.2+ 的特性
if ((BASH_VERSINFO[0] < 5 ||
     (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))) ; then
    echo "SKIP: patsub_replacement requires Bash 5.2+ (running $BASH_VERSION)"
    exit 0
fi

# patsub_replacement 是匹配一个模式
test_case1 ()
{
    (
        shopt -s patsub_replacement
        s="abc123xyz"
        s=${s/[a-z]*/[&]}
        if [[ "$s" == '[abc123xyz]' ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
    )
}

eval -- "$(AS_RUN_TEST_CASES)"

