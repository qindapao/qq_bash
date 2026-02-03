#!/usr/bin/env bash

test_crash ()
{
a=$((009+1))
}

# 只有这种情况下 case 1-0 的代码才会被执行
test_crash
if [[ $? -ne 0 ]] ; then
    echo "case 1-0"
fi

# 这里分号的作用看起来不仅仅是开始下一个命令
# 这个开始的下一个命令看起来也是和上一个命令组合在一起的
test_crash ; if [[ $? -ne 0 ]] ; then
    echo "case 1-1"
fi

if ! test_crash ; then
    echo "case 2"
fi

test_crash || echo "case 3"

{ test_crash ; } || echo "case 4"

exit 0

