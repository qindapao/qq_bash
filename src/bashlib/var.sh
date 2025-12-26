((_VAR_IMPORTED++)) && return 0

# var_ as a reserved prefix

var_params_to_set ()
{
    local -A var_set=()
    local var_head=$1
    shift
    while (($#)) ; do
        var_set["$var_head$1"]=1 ; shift
    done
    REPLY="${var_set[*]@K}"
}

return 0

