#!/usr/bin/env bash

test_crash ()
{
a=$((009+1))
}

test_crash
if [[ $? -ne 0 ]] ; then
    echo "case 1"
fi

if ! test_crash ; then
    echo "case 2"
fi

test_crash || echo "case 3"

{ test_crash ; } || echo "case 4"

exit 0

