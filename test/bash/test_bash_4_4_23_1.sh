#!/home/admin/bash

# ./ 执行脚本
# bash 4.4.3 的可执行文件放置到 /home/admin/ 目录下

test_case1 ()
{
    declare -p BASH_VERSION
    local a='1 2'
    echo ${a@Q}
    local -A assoc=([a]=b)
    declare -p assoc

}

test_case2 ()
{
    set -x
    local m=$'xxx xxx->xxx->xxx->xx:xx.x->(x \\ * @ xx:xx)->(xxxxx:xxxx)'
    local x=$'zy\n\t 133'
    local k='(xx:yy)'
    local n=$'gege\t \n tgeg223 \n tt223'
    declare -A dict_spec=([$'gege\t \n tgeg223 \n tt223(xx:yy)xxx xxx->xxx->xxx->xx:xx.x->(x \\ * @ xx:xx)->(xxxxx:xxxx)zy\n\t 133']="" )
    
    if [[ ${dict_spec[$n$k$m$x]+_} ]] ; then
        echo "ok"
    else
        echo "fail"
    fi

    if [[ ${dict_spec[$n$k$m$x]+_} ]] ; then
        echo "ok"
    else
        echo "fail"
    fi

    if [[ ${dict_spec[$n$k$m$x]+_} ]] ; then
        echo "ok"
    else
        echo "fail"
    fi
}

test_case1 &&
test_case2

