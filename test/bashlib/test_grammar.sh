#!/usr/bin/env bash

. ../../src/bashlib/grammar.sh
. ../libs/test_utils.sh

test_case1 ()
{
    :
}

# step_test 9

eval -- "$(AS_RUN_TEST_CASES)"

