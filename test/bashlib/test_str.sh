#!/usr/bin/env bash

. ../../src/bashlib/str.sh
. ../libs/test_utils.sh

test_case1 ()
{
    local demo_str='*1*a*b'
    str_count "$demo_str" '*' ; local str_count=$REPLY
    if [[ "$str_count" == '3' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local demo_str="我是中文hahah中文文"
    str_count "$demo_str" '中文' ; local str_count=$REPLY
    if [[ "$str_count" == '2' ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    local demo_str="我是中文hahah中文文"
    str_count "$demo_str" '中x文' ; local str_count=$REPLY
    if [[ "$str_count" == '0' ]] ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    local demo_str=""
    str_count "$demo_str" '中x文' ; local str_count=$REPLY
    if [[ "$str_count" == '-1' ]] ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    return 0
}

test_case2 ()
{
    local str1=''
    local sep1=''
    local str2='xxyykkyy23'
    local sep2="904"
    local sep3='yy'
    local str3='xxyy'
    
    str_split "$str1" "$sep1"; local -a "arr1=($REPLY)"
    str_split "$str1" "$sep2"; local -a "arr2=($REPLY)"
    str_split "$str2" "$sep1"; local -a "arr3=($REPLY)"
    str_split "$str2" "$sep2"; local -a "arr4=($REPLY)"
    str_split "$str2" "$sep3"; local -a "arr5=($REPLY)"
    str_split "$str3" "$sep1"; local -a "arr6=($REPLY)"
    str_split "$str3" "$sep2"; local -a "arr7=($REPLY)"
    str_split "$str3" "$sep3"; local -a "arr8=($REPLY)"

    # declare -p arr1 arr2 arr3 arr4 arr5 arr6 arr7 arr8
    
    local -a arr1_s=()
    local -a arr2_s=()
    local -a arr3_s=([0]="x" [1]="x" [2]="y" [3]="y" [4]="k" [5]="k" [6]="y" [7]="y" [8]="2" [9]="3")
    local -a arr4_s=([0]="xxyykkyy23")
    local -a arr5_s=([0]="xx" [1]="kk" [2]="23")
    local -a arr6_s=([0]="x" [1]="x" [2]="y" [3]="y")
    local -a arr7_s=([0]="xxyy")
    local -a arr8_s=([0]="xx")

    if  assert_array a arr1 arr1_s &&
        assert_array a arr2 arr2_s &&
        assert_array a arr3 arr3_s &&
        assert_array a arr4 arr4_s &&
        assert_array a arr5 arr5_s &&
        assert_array a arr6 arr6_s &&
        assert_array a arr7 arr7_s &&
        assert_array a arr8 arr8_s ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    return 0
}

test_case3 ()
{
    local str1=$'a:;b:;c ggg \n \tge :;:;e'
    str_cut "$str1" ':;' 0;   local get_str1=${REPLY}
    str_cut "$str1" ':;' 1;   local get_str2=${REPLY}
    str_cut "$str1" ':;' 2;   local get_str3=${REPLY}
    str_cut "$str1" ':;' 3;   local get_str4=${REPLY}
    str_cut "$str1" ':;' 4;   local get_str5=${REPLY}
    str_cut "$str1" ':;' 5;   local get_str6=${REPLY}
    str_cut "$str1" ':x' 0;   local get_str7=${REPLY}
    str_cut "$str1" ':x' 1;   local get_str8=${REPLY}
    str_cut "$str1" '' 3;     local get_str9=${REPLY}

    str_cut "$str1" ':;' -1;   local get_str10=${REPLY}
    str_cut "$str1" ':;' -2;   local get_str11=${REPLY}
    str_cut "$str1" ':;' -3;   local get_str12=${REPLY}
    str_cut "$str1" ':;' -4;   local get_str13=${REPLY}
    str_cut "$str1" ':;' -5;   local get_str14=${REPLY}
    str_cut "$str1" ':;' -6;   local get_str15=${REPLY}
    str_cut "$str1" ':x' -1;   local get_str16=${REPLY}
    str_cut "$str1" ':x' -2;   local get_str17=${REPLY}
    str_cut "$str1" ''   -4;   local get_str18=${REPLY}

    if  [[ "$get_str1" == 'a' ]] &&
        [[ "$get_str2" == 'b' ]] &&
        [[ "$get_str3" == $'c ggg \n \tge ' ]] &&
        [[ "$get_str4" == '' ]] &&
        [[ "$get_str5" == 'e' ]] &&
        [[ "$get_str6" == '' ]] &&
        [[ "$get_str7" == '' ]] &&
        [[ "$get_str8" == '' ]] &&
        [[ "$get_str9" == '' ]] &&
        [[ "$get_str10" == 'e' ]] &&
        [[ "$get_str11" == '' ]] &&
        [[ "$get_str12" == $'c ggg \n \tge ' ]] &&
        [[ "$get_str13" == 'b' ]] &&
        [[ "$get_str14" == 'a' ]] &&
        [[ "$get_str15" == '' ]] &&
        [[ "$get_str16" == '' ]] &&
        [[ "$get_str17" == '' ]] &&
        [[ "$get_str18" == '' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    # 1. 字符串以分隔符开头
    str_cut ":;a:;b" ":;" 0 ; local get_str19=${REPLY}   # => ''
    str_cut ":;a:;b" ":;" 1 ; local get_str20=${REPLY}   # => 'a'

    # 2. 字符串以分隔符结尾
    str_cut "a:;b:;" ":;" -1 ; local get_str21=${REPLY}  # => ''

    # 3. 多个连续分隔符
    str_cut "a:;:;:;b" ":;" 1 ; local get_str22=${REPLY} # => ''
    str_cut "a:;:;:;b" ":;" 2 ; local get_str23=${REPLY} # => ''
    str_cut "a:;:;:;b" ":;" 3 ; local get_str24=${REPLY} # => 'b'

    # 4. 特殊字符分隔符
    str_cut       "a.*b.*c" '.*' 1 ;   local get_str25=${REPLY}  # => 'b'
    awk_cut_regex "a.*b.*c" '.*' 1 ;   local get_str26=${REPLY}  # => ''

    # 5. 字段包含分隔符子串
    str_cut "abc:;def:;ghi:;jkl:;mno:;xyz" ":;" 5 ; local get_str27=${REPLY} # => 'xyz'

    # 6. 空字符串
    str_cut "" ":;" 0 ; local get_str28=${REPLY}         # => ''

    if [[ "$get_str19" == '' ]] &&
        [[ "$get_str20" == 'a' ]] &&
        [[ "$get_str21" == '' ]] &&
        [[ "$get_str22" == '' ]] &&
        [[ "$get_str23" == '' ]] &&
        [[ "$get_str24" == 'b' ]] &&
        [[ "$get_str25" == 'b' ]] &&
        [[ "$get_str26" == '' ]] &&
        [[ "$get_str27" == 'xyz' ]] &&
        [[ "$get_str28" == '' ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    return 0
}

test_case4 ()
{
    local str=$'ggeeg:gege\nge;g \tgeg te中文t不对 aew:geeg ge;geg:'
    str_cuts "$str" ':' 1 ';' -1 ; local get_str=${REPLY}
    if [[ "$get_str" == $'g \tgeg te中文t不对 aew' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    str_cuts "$str" ':' 1 ';' -1 '中文' 1 ; local get_str1=${REPLY}
    if [[ "$get_str1" == $'t不对 aew' ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    return 0
}

test_case5 ()
{
    local i str
    for i in {0..70} ; do
        rand_str
        str+=${REPLY}
    done
    str_cut "$str" ':' 89 ; local get_str=${REPLY}
    # awk here is the fastest in transmitting data through pipes.
    # <<< On the contrary, it is slower
    get_str_awk=$( printf '%s' "$str" | awk -F ':' '{print $90}' )
    
    if [[ "$get_str" == "$get_str_awk" ]] ; then
        log_test 1 1
    else
        log_test 0 2 ; return 1
    fi
    return 0
}

test_case6 ()
{
    local str1= str2=

    str_repeat 'x*y' 1000000 ; str2=${REPLY}
    if  [[ "${#str2}" == '3000000' ]] && 
        [[ "${str2:0:6}" == 'x*yx*y' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    return 0
}

test_case7 ()
{
    local my_str="ee中中😊😊"
    str_bytes "$my_str" ; local -i bytes_num=$REPLY
    if (( bytes_num == (2+3*2+4*2) )) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case8 ()
{
    local LC_ALL=en_US.UTF-8
    local LANG=en_US.UTF-8
    local my_str='xgeg中文2233svsg23中文2233'

    str_index_of "$my_str" '中文' 1 ; local -i index1=${REPLY}
    str_index_of "$my_str" '中文' 2 ; local -i index2=${REPLY}
    str_index_of "$my_str" '中文' 3 ; local -i index3=${REPLY}
    
    if [[ "$index1" == '4' && "$index2" == '16' && "$index3" == '-1' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case9 ()
{
    local str=$'gege\nge中文ge 12\t gege 2e\nge中文ge 12\t g中\n ge\t文e\nge中文ge 12\t g不对'
    local sep=$'e\nge中文ge 12\t g'
    str_cut "$str" "$sep"  0;      local get_str1=${REPLY}
    str_cut "$str" "$sep"  1;      local get_str2=${REPLY}
    str_cut "$str" "$sep"  2;      local get_str3=${REPLY}
    str_cut "$str" "$sep"  3;      local get_str4=${REPLY}
    str_cut "$str" "$sep"  4;      local get_str5=${REPLY}
    str_cut "$str" "$sep"  5;      local get_str6=${REPLY}
    str_cut "$str" "$sep" -1;      local get_str7=${REPLY}
    str_cut "$str" "$sep" -2;      local get_str8=${REPLY}
    str_cut "$str" "$sep" -3;      local get_str9=${REPLY}
    str_cut "$str" "$sep" -4;      local get_str10=${REPLY}
    str_cut "$str" "$sep" -5;      local get_str11=${REPLY}
    str_cut "$str" "$sep" -6;      local get_str12=${REPLY}

    declare -- get_str1_s="geg"
    declare -- get_str2_s="ege 2"
    declare -- get_str3_s=$'中\n ge\t文'
    declare -- get_str4_s="不对"
    declare -- get_str5_s=""
    declare -- get_str6_s=""
    declare -- get_str7_s="不对"
    declare -- get_str8_s=$'中\n ge\t文'
    declare -- get_str9_s="ege 2"
    declare -- get_str10_s="geg"
    declare -- get_str11_s=""
    declare -- get_str12_s=""
    
    if  [[ "$get_str1" == "$get_str1_s" ]] &&
        [[ "$get_str2" == "$get_str2_s" ]] &&
        [[ "$get_str3" == "$get_str3_s" ]] &&
        [[ "$get_str4" == "$get_str4_s" ]] &&
        [[ "$get_str5" == "$get_str5_s" ]] &&
        [[ "$get_str6" == "$get_str6_s" ]] &&
        [[ "$get_str7" == "$get_str7_s" ]] &&
        [[ "$get_str8" == "$get_str8_s" ]] &&
        [[ "$get_str9" == "$get_str9_s" ]] &&
        [[ "$get_str10" == "$get_str10_s" ]] &&
        [[ "$get_str11" == "$get_str11_s" ]] &&
        [[ "$get_str12" == "$get_str12_s" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    return 0
}

test_case10 ()
{
    local test_str=$'中文\nxxx是对的的确是对的\n哥哥xxx'
    local part1 part2 part3

    awk_cut "$test_str" '对的' 0 ; part1=$REPLY
    awk_cut "$test_str" '对的' 1 ; part2=$REPLY
    awk_cut "$test_str" '对的' 2 ; part3=$REPLY

    if [[ "$part1" == $'中文\nxxx是' ]] &&
        [[ "$part2" == "的确是" ]] &&
        [[ "$part3" == $'\n哥哥xxx' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case11 ()
{
    local result
    local -i pass=0 fail=0
    local -a fail_msgs=()

    local bs='\'   # 用于安全构造字面反斜杠

    _t11_check ()
    {
        local _name=$1 _expected=$2
        if [[ "$result" == "$_expected" ]]; then
            ((pass++))
        else
            ((fail++))
            fail_msgs+=("$_name: got [$result], expected [$_expected]")
        fi
    }

    # ---- 1. 快速路径：纯 ASCII + 换行 ----
    local input1=$'hello\nworld'
    str_escape_keep_nl "$input1" result
    _t11_check "case1_ascii_nl" "$input1"

    # ---- 2. 快速路径：含中文 ----
    local input2=$'我是中文hahah中\n\n文文'
    str_escape_keep_nl "$input2" result
    _t11_check "case2_chinese" "$input2"

    # ---- 3. 快速路径：空字符串 ----
    str_escape_keep_nl "" result
    _t11_check "case3_empty" ""

    # ---- 4. 中速路径：反斜杠 ----
    local input4="a${bs}b${bs}c"
    local expected4="a${bs}${bs}b${bs}${bs}c"
    str_escape_keep_nl "$input4" result
    _t11_check "case4_backslash" "$expected4"

    # ---- 5. 中速路径：\b \f \r \t ----
    local input5=$'a\bb\fc\rd\te'
    local expected5="a${bs}bb${bs}fc${bs}rd${bs}te"
    str_escape_keep_nl "$input5" result
    _t11_check "case5_ctrl_shorthand" "$expected5"

    # ---- 6. 慢速路径：C0 控制字符 (\x01, \x02) ----
    local input6=$'a\x01b\x02c'
    local expected6="a${bs}u0001b${bs}u0002c"
    str_escape_keep_nl "$input6" result
    _t11_check "case6_c0" "$expected6"

    # ---- 7. 慢速路径：DEL (\x7f) ----
    local input7=$'a\x7fb'
    local expected7="a${bs}u007fb"
    str_escape_keep_nl "$input7" result
    _t11_check "case7_del" "$expected7"

    # ---- 8. 慢速路径：C1 (CSI \x9b) ----
    # 在 UTF-8 环境下 0x9b 是非法的，但函数应该能按码点正确处理
    local input8=$'a\x9bb'
    local expected8="a${bs}u009bb"
    str_escape_keep_nl "$input8" result
    _t11_check "case8_c1_csi" "$expected8"

    # ---- 9. 慢速路径：单引号不崩溃 ----
    local input9=$'a\'b\x01c'
    local expected9="a'b${bs}u0001c"
    str_escape_keep_nl "$input9" result
    _t11_check "case9_quote" "$expected9"

    # ---- 10. 混合场景：中文 + 反斜杠 + Tab + C0 + 单引号 + 双引号 + 换行符 ----
    local input10=$'中文\\n\t\x01单引\'引号\nxx\n"'
    local expected10=$'中文\\\\n\\t\\u0001单引\'引号\nxx\n"'
    str_escape_keep_nl "$input10" result
    _t11_check "case10_mixed" "$expected10"

   # ---- 11. 慢速路径：单引号 + C0（确保 printf 容错生效） ----
    local input11=$'\'\x01\''
    local expected11="'${bs}u0001'"
    str_escape_keep_nl "$input11" result
    _t11_check "case11_quote_c0" "$expected11" 

    # ---- 12. 终极混合大用例：包含所有控制字符（C0 / DEL / C1）----
    local input12=$'中文abc\\\n\t\r\b\f单\'双"\x01\x02\x03\x04\x05\x06\x07\x0B\x0E\x0F\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x7F'
    local expected12=$'中文abc\\\\\n\\t\\r\\b\\f单\'双"\\u0001\\u0002\\u0003\\u0004\\u0005\\u0006\\u0007\\u000b\\u000e\\u000f\\u0010\\u0011\\u0012\\u0013\\u0014\\u0015\\u0016\\u0017\\u0018\\u0019\\u001a\\u001b\\u001c\\u001d\\u001e\\u001f\\u007f'

    # 动态追加合法的 UTF-8 C1 控制字符 (\xC2\x80 到 \xC2\x9F)
    local i hex
    for i in {128..159}; do
        printf -v hex '%02x' "$i"
        input12+=$(printf "\\xC2\\x$hex")
        printf -v hex '\\u%04x' "$i"
        expected12+="$hex"
    done

    str_escape_keep_nl "$input12" result
    _t11_check "case12_ultimate_all_ctrls" "$expected12"

    # ---- 汇总 ----
    if (( fail == 0 )); then
        log_test 1 11
    else
        local m
        for m in "${fail_msgs[@]}"; do
            echo "$m" >&2
        done
        log_test 0 11
        return 1
    fi

    return 0
}

# step_test 11

eval -- "$(AS_RUN_TEST_CASES)"

