#!/usr/bin/env bash

. ../libs/test_utils.sh

# 命令管道退出时候需要清除,但是协程不用
cleanup() {
    rm -f /tmp/fifo_in /tmp/fifo_out
}

trap cleanup EXIT INT TERM HUP


# Named pipes are slower than coroutines
test_case1 ()
{
    local old_dir=$PWD
    cd /tmp

    rm -f fifo_in fifo_out
    mkfifo fifo_in fifo_out || echo "mkfifo failed"

    ls -l fifo_in fifo_out

    # 1. 启动 awk（先打开读端）
    awk '
    {
        print "got:", $0
        fflush()
    }
    ' < fifo_in > fifo_out &
    awk_pid=$!

    # 2. 再打开写端和读端
    exec 3>fifo_in
    exec 4<fifo_out

    # 3. 通信
    time {
    echo "hello" >&3
    read line <&4
    echo "awk returned: $line"
    }
    time {
    echo "hello2" >&3
    read line <&4
    echo "awk returned: $line"
    }
    time {
    echo "hello3" >&3
    read line <&4
    echo "awk returned: $line"
    }
    time {
    echo "hello4" >&3
    read line <&4
    echo "awk returned: $line"
    }
    time {
    echo "hello5" >&3
    read line <&4
    echo "awk returned: $line"
    }

    cd $old_dir
}

test_case2 ()
{
    echo "-------- Running test_case2 (coproc awk) ----------"

    # 启动 awk 协程（持久进程）
    coproc AWKPROC {
        awk '
        {
            print "got:", $0
            fflush()
        }
        '
    }

    # AWKPROC[1] = 写入端（stdin）
    # AWKPROC[0] = 读取端（stdout）

    # 1
    time {
        echo "hello" >&"${AWKPROC[1]}"
        read line <&"${AWKPROC[0]}"
        echo "awk returned: $line"
    }

    # 2
    time {
        echo "hello2" >&"${AWKPROC[1]}"
        read line <&"${AWKPROC[0]}"
        echo "awk returned: $line"
    }

    # 3
    time {
        echo "hello3" >&"${AWKPROC[1]}"
        read line <&"${AWKPROC[0]}"
        echo "awk returned: $line"
    }

    # 4
    time {
        echo "hello4" >&"${AWKPROC[1]}"
        read line <&"${AWKPROC[0]}"
        echo "awk returned: $line"
    }

    # 5
    time {
        echo "hello5" >&"${AWKPROC[1]}"
        read line <&"${AWKPROC[0]}"
        echo "awk returned: $line"
    }
    time {
        echo "hegegegege gegeggllo5" >&"${AWKPROC[1]}"
        read line <&"${AWKPROC[0]}"
        echo "awk returned: $line"
    }

    local xx=$'gegeg1 23 4\ngege\n'
    # local xx="gege gegg "

    time {
        echo "$xx" >&"${AWKPROC[1]}"
        read all <&"${AWKPROC[0]}"
        echo "awk returned: $all"
    }

    # 取了名字的协程ID保存在 名字_PID 中
    # 最近的一次在 COPROC_PID 中
    echo "AWKPROC:$AWKPROC_PID"
    # 关闭协程
    exec {AWKPROC[1]}>&-
    wait "$AWKPROC_PID"
    
}

test_case3 ()
{
    # The default delimiter used by bc to trigger calculations is the newline
    # character.
    # bc -l loads the math library and sets the precision to 20
    coproc BC { bc -l; }

    time {
    echo "(2030+19)" >&"${BC[1]}"
    read result <&"${BC[0]}"
    echo "result:$result"
    }
    time {
    echo "(2030+19)" >&"${BC[1]}"
    read result <&"${BC[0]}"
    echo "result:$result"
    }
    time {
    echo "(29393*220.34)" >&"${BC[1]}"
    read result <&"${BC[0]}"
    echo "result:$result"
    }
    time for i in {0..100} ;do
        echo "(2939.34/930.32)" >&"${BC[1]}"
        read result <&"${BC[0]}"
        # echo "result:$result"
    done
}

# 通过\0来传送完整的字符串

test_case4 ()
{
    # 因为是常驻链接所以只能在主块中写代码，不能写END块
    # 因为 END 块只有在程序需要退出的时候才会执行的
    # 协程适合处理小数据，如果数据本身太大，那么通过管道发送回Bash的开销也
    # 会比较大,mapfile 也不会让速度更快
    #
    # 所有频繁的交互还是有用协程，但是大数据的低频交互还是用命令替换比较好

    local SI=$'\034'

    coproc AWKPROC {
        awk '
            # join 函数：把数组 a 从索引 s 到 e 用 sep 拼成一个字符串
            function join(a, s, e, sep,    out, i) {
                if (s > e) return ""
                out = a[s]
                for (i = s + 1; i <= e; i++) out = out sep a[i]
                return out
            }

            BEGIN {
            RS = "\0"
            MY_SEP = "\034"
            }
            {
            n = split($0, parts, MY_SEP)
            out = ""
            for (i=1; i<=n ; i++) {
                out = out MY_SEP "got: " parts[i]
            }

            printf("%s\0", out)
            fflush()
            }
        '
    }

    local my_arr=() i
    for i in {0..1000} ; do
        my_arr+=("${|rand_str;}$SI")
    done

    echo "str build end."

    local other=${my_arr[*]}

    result=()

    # 其实直接命令替换的速度反而是最快的
    time my_str=${
        awk '
            # join 函数：把数组 a 从索引 s 到 e 用 sep 拼成一个字符串
            function join(a, s, e, sep,    out, i) {
                if (s > e) return ""
                out = a[s]
                for (i = s + 1; i <= e; i++) out = out sep a[i]
                return out
            }

            BEGIN {
            RS = "\0"
            MY_SEP = "\034"
            }
            {
            n = split($0, parts, MY_SEP)
            out = ""
            for (i=1; i<=n ; i++) {
                out = out MY_SEP "got: " parts[i]
            }

            printf("%s", out)
            fflush()
            }
        ' <<<"$other";}
    echo "${#my_str}"

    echo 1_in
    printf '%s\0' "$other" >&"${AWKPROC[1]}"
    echo 1_out
    time IFS=$'\034' read -r -d $'\0' -a result -u "${AWKPROC[0]}"

    echo 2_in
    printf '%s\0' "$other" >&"${AWKPROC[1]}"
    echo 2_out
    time IFS=$'\034' read -r -d $'\0' -a result -u "${AWKPROC[0]}"
    
    echo "result: ${#result[@]}"
}


eval -- "${|AS_RUN_TEST_CASES;}"


