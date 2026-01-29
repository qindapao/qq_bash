((_MY_CLASS_IMPORTED++)) && return 0

# :TODO: The biggest problem with the current architecture is that the variable
# name is bound to the tree. If the object contains other objects, or the local
# variable is destroyed, it will be destroyed. Only one or more global trees
# should be initialized, and then all objects can only get IDs. These global
# trees can be understood as memory pools or namespaces.
#
# So now the object initialization function can only return the ID in a certain
# namespace (equivalent to the memory address). After the initialization object
# is attached to the global tree, the ID may change. The global variable name
# may still need to be passed in, but then it is not called a global variable.
# That is a namespace. We can also design more than one namespace.
#
# The current design is sufficient in most scenarios. If there are more complex
# requirements in the future, system needs to be redesigned. The current
# feature is that it is simple and fast. The structure is also clear.
#
# A simple fix currently implemented is that when the binding name of the
# object changes, we use the rebind_self atomic function to change the binding
# name, and then the object can be operated. After the operation is completed,
# the object can be stuffed back into the large object.

. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"
. "${BASH_SOURCE[0]%/*}/mid_class.sh"

#-------------------------------------------------------------------------------

setup_my_class ()
{
    local tr_s=$1 tr_i=$2 tr_k=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6

    trie_insert_token_dict  "$tr_s" "$tr_i" "$tr_k" \
                            "{CLASS}" "my_class" \
                            "{SELF}" "$tr_s $tr_i" \
                            "{P1}" "$tr_value1" \
                            "{P2}" "$tr_value2" \
                            "{CNT}" "$tr_cnt_demo" \
                            "{ELEMENTS}" "$TR_VALUE_NULL_ARR"
}

#-------------------------------------------------------------------------------

# ns: name space
new_my_class ()
{
    local tr_s=$1 tr_i=$2 tr_k=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6
    
    NS["$tr_s.$tr_i"]=$tr_k
    setup_my_class  "$tr_s" "$tr_i" "$tr_k" \
                    "$tr_value1" "$tr_value2" "$tr_cnt_demo" 

    # bless_my_class "$tr_s" "$tr_i" "$tr_k"

    return 0
}

#-------------------------------------------------------------------------------

bless_my_class ()
{
    # Bless the parent first and then bless self
    bless_mid_class "$@"
    bless my_class "$@"
}

#-------------------------------------------------------------------------------

cut_plus_my_class ()
{
    local -n tr_n=$1
    local tr_s=$1
    local tr_i=$2
    local tr_k=${NS[$tr_s.$tr_i]}

    local tr_class=${tr_n[$tr_k{CLASS}$X]}
    ${FN[$tr_class.SUPER.${FUNCNAME[0]}]} $tr_s $tr_i
    
    local tr_cnt=${tr_n[$tr_k{CNT}$X]}
    ((tr_cnt++))
    tr_n[$tr_k{CNT}$X]=$tr_cnt
}

#-------------------------------------------------------------------------------

special_my_my_class ()
{
    :
}

#-------------------------------------------------------------------------------

return 0

