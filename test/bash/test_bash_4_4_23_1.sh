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
    # local - ; set -x
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

# bash 4.4 的关联数组没有自动扩容机制，所以非常慢
# 50万个键是无法接收的
# 10万个键，3s，勉强能接受
# 20完个键，12s，已经很慢了
# 建议 bash 4.4 的hash 表不要超过 10万 个键
test_case3 ()
{
    local -A assoc=()
    time for i in {1..100000} ; do
        assoc[$i]=1
    done
}

test_case4 ()
{
    cat xx.txt > >(tee -a yy.txt)
    echo $?
}

test_case1 &&
test_case2 &&
test_case3 &&
test_case4

