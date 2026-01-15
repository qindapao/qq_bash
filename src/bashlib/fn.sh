((_FN_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/var.sh"


#-------------------------------------------------------------------------------

# declare -a a=(1 2 3 4)
# fn_callback ()
# {
#   REPLY=$(($1+1))
# }
# It must be lowercase k when passed in
# fn_map_inplace "${a[@]@k}" a fn_callback
# for in list          fastest
# for((i=0;i<len;i++)) slightly faster
# The current function is the slowest
fn_map_inplace ()
{
    while (($#>2)) ; do
        printf -v ${@: -2:1}['${1}'] "%s" "${|${@: -1} "$2";}"
        shift 2
    done
}

#-------------------------------------------------------------------------------

fn_map ()
{
    :
}

#-------------------------------------------------------------------------------


return 0

