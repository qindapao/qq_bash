((_STR_IMPORTED++)) && return 0


# If you need an empty string, you can do it in the following way instead of splicing
# String concatenation is expensive operation in bash, it is better to use
# prototype template slicing
# https://github.com/akinomyoga/ble.sh/blob/master/src/util.sh
# _ble_string_prototype='        '
# function ble/string#reserve-prototype {
#   local n=$1 c
#   for ((c=${#_ble_string_prototype};c<n;c*=2)); do
#     _ble_string_prototype=$_ble_string_prototype$_ble_string_prototype
#   done
# }
# ## @fn ble/string#repeat str count
# ##   @param[in] str
# ##   @param[in] count
# ##   @var[out] ret
# function ble/string#repeat {
#   ble/string#reserve-prototype "$2"
#   ret=${_ble_string_prototype::$2}
#   ret=${ret// /"$1"}
# }
#
# ble/string#repeat "*" 5
# This way it is faster to pick 5 *
# 


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

str_is_decimal_positive_int ()
{
    [[ -z "$1" ]] && return 1
    [[ "$1" == "0" || ( -z "${1//[0-9]/}" && "$1" != 0* ) ]]
}

str_is_decimal_int ()
{
    [[ "${1:0:1}" == "-" ]] && set -- "${1:1}"
    str_is_decimal_positive_int "$1"
}


return 0

