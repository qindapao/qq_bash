((_STR_IMPORTED++)) && return 0

# str_ as a reserved prefix

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

return 0

