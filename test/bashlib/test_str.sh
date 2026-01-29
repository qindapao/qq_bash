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


# step_test 9

eval -- "$(AS_RUN_TEST_CASES)"

