((_STR_IMPORTED++)) && return 0

#-------------------------------------------------------------------------------

# The current function is much faster than the following way of writing
# printf -v REPLY "%*s" "$2" "" ; REPLY=${REPLY// /"$1"}
str_repeat ()
{
    local str=$1 ; local -i len=$(($2*${#str}))
    while ((${#str} < len)) ; do str+=$str ; done
    REPLY=${str::len}
}

#-------------------------------------------------------------------------------

# $1: a string
# $2: b string
# REPLY
str_common_prefix ()
{
    local a=$1 b=$2
    ((${#a}>${#b})) && local a=$b b=$a
    b=${b::${#a}}
    if [[ $a == "$b" ]] ; then
        REPLY=$a ; return 0
    fi

    local l=0 u=${#a} m
    while ((l+1<u)); do
        ((m=(l+u)/2))
        if [[ ${a::m} == "${b::m}" ]]; then
            ((l=m))
        else
            ((u=m))
        fi
    done

    REPLY=${a::l}
}

#-------------------------------------------------------------------------------

# $1: a string
# $2: b string
# REPLY
str_common_suffix ()
{
    local a=$1 b=$2
    ((${#a}>${#b})) && local a=$b b=$a
    b=${b:${#b}-${#a}}
    if [[ $a == "$b" ]]; then
        REPLY=$a ; return 0
    fi

    local l=0 u=${#a} m
    while ((l+1<u)); do
        ((m=(l+u+1)/2))
        if [[ ${a:m} == "${b:m}" ]]; then
            ((u=m))
        else
            ((l=m))
        fi
    done

    REPLY=${a:u}
}

#-------------------------------------------------------------------------------

str_count ()
{
    [[ -z "$1" || -z "$2" ]] && {
        echo "null haystack or null needle!" >&2
        REPLY=-1
        return 1
    }
    local text=${1//"$2"}
    ((REPLY=(${#1}-${#text})/${#2}))
    return 0
}

#-------------------------------------------------------------------------------

str_is_decimal_positive_int ()
{
    [[ -z "$1" ]] && return 1
    [[ "$1" == "0" || ( -z "${1//[0-9]/}" && "$1" != 0* ) ]]
}

#-------------------------------------------------------------------------------

str_is_decimal_int ()
{
    [[ "${1:0:1}" == "-" ]] && set -- "${1:1}"
    str_is_decimal_positive_int "$1"
}

#-------------------------------------------------------------------------------

# $1: str
# $2: sep
str_split ()
{
    local str=$1 sep=$2
    local -a ret_arr=()
    local part=

    [[ -z "$sep" ]] && {
        local i ; for ((i=0; i<${#str}; i++)); do ret_arr+=("${str:i:1}") ; done
        REPLY=${ret_arr[*]@Q} ; return
    }

    [[ $str == *$'\034'* ]] || {
        local - ; set -f
        local old_ifs=$IFS IFS=$'\034'
        ret_arr=(${str//"$sep"/"$IFS"})
        IFS=$old_ifs ; REPLY=${ret_arr[*]@Q}
        return
    }

    while [[ $str == *"$sep"* ]]; do
        part=${str%%"$sep"*} ; ret_arr+=("$part") ; str=${str#*"$sep"}
    done
    [[ -n "$str" ]] && ret_arr+=("$str")

    REPLY=${ret_arr[*]@Q}
}

#-------------------------------------------------------------------------------

# str_cut
# ----------
# Extract a field from a string using a multi character separator.
#
# Arguments:
#   $1: str   – input string
#   $2: sep   – separator (must not be empty)
#   $3: count – field index
#
# Field indexing rules:
#   count >= 0 : 0-based forward indexing
#   count < 0  : -1 = last field, -2 = second last, etc.
#
# Behavior:
#   . If the field does not exist → return empty string (unlike awk)
#   . Multi-character separators are fully supported
#   . No external commands are used (pure Bash, high performance)
#
# Return values:
#   0  – success (field extracted OR field not found but no error)
#        REPLY contains the field or empty string if not found
#   1  – error (separator is empty)
#
# Performance notes:
#   . Cutting ~400,000 characters takes ~0.16 seconds
#   . For strings < 3000 characters, str_cut is significantly faster than awk (no fork)
#   . For very large strings (> 3000 characters), awk becomes faster (C engine)
#
# Examples:
#   str_cut "$str" ':' 0     # first field
#   str_cut "$str" ':' 2     # third field
#   str_cut "$str" ':' -1    # last field
str_cut ()
{
    local str=$1 sep=$2 cnt=$3
    [[ -z "$sep" ]] && { echo "sep:$sep can not be null!" >&2 ; return 1 ; }
    [[ "$str" == *"$sep"* ]] || return 0

    local transformed=$str
    if ((cnt>0)) ; then
        eval -- "transformed=\${str#${|str_repeat '*"$sep"' "$cnt";}}"
        # Length comparison takes much less time than direct string comparison
        ((${#transformed}==${#str})) && transformed=
        REPLY=${transformed%%"$sep"*}
    elif ((cnt<0)) ; then
        ((cnt!=-1)) && {
            eval -- "transformed=\${str%${|str_repeat '"$sep"*' "$((-cnt-1))";}}"
            (("${#transformed}"=="${#str}")) && transformed=
        }
        REPLY=${transformed##*"$sep"}
    else
        REPLY=${transformed%%"$sep"*}
    fi
}

#-------------------------------------------------------------------------------

# str_cuts "$str" ':' 2 ';' -1
str_cuts ()
{
    local str=$1
    local i sep cnt
    for((i=2;i<$#;i++)) ; do
        sep=${!i} ; let 'i++' ; cnt=${!i}
        str=${|str_cut "$str" "$sep" "$cnt";} || return $?
    done
    REPLY=$str
}

#-------------------------------------------------------------------------------

# e  -> 1
# 中 -> 3
# 😊 -> 4
str_bytes () { local LC_ALL=C; REPLY=${#1}; }

#-------------------------------------------------------------------------------

return 0

